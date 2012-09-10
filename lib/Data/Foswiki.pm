package Data::Foswiki;

use 5.006;
use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(serialise deserialise);

=head1 NAME

Data::Foswiki - Read and Write Foswiki topics

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';

=head1 SYNOPSIS

Quickly read and write Foswiki topics into a hash

    use Data::Foswiki;

    #read
    my $fh;
    open($fh, '<', '/var/lib/foswiki/data/System/FAQSimultaneousEdits.txt') or die 'open failure';
    my @topic_text = <$fh>;
    close($fh);
    my $topic = Data::Foswiki::Test2::deserialise(@topic_text);
    
    $topic->{TOPICINFO}{author} = 'NewUser';
    $topic->{PARENT}{name} = 'WebHome';
    
    $topic->{TEXT} = "Some new text\n\n".$topic->{TEXT};
    undef $topic->{TOPICMOVED};
    
    $topic->{FIELD}{TopicTitle}{attributes} = 'H';
    
    #add a new field that is not part of the form definition - if edited within foswiki, it willbe removed
    #but its useful for importing
    $topic->{FIELD}{NewField}{value} = 'test';
    
    #write
    open($fh, '>', '/var/lib/foswiki/data/System/FAQNewFaq.txt') or die 'write failure';
    print $fh Data::Foswiki::Test::serialise($topic);
    close($fh);
    

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 deserialise($text|@stringarray) -> $hash_ref

Parse a string, or array of strings and convert into a hash of the Foswiki topic's data

(apparently Perl can be faster reading a file into an array)

if you pass in an undef / empty string, you will get undef back

=cut

my $METAINFOregex   = qr/^\%META:(TOPICINFO){(.*)}\%\n?$/o;
my $METAPARENTregex = qr/^\%META:(TOPICPARENT){(.*)}\%\n?$/o;
my $METAregex       = qr/^\%META:(\S*){(.*)}\%\n?$/o;

sub deserialise {
    my $topic;

    return $topic unless ( $#_ >= 0 );

    #convert a string into an array
    if ( $#_ == 0 ) {
        return $topic if ( $_[0] eq '' );
        if ( $_[0] =~ /\n/ ) {
            return deserialise( split( /\n/, $_[0] ) );
        }
    }

    my $start = 0;
    my $end   = -1;

    #I can test $_[$start] rather than defined($_[$start])
    #  because an empty line still would not match the regex
    # first get rid of the leading META
    if ( $_[$start] && $_[$start] =~ $METAINFOregex ) {
        $topic->{$1} = _readKeyValues($2);
        $start++;
    }
    if ( $_[$start] && $_[$start] =~ $METAPARENTregex ) {
        $topic->{$1} = _readKeyValues($2);
        $start++;
    }

    #then the trailing META
    my $trailingMeta;
    while ( $_[$end] && $_[$end] =~ $METAregex ) {

#should skip any TOPICINFO & TOPICPARENT, they are _only_ valid in one place in the file.
        last if ( ( $1 eq 'TOPICINFO' ) || ( $1 eq 'TOPICPARENT' ) );

        $trailingMeta = 1;
        $end--;

        my $meta = _readKeyValues($2);
        if ( $1 eq 'FORM' ) {
            $topic->{$1} = $meta;
        }
        else {
            if ( exists( $meta->{name} ) && $1 ne 'FORM' ) {
                $topic->{$1}{ $meta->{name} } = $meta;
            }
            else {
                $topic->{$1} = $meta;
            }
        }
    }

    #there is an extra newline added between TEXT and any trailing meta
    $end-- if ( $trailingMeta && $_[$end] =~ /^\n?$/o );

    if ( $_[$start] ) {

 #TODO: not joining and just returning an arrayref is ~200 topics/s faster again
 #but leaves the user to work out if there are \n's
        $topic->{TEXT} =
          join( ( ( $_[$start] =~ /\n/o ) ? '' : "\n" ), @_[ $start, $end ] );
    }
    return $topic;
}

=head2 serialise($hashref) -> string

Serialise into a foswiki 'embedded' formatted string, ready for writing to disk.

Note: this does not take care of updating the topic revision and date data

=cut

sub serialise {
    my $topic        = shift;
    my @ordered_keys = qw/TOPICINFO TOPICPARENT TEXT FORM TOPICMOVED FIELD/;
    my @topic_keys   = keys(%$topic);

    #I thought there was an extra \n added..
    #my $key_count    = $#topic_keys;
    my @text;

    my %done;
    foreach my $type ( @ordered_keys, @topic_keys ) {
        if ( !$done{$type} ) {
            $done{$type} = 1;

            #$key_count--;
            if ( $type eq 'TEXT' ) {
                push( @text, $topic->{TEXT} )
                  ;    # . ( $key_count >= 0 ? "\n" : '' );
            }
            else {
                push( @text, _writeMeta( $type, $topic->{$type} ) );
            }
        }
    }

    #TODO: how about using wantarray to avoid the join?
    return join( "\n", @text );
}

#from Foswiki::Meta
# STATIC Build a hash by parsing name=value comma separated pairs
# SMELL: duplication of Foswiki::Attrs, using a different
# system of escapes :-(
sub _readKeyValues {
    my @arr = split( /="([^"]*)"\s*/, $_[0] );

    #if the last attribute is an empty string, we're a bit naf
    my $count = $#arr;
    push( @arr, '' ) unless ( $count % 2 );
    my $res;
    for ( my $i = 1 ; $i <= $count ; $i = $i + 2 ) {
        $arr[$i] =~ s/%([\da-f]{2})/chr(hex($1))/geio;
        $res->{ $arr[ $i - 1 ] } = $arr[$i];
    }

    return $res;
}

sub _writeMeta {
    my $type = shift;
    my $hash = shift;

    my @elements = _writeKeyValues( $type, $hash );
    unless ( $elements[0] =~ /^%META/ ) {
        return '%META:' . $type . '{' . join( ' ', @elements ) . '}%';
    }
    return @elements;
}

sub _writeKeyValues {
    my $type = shift;
    my $hash = shift;

    return map {

        #        if (exists($hash->{$_}{name}) && $hash->{$_}{name} eq $_) {
        #print STDERR "---".$hash->{$_}."-".ref($hash->{$_})."--\n";
        if ( ref( $hash->{$_} ) eq 'HASH' ) {

            #META:TYPE{name=} hash of entries
            _writeMeta( $type, $hash->{$_} );
        }
        else {
            $_ . '="' . _dataEncode( $hash->{$_} ) . '"';
        }
    } keys( %{$hash} );
}

sub _dataDecode {
    my $datum = shift;

    $datum =~ s/%([\da-f]{2})/chr(hex($1))/gei;
    return $datum;
}

sub _dataEncode {
    my $datum = shift;

    $datum =~ s/([%"\r\n{}])/'%'.sprintf('%02x',ord($1))/ge;
    return $datum;
}

=head1 AUTHOR

Sven Dowideit, C<< <SvenDowideit at fosiki.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-data-foswiki at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Data-Foswiki>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

Foswiki support can be found in the #foswiki irc channel on L<irc://irc.freenode.net>, 
or from SvenDowideit L<mailto:SvenDowideit@fosiki.com>


=head1 ACKNOWLEDGEMENTS

=head1 TO DO

make an XS version, and try a few different approaches to parsing and then benchmark them
this would mean making this module into a facade to the other implementations.

is it faster not to modify the array? (just keep start and end Text indexes?)

=head1 LICENSE AND COPYRIGHT

Copyright 2012 Sven Dowideit SvenDowideit@fosiki.com.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;    # End of Data::Foswiki::Test

package Data::Foswiki;

use 5.006;
use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(serialise deserialise);

=head1 NAME

Data::Foswiki - Read and Write Foswiki topics

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

Quickly read and write Foswiki topics into a hash

    use Data::Foswiki;

    #read
    my $fh;
    open($fh, '<', '/var/lib/foswiki/data/System/FAQSimultaneousEdits.txt') or die 'open failure';
    my @topic_text = <$fh>;
    close($fh);
    my $topic = Data::Foswiki::deserialise(@topic_text);
    
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
    print $fh Data::Foswiki::serialise($topic);
    close($fh);
    

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 deserialise($text|@stringarray) -> $hash_ref

Parse a string, or array of strings and convert into a hash of the Foswiki topic's data

(apparently Perl can be faster reading a file into an array)

=cut

sub deserialise {
    my @str = @_;
    my %topic = ( 'TEXT', '' );

    #convert a string into an array
    if ( $#str == 0 ) {
        @str = split( /\n/, $str[0] );
    }

    # first get rid of the leading META
    if ( defined( $str[0] ) && $str[0] =~ /\%META:(TOPICINFO){(.*?)}\%\n?$/ ) {
        my $type   = $1;
        my $params = $2;
        my %meta;
        _parse_params( $type, $params, \%meta, qw/author date version format/ );
        $topic{$type} = \%meta;
        shift(@str);
    }
    if ( defined( $str[0] ) && $str[0] =~ /\%META:(TOPICPARENT){(.*?)}\%\n?$/ )
    {
        my $type   = $1;
        my $params = $2;
        my %meta;
        _parse_params( $type, $params, \%meta, qw/name/ );
        $topic{$type} = \%meta;
        shift(@str);
    }

    #then the trailing META
    my $trailingMeta;
    while ( ( $#str >= 0 ) && $str[$#str] =~ /\%META:(.*?){(.*?)}\%\n?$/ ) {
        $trailingMeta = 1;
        my $type   = $1;
        my $params = $2;
        pop(@str);

        #should skip any TOPICINFO & TOPICPARENT, they are _only_ valid in one place in the file.
        next if (($type eq 'TOPICINFO') || ($type eq 'TOPICINFO'));

        my %meta;
        if ( $type eq 'FORM' ) {
            _parse_params( $type, $params, \%meta, qw/name/ );
            $topic{$type} = \%meta;
        }
        else {
            _parse_params( $type, $params, \%meta );
            if ( exists( $meta{name} ) ) {
                $topic{$type}{ $meta{name} } = \%meta;
            }
            else {
                $topic{$type} = \%meta;
            }
        }
    }

    #there is an extra newline added between TEXT and any trailing meta
    pop(@str) if ( $trailingMeta && $str[$#str] =~ /^\n?$/ );

    #and thus we're left with the topic text
    if ( defined( $str[0] ) ) {

        #decide if the TEXT array already has \n at the ends
        my $separator = "\n";
        $separator = '' if ( $str[0] =~ /\n/ );
        $topic{TEXT} = join( $separator, @str );
    }
    else {

        #        $topic{TEXT} = '';
    }

    return \%topic;
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

sub _parse_params {
    my ( $metaname, $str, $meta, @attrs ) = @_;
    my $args = _readKeyValues($str);
    if ( $#attrs >= 0 ) {
        map { $meta->{$_} = $args->{$_} if ( exists( $args->{$_} ) ); } @attrs;
    }
    else {
        map { $meta->{$_} = $args->{$_} } keys(%$args);
    }
}

#from Foswiki::Meta
# STATIC Build a hash by parsing name=value comma separated pairs
# SMELL: duplication of Foswiki::Attrs, using a different
# system of escapes :-(
sub _readKeyValues {
    my ($args) = @_;
    my %res;

    # Format of data is name='value' name1='value1' [...]
    $args =~ s/\s*([^=]+)="([^"]*)"/
      $res{$1} = _dataDecode( $2 ), ''/ge;

    return \%res;
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

1;    # End of Data::Foswiki

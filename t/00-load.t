#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Data::Foswiki' ) || print "Bail out!\n";
}

diag( "Testing Data::Foswiki $Data::Foswiki::VERSION, Perl $], $^X" );

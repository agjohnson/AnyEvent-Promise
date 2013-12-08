#!perl -T
use 5.008;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'AnyEvent::Promise' ) || print "Bail out!\n";
}

diag( "Testing AnyEvent::Promise $AnyEvent::Promise::VERSION, Perl $], $^X" );

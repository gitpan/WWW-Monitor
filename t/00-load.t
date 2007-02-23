#!perl

use Test::More tests => 2;

BEGIN {
  use_ok( 'WWW::Monitor::Task');
  use_ok( 'WWW::Monitor' );
}

diag( "Testing WWW::Monitor $WWW::Monitor::VERSION, Perl $], $^X" );

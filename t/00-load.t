#!perl -T

use Test::More tests => 3;

BEGIN {
  use_ok( 'WWW::Monitor::Task');
  use_ok( 'WWW::Monitor' );
  ok ( WWW::Monitor->new() );
}

diag( "Testing WWW::Monitor $WWW::Monitor::VERSION, Perl $], $^X" );

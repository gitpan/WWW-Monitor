#!perl

use Test::More tests => 3;

BEGIN {
  use_ok( 'WWW::Monitor::Task');
  use_ok( 'WWW::Monitor' );
  ok(system('perl','blib/script/webmon.pl' ,'--version') == 0,'webmon.pl is runnable');
}

diag( "Testing WWW::Monitor $WWW::Monitor::VERSION, Perl $], $^X" );

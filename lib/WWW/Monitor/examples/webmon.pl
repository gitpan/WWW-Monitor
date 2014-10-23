#!/usr/bin/perl
########################################################################
# Filename: webmon.pl - Version 1.0                                    #
# Author:   Yaron Kahanovitch <yaron at kahanovitch dor com>           #
#                                                                      #
# Usage: webmon.pl --conf=filename                                     #
#                                                                      #
# Scans a  list  of web  adderesses and compares  them with pre-cached #
# pages version.  If a change is detected, a mail notification is      #
# being sent.  webmon.pl use  WWW::Monitor  as the  primary engine to  #
# perform monitoring. Mail   is being  sent  via MIME::Lite, and       #
# Scheduling  is   being  done   by  using   Schedule::Cron  mechanism #
#                                                                      #
# Copyright   2007  Yaron Kahanovitch, all     rights reserved.  This  #
# program is free software; you  can redistribute it and/or modify  it #
# under the same terms as Perl itself.                                 #
########################################################################

use Getopt::Long;
use MIME::Lite;
use WWW::Monitor;
use Schedule::Cron;
use Cache::File;
use Carp;

$VERSION = 1.0;

$CONFIG = '/etc/webmon.conf';
$LOGPATH = "";
$LAST_ERROR = "";
$FROM="";
$SUBJECT="";
%RECIPIENTS = ();

GetOptions ( 'help'      => \&HELP_MESSAGE,
	     'version'   => sub { VERSION_MESSAGE();exit(0);},
	     'conf=s'    => \$CONFIG) or HELP_MESSAGE();

#HELP_MESSAGE() unless $ARGV[0];

croak "Given configuration file, $CONFIG, cannot be located" unless (-f $CONFIG);
my $conf = read_configuration($CONFIG) or croak "Cannot read configuration file $CONFIG. $LAST_ERROR";
#dump_conf($conf);
unless (exists ($conf->{query})) { warn "No queries given ";exit(0);}

#Setting up mail fileds.
$FROM = $conf->{from}[-1] if (exists $conf->{from});
$SUBJECT=$conf->{subject}[-1] if (exists $conf->{subject});
$MAIL_METHOD = "sendmail";
$MAIL_METHOD=$conf->{mail_method}[-1] if(exists($conf->{mail_method}));
$SMTP_SERVER=$conf->{smtp_server}[-1] if(exists($conf->{smtp_server}));
$SMTP_TIMEOUT=$conf->{smtp_server}[-1] if(exists($conf->{smtp_server}));


#Preparing Log directory.
$LOG_NOTIFICATIONS="";
$LOG_NOTIFICATIONS=$conf->{log_notification} if (exists($conf->{log_notification}));
$LOGPATH = $conf->{log_mail_dir}[-1] if (exists $conf->{log_mail_dir});
if ($LOGPATH and ! -d $LOGPATH and !mkdir($LOGPATH)) { 
  print STDERR "Cannot Create directory $LOGPATH.$! \n";
}

#Setting up cache object.
my $cache_root = '/var/cache/monitor';

#Initialize Cron object
my $cron =  new Schedule::Cron(sub { return 1;});

if (exists $conf->{cache_root}     and
    scalar(@{$conf->{cache_root}})) {
  $cache_root =  $conf->{cache_root}[-1];
} 


#Setting up cache object
if (!-d $cache_root and !mkdir($cache_root)) {
  print STDERR "Cannot create directory $cache_root \n";
  exit 255;
}
$cache = Cache::File->new( cache_root => $cache_root);

#Setting up queries
my $indx = 0;
foreach my $query (@{$conf->{query}}) {
  ++$indx;
  foreach my $reserved_word ("url","sampling_rate") {
    unless (exists $query->{$reserved_word}) { 
      print STDERR "Missing $reserved_word in query $indx\n";
      exit (255);
    }
  }
  #Initializing WWW::Monitor object

  my $mon = WWW::Monitor->new('MAIL_CALLBACK'=>\&notify,'CACHE'=>$cache);
  foreach my $url (@{$query->{url}}) {
    my $task = $mon->watch("$url");
    log_notification("Watching ",$url);
    $RECIPIENTS{$task}=$query->{mailto};
  }
  foreach my $cron_samp (@{$query->{sampling_rate}}) {
    log_notification ("sampling_rate = ",$cron_samp);
    $cron->add_entry($cron_samp,\&run_query,$mon);
  }
}

log_notification ("Started\n********");

$cron->run();


sub run_query {
  my $mon = shift;
  log_notification("Testing: ",join("\n",$mon->targets));
  $mon->run or log_notification("Query ended with error",$mon->errors);
  return 1;
}



#Basic parser. Configuration should have the format key=value. Nesting can be achieved by specifing sub parts. For example query start....end specify sub part names query.
sub read_configuration {
  my $q_file = shift;
  open QFILE,"<$q_file" or do{ report_error("Cannot open $q_file for read.$!"); return 0;};
  my $res = {};
  my $lineNum = 0;
  read_configuration_recursive(\*QFILE,$res,\$lineNum) or return 0;
  close QFILE;
  return $res;
}


sub read_configuration_recursive {
  my $qfile = shift;
  my $res = shift;
  my $lineNum = shift;
  while (<$qfile>) {
    ++$$lineNum;
    chomp;
    $_ =~ s/#.*//;
    $_ =~ s/^\s+//;
    next if ($_ eq "");
    return 1 if ($_ eq "end");
    my @fields = split("=",$_);
    if (scalar(@fields) >= 2) {
      my $a1 = $fields[0];
      my $a2 = join("=",@fields[1..$#fields]);
      $res->{$a1} = [] unless (exists ($res->{$a1}));
      push @{$res->{$a1}},$a2;
      next;
    }
    if (/(\S+)\s+start/) {
      my $key = $1;
      my $inner = {};
      $res->{$key} = [] unless(exists $res->{$key});
      push @{$res->{$key}},$inner;
      read_configuration_recursive($qfile,$inner,$lineNum) or return 0;
      next;
    }
    report_error("parse error at line $$lineNum ($_)");return 0;
  }
  return 1;
}

sub VERSION_MESSAGE {
    print "$0 $VERSION (C) 2007 Yaron Kahanovitch.\n";
}

sub HELP_MESSAGE {
    VERSION_MESSAGE();
    print <<EOT;
usage: $0 --conf=<configuration file name> 
options:
  --conf=file          Configuration file name. Deafault $CONFIG
EOT
exit 0;
}

sub report_error {
  $LAST_ERROR = @_;
  return 1;
}

#mail notification callback
sub notify {
  my ($url,$text,$task) =@_;
  foreach my $recipient (@{$RECIPIENTS{$task}}) {
    my $mail_obj = 
      MIME::Lite->new(To      => $recipient,
		      From    => $FROM,
		      Subject => $SUBJECT,
		      Type    => 'Text',
		      Data    => 'For details visit '.$url."\n".$text
		     );
    
    if ($MAIL_METHOD ne "sendmail") {
      $mail_obj->send('smtp',$SMTP_SERVER,$SMTP_TIMEOUT) or 
	log_notification("smtp send to $recipient ended with error");
    } else {
      $mail_obj->send or log_notification("sendmail to $recipient ended with error");
    }
    if ($LOG_NOTIFICATIONS ne "") {
      log_notification("To: $recipient\n","url = $url\n","text = $text\n");
    }
  }
  return 1;
}

#Simple log sub.
sub log_notification {
  return 1 unless ($LOGPATH);
  my @message = @_;
  open HIST,">>$LOGPATH/www-monitor-log" or print STDERR "Cannot open log file.$! \n";
  my $message_frmt = join("",(HTTP::Date::time2str(time()),"==>",@message,"\n"));
  print HIST $message_frmt,"\n*******************************************************\n";
  close HIST;
}
	     
sub dump_conf {
  my $conf = shift;
  while (my ($key,$val) = each %$conf) {
    print "$key ==> $val \n";
  }
  return 1;
}

__END__

=pod

=head1 NAME

webmon.pl - monitor websites for updates and changes

=head1 OPTIONS

=over

=item --conf=<filename>

A configuration file to be used. See bellow example of such a file. 

=item --help

Short help message

=back

=head1 EXAMPLES

=head2 example of configuation file

     ########################################################################
     # webmon.conf.example - Yaron Kahanovitch - Feb 2007                   #
     #                                                                      #
     #                                                                      #
     # Example for webmon configuration file                                #
     ########################################################################

     #cache_root - Cache repository Root directory.	
     cache_root=/var/cache/monitor

     #log_mail_dir - optional -Every notification will be kept under that directory
     log_mail_dir=/var/log/monitor

     #from - mail address to be filed in the from field. <More than one
     from=user1@host1
     from=user2@host2

     #subject - A subject line for mail messages.
     subject=Web alert, web page changed!!!

     #mail_method - <sendmail | smtp> - Method for sending mail. default - sendmail.
     mail_method=sendmail

     #smtp_server - smtp server.used only if mail_method=smtp. 
     #smtp_server=smtp.myisp.net

     #smtp_timeout - Time out to be used if smtp mail metho is in use. Valid only if mail_method=smtp.
     smtp_timeout=60 #seconds

     #log_notifications - Log every outgoing mail notification.
     log_notifications=yes

     #query start - start a new query
     query start

          #url - One or more targets url to be monitored.
	  url=http://www.target1.org
	  url=http://another.one/any_web_page.html
	  #sampling_rate=  (Taken from crontab(5), "Vixie" cron) 
          #               specification of the scheduled time in crontab
	  #               format (crontab(5)) which contains five mandatory time and
	  #               date fields and an optional 6th column. fields are:
          #               minute         0-59
          #               hour           0-23
          #               day of month   1-31 
          #               month          1-12 (or as names)
          #               day of week    0-7 (0 or 7 is Sunday, or as names )
          #               seconds        0-59 (optional)
          #               A field may be an asterisk (*), which always stands for
          #               ``first-last''. For details please visit 
          #              for details visit 
          #              http://search.cpan.org/~roland/Schedule-Cron-0.97/Cron.pm
          #
	  #               In the following example the query is being executed every minute
	  sampling_rate=0-59/1 * * * *

	  #mailto - specify mail addresses to be notify upon query notification
	  mailto=user1@host1
          mailto=user2@host2
     end

=head2 Invoking webmon.pl from command line

>perl webmon.pl --conf=/etc/webmon.conf

=head1 COPYRIGHT

Copyright   2007  Yaron Kahanovitch, all     rights reserved.  This  
program is free software; you  can redistribute it and/or modify  it 
under the same terms as Perl itself.

=head1 AUTHOR

Yaron Kahanovitch <yaron at kahanovitch dot com>

=head1 README

Scans list of web pages and compares them with its pre-cached
counterparts.  If a change is detected then a mail notification is
being send.  webmon.pl uses WWW::Monitor as the primary engine to
perform monitoring.




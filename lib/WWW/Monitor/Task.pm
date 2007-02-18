#WWW/monitor.pm. Written in 2007 by Yaron Kahanoitch.  This
# source code has been placed in the public domain by the author.
# Please be kind and preserve the documentation.


package WWW::Monitor::Task;


#use 5.008;
use warnings;
use strict;
use HTTP::Response;
use HTTP::Request;
use HTTP::Headers;
use HTTP::Status;
use Text::Diff;
use HTML::TreeBuilder;
#use Carp;



our(@ISA, @EXPORT, @EXPORT_OK, $VERSION);

$VERSION = 0.11;

@ISA = qw(
	  Exporter
	 );
@EXPORT = qw ();
@EXPORT_OK = qw ();

our $HASH_SEPARATOR = "\n";
our $HASH_KEY_PREFIX = "__HASH_KEY__";

=head1 NAME

WWW::Monitor::Task - A Task class for monitoring single web page
against cached version.

=head1 VERSION

Version 0.1

=cut

=head1 Description

This class responsible for tracking a single web page and report
changes.  This class should be considered as private asset of
L<WWW::Monitor>.  For details please refer to <WWW::Monitor>

=head1 EXPORT

=head1 FUNCTIONS

=head2 new 

A constructor.

=cut

sub new {
  my $this = shift;
  my %arg;
  unless (@_ % 2) {
    %arg = @_;
  } else {
    carp ("Parameters for WWW::Monitor::Task should be given as pair of 'OPTION'=>'VAL'");
  }
  my  $class = ref($this) || $this;
  my  $self = {};
  carp ("Url is not given") unless exists $arg{URL};
  $self->{url} = $arg{URL};
  $self->{cache} = $arg{CACHE};
  bless($self, $class);
}

=head2 run ( mechanize, carrier, <cache>)

Executes Task.  Parameters: 

mechanize - Web mechanize object.

L<WWW::Monitor::Task> assumes that the given object implements or
inherits WWW::mechnize abstraction. See
L<http://search.cpan.org/~petdance/WWW-Mechanize-1.20/lib/WWW/Mechanize.pm>.

carrier- Object that that will conduct the notification See L<WWW::Monitor> for details

cache - optional - A cache class. 

=cut

sub run {
  my $self = shift;
  $self->{error} = "";
  my ($mechanize,$carrier) = (shift,shift);
  my $cache = "";
  if (@_) { $cache = shift;}
  my $url_i = $self->{url};
  $self->{cache} = $cache if ($cache);
  my $responses = {};

  #Get Url data. Output data is stored in the hash ref $responses.
  $self->get_url_data($mechanize,$url_i,$responses) or return 0;

  #Compares Pages list eith cache.
  my ($url_keys_for_comapre,$old_pages_to_compare,$new_pagets_to_compare,$missing_pages,$added_pages,$existsInCache) = $self->sync_cache($url_i,$responses);

  #If a page does not exists in cache we don't want to notify on this.
  return 1 unless ($existsInCache);

  #Activate Notification.
  $self->be_notified($carrier,$url_i,$missing_pages,$added_pages,$old_pages_to_compare,$new_pagets_to_compare,$url_keys_for_comapre);
  return 1;
}

=head2 be_notified

(Private method)
Tests if a page is tested. If yes notification call back is being called.

=cut

sub be_notified {
  my $self = shift;
  my $notify_ind = 0;
  my ($carrier,$url,$missing_pages,$added_pages,$old_pages_to_compare,$new_pages_to_compare,$url_keys_for_comapre) = @_;
  my $cache = $self->{cache};
  my $ret = 1;
  my @messages;
  #Extract textual information from missing pages.
  my $notify_ind1 = $self->extract_text($missing_pages,"Cannot find the following parts:",\@messages);

  #Extract added information from added pages.
  my $notify_ind2 = $self->extract_text($added_pages,"Found new parts in url:",\@messages);
  my $index = 0;

  #Go over on all pages that exists in cache and perform textual comparation
  if (@$old_pages_to_compare) {
    push @messages,"The following parts has been changed since last visited:";
    while ($index < scalar(@$old_pages_to_compare)) {
      my $t1 = $self->format_html($old_pages_to_compare->[$index]);
      my $t2 = $self->format_html($new_pages_to_compare->[$index]);
      if ($$t1 ne $$t2) {
	$cache->set($url_keys_for_comapre->[$index],${$new_pages_to_compare->[$index]});
	$notify_ind = 1;
	push @messages,diff($t1,$t2,{ STYLE => "Context" });
      }
      ++$index;
    }
  }

  
  #If notification is requried, perform it.
  if ($notify_ind or $notify_ind1 or $notify_ind2) {
    $self->store_validity($url,time());
    return $carrier->notify($url,join("\n",@messages),$self);
  } else { return 1;}
}

=head2 format_html

(Private method)
Return a textual version of an html.

=cut

sub format_html {
  my $self = shift;
  my $html_ref = shift;
  my $tree = HTML::TreeBuilder->new->parse($$html_ref);
  my $formatter = HTML::FormatText->new(leftmargin => 0, rightmargin => 50);
  my $ret = $formatter->format($tree);
  return \$ret;
}

=head2 extract_text 

(Private Method).
Extract text from given set of pages. 

=cut

sub extract_text {
  my $self = shift;
  my $pages = shift;
  my $textHeader = shift;
  my $messages = shift;
  my $notif_ind = 0;
  my @texts = ();
  foreach my $part (values %$pages) {
    my $tmp = $self->format_html($part);
    push @texts,$$tmp unless ($$tmp =~ m/^\s*$/);
  }
  if (@texts) {
    push @$messages,$textHeader;
    push @$messages,@texts;
    $notif_ind = 1;
  }
  return $notif_ind;
  
}

=head2 get_hash_cache_key

(Private method)
Return a hash key that stores information about the whole visibe part URL.

=cut

sub get_hash_cache_key {
  my $self = shift;
  my $url = shift;
  return $HASH_KEY_PREFIX.$url;
}

=head2 get_cache_hash

(Private Method)
Returns all urls that was last cached.
return true if the url was previously hased.

=cut

sub get_cache_hash {
  my ($self,$url,$is_cached_site) = @_;
  my $cache = $self->{cache};
  my $ret = {};
  $$is_cached_site = 1;
  my $hash_key = $self->get_hash_cache_key($url);
  $cache->exists($hash_key) or do { $$is_cached_site = 0;return 0;};
  foreach $hash_key (split($HASH_SEPARATOR, $cache->get($hash_key))) {
    my $tmp = $cache->get($hash_key);
    $ret->{$hash_key} = \$tmp;
  }
  return $ret;
}

=head2 store_validity

(Private method)
Store current time in the main hash key

=cut

sub store_validity {
  my ($self,$url) = (@_);
  my $cache = $self->{cache};
  my $hash_key = $self->get_hash_cache_key($url);
  $cache->set_validity($hash_key,time()) if ($cache->exists($hash_key));
  return 1;
  
}

=head2 store_cache_hash

Store General information of a web adderess. This includes all frames and dates.

=cut

sub store_cache_hash {
  my ($self,$url,$data,$added_data,$deleted_data) = (@_);
  my $cache = $self->{cache};
  my $hash_key = $self->get_hash_cache_key($url);
  my $header = join($HASH_SEPARATOR,keys %$data);
  $cache->set($hash_key,join($HASH_SEPARATOR,keys %$data));
  while (my ($key,$value) = each %$added_data) {
    $cache->set($key,$$value);
    $cache->set_validity($key,time());
  }
  while (my ($key2,$value2) = each %$deleted_data) {
    $cache->purge($key2,$value2);
  }
  return 1;
}

=head2 sync_cache

(Private method)

=cut


#sync_cache (Privatre method) takes newly retreived data and store and compares it with the cache data.
#That is, It returns as follows:
# might_be_changed - Urls that are includes in the retreived pages and in in the cache. Those pages are potentialy changed,
#therefore should be examinated by HTML comperator.
#deleted_data - Pages that exists in cache and not in the new set.
#added_data - Pages that exists only in the new version.
#In addition the sub purge all deletd pages from cache and store the added pages.
#From performance reasons all the "might_be_changed" pages are not cached. This is left for the caller to do.
sub sync_cache {
  my ($self,$url,$new_data_http) = @_;
  my $cache = $self->{cache};
  my $is_cached_site;
  my $old_data = $self->get_cache_hash($url,\$is_cached_site);
  my ($added_data,$deleted_data) = ({},{});
  my @old_pages_to_compare;
  my @new_pages_to_compare;
  my @url_keys_for_comapre;
  my $index_new = 0;my $index_old = 0;
  my @new_keys = sort (keys %$new_data_http);
  my @old_keys = ($old_data)?(sort(keys %$old_data)):();
#  print "Scalars: ", scalar(@new_keys), "==",scalar(@old_keys),"\n";
  while ($index_new < scalar(@new_keys) and $index_old < scalar(@old_keys)) {
    if ($new_keys[$index_new] eq $old_keys[$index_old]) { 
      if ($new_data_http->{$new_keys[$index_new]}->code() != RC_NOT_MODIFIED) {
	push @old_pages_to_compare, $old_data->{ $old_keys[$index_old]};
	my $content = $new_data_http->{$new_keys[$index_new]}->content;
	push @new_pages_to_compare, \$content;
	push @url_keys_for_comapre,$new_keys[$index_new];
      }
      ++$index_old;++$index_new;next;
    }
    if ($new_keys[$index_new] lt $old_keys[$index_old]) { 
      my $content = $new_data_http->{$new_keys[$index_new]}->content;
      $added_data->{$new_keys[$index_new]} = \$content;
      ++$index_new;
      next;
    }
    $deleted_data->{$old_keys[$index_old]} = $old_data->{$old_keys[$index_old]};
    ++$index_old;next;
  }
  while ($index_new < scalar(@new_keys)) {
    my $content = $new_data_http->{$new_keys[$index_new]}->content;
    $added_data->{$new_keys[$index_new]} = \$content;
    ++$index_new;
  }
  while ($index_old < scalar(@old_keys)) {
    $deleted_data->{$old_keys[$index_old]} = $old_data->{$old_keys[$index_old]};
    ++$index_old;
  }
#  print "Goota cache\n";
  $self->store_cache_hash($url,$new_data_http,$added_data,$deleted_data) or die ("Cannot store $url in cache");
  return (\@url_keys_for_comapre,\@old_pages_to_compare,\@new_pages_to_compare,$deleted_data,$added_data,$is_cached_site);
}

=head2 get_url_data

(Private method)

=cut

#get_url_data go recursively on all the pages that construct a given web page (That includes all type of included 
#frames and dynamic pages) and retreive them into a given hash reference ($response.
sub get_url_data {
  my $self = shift;
  my $mechanize = shift;
  my $url = shift;
  my $responses = shift;
  my $cache = $self->{cache};
  my $r = HTTP::Request->new('GET',$url);
  if ($cache->exists($url)) {
    my $validity = $cache->validity($url);
    $r->header('If-Modified-Since'=>HTTP::Date::time2str($cache->validity($url))) if ($validity);
  }
  my $response = $mechanize->request( $r );

  if ($response->code() == 304) {
    $response->content($cache->get($url));
    $mechanize->_update_page($r,$response);
  } elsif(!($self->{status} = $response->is_success())) {
    $self->{error} = $response->status_line;
    return 0;
  }
  $responses->{$url} = $response;
  my $frames = [];
  my $output = $mechanize->find_all_links( tag_regex => qr/^([ia]?frame)$/i);
  push @$frames,@$output if ($output);
  $output = $mechanize->find_all_links( tag_regex => qr/meta/);
  push @$frames,@$output if ($output);

  foreach my $link (@$frames) {
    next unless ($link->url_abs =~ m%^http.*//%);
    unless (exists $responses->{$link->url_abs()}) {
      $self->get_url_data($mechanize,$link->url_abs(),$responses) or return 0;
    }
  }
  return 1;
}

=head2 success 

return true upon success on the last run execution.

=cut

sub success {
  my $self = shift;
  return $self->{status};
}


=head1 AUTHOR

Yaron Kahanovitch, C<< <yaron-helpme at kahanovitch.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-www-monitor at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=WWW-Monitor>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command. perldoc WWW::Monitor
You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/WWW-Monitor>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/WWW-Monitor>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=WWW-Monitor>

=item * Search CPAN

L<http://search.cpan.org/dist/WWW-Monitor>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2007 Yaron Kahanovitch, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

1;				# End of WWW::Monitor::Task

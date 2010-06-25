#!/usr/bin/perl

$| = 1;

use warnings;
use strict;

use Config::Abstract::Ini;
use Data::Dumper;
use Data::ICal;
use Data::ICal::Entry::Event;
use Date::Manip;
use File::Basename;
use Net::Google::Calendar;
use Storable;

Date_Init("ConvTZ=UTC");

my $username = '';
my $password = '';
my $path = '';
my $file = '';

my $settings;
my $settings_file = '.' . basename($0) . '.ini';
my $default_file = basename($0) . '.ics';

if (! -e $settings_file) {
    die "No config file found: $settings_file";
} else {
    $settings = (new Config::Abstract::Ini($settings_file))->get_all_settings->{'config'};
    
    $username = $settings->{'username'};
    $password = $settings->{'password'};
    $path = $settings->{'path'} || './';
    $file = $settings->{'file'} || $default_file;

    $file = $path . '/' . $file;
}

die Dumper($settings) if not $file;

my $debug = 0;
my $ics;

if (-e $file) {
	# load from file
	$ics = Data::ICal->new(filename => $file);
} else {
	$ics = Data::ICal->new();
}

my $start_ics = $ics->as_string;

my $cal;
print "Getting events\n";
for (&getEvents()) {

	my $uid = $_->id;
	my ($entry, $success) = &entryExists($uid);
	my ($t_entry, $t_success) = &entrySameAge($_->updated);
	
	# find out if this entry already exists in $ics
	if ($success && $t_success) {
		print sprintf("\t\tNot adding %s, it already exists and is the same age\n", $_->title);
		next;
	}
	
	my $event = Data::ICal::Entry::Event->new();
	my ($start, $end, $all_day) = $_->when;

	if (! defined($entry)) {
		print sprintf("\t\tAdding event %s updated %s", $_->title, $_->updated);
	} else {
		print sprintf("\t\tUpdating event %s", $_->title);
		$event = $entry;
	}
	
	if ($_->when) {
		$event->add_properties(
			'dtstart' => $start->strftime('%Y%m%dT%H%M%SZ'), # 20060306T050000Z
			'dtend' => $end->strftime('%Y%m%dT%H%M%SZ'),
		);
		print sprintf(" on %s", $start->strftime('%Y%m%dT%H%M%SZ'));
	}
	
	if ($_->recurrence) {
		my $frequency = $_->recurrence->properties->{'rrule'}[0]->value;
		
		# 'FREQ=MONTHLY;INTERVAL=1;UNTIL=20090102T050000Z;BYDAY=1FR'
		
		$event->add_property(
			'rrule' => $frequency
		);
	}
	print "\n";

	$event->add_properties(
		'summary' => $_->title,
		'description' => $_->content->body,
		'organizer' => 'CN=' . $_->author->name . ':mailto:' . $_->author->email,
		'location' => $_->location,
		'transp' => $_->transparency,
		'last-modified' => $_->updated,
		'uid' => $_->id,
	);
	$ics->add_entry($event);
}

my $end_ics = $ics->as_string;

if ($start_ics ne $end_ics) {
	open(ICS, ">:utf8", $file);
	# print $ics->as_string;
	print ICS $ics->as_string;
	close(ICS);
}

sub getEvents {
	my @object;
	print "\tAuthenticating to Google\n";
	# this will get you a read-write feed. 
	eval {
		$cal = Net::Google::Calendar->new;
		$cal->login($username, $password);
	};
	if ($@) {
		die "Couldn't connect to google. $@";
	}

	print "\tAuthentication complete\n\n";

	my $c;
	for ($cal->get_calendars) {
		$c = $_ if ($_->title eq 'Glen Solsberry');
	}
	$cal->set_calendar($c);

	my $min_date = ParseDate("1 month ago");
	my $max_date = ParseDate("+1 hour");
	
	print "\tFetching data\n";
	@object = $cal->get_events(
		'max-results' => 10000,
		'updated-min' => UnixDate($min_date, '%OZ'), # 2005-08-09T10:57:00-08:00
		'updated-max' => UnixDate($max_date, '%OZ') # 2005-08-09T10:57:00-08:00
	);
	print sprintf("\t\t%s -- %s\n", UnixDate($min_date, '%OZ'), UnixDate($max_date, '%OZ')) if $debug;
	print "\tFetched all data\n";
	return @object;	
}

sub entryExists {
	my ($id) = @_;
	
	my $entries = $ics->entries;
	
	foreach my $entry (@$entries) {
		if (defined($entry->property('uid'))) {
			my $uid = $entry->property('uid')->[0]->value;
		
			if ($uid eq $id) {
				return ($entry, 1);
			}
		}
	}
	return (undef, 0);
}

sub entrySameAge {
	my ($updated) = @_;
	
	my $entries = $ics->entries;
	
	foreach my $entry (@$entries) {
		if (defined($entry->property('last-modified'))) {
			my $last_mod = $entry->property('last-modified')->[0]->value;
			
			if ($last_mod eq $updated) {
				return ($entry, 1);
			}
		}
	}
	return (undef, 0);
}

#!/usr/bin/perl

# * * * * * * * * * * * * * *
# Acknoledgment von Nagios notifications per mail replay
# ! Nach einer Aenderung der Mail-Templates muss die Subroutine "mailread" 
# ggf. angepasst werden.
# * * * * * * * * * * * * * *

use strict;
use warnings;
use lib '/omd/versions/default/lib/perl5/lib/perl5';
use Monitoring::Livestatus;
use Data::Dumper;
use feature qw/say switch/;

my $ls = undef;
my $contact = undef;

# Infos aus der Mail
my $mail = {
        from => undef,
        type => undef,
        host => "",
        service => "",
        state => undef,
        message => undef,
    };

# Livestatus Parameter
my $h = {
    socket => "$ENV{'OMD_ROOT'}/tmp/run/live",
    host => {
        get => "hosts",
        cols => "name alias state acknowledged comments_with_extra_info",
        filter => undef,
    },
    service => {
        get => "services",
        cols =>  "host_name description state acknowledged comments_with_extra_info",
        filter => undef,
    },
    contact => {
        get => "contacts",
        cols => "name email",
        filter => undef,
    },
};

# Eingehende Mail parsen
sub mailread{
    # Entfernern von Steuerzeichen bei OWA
    $_ =~ s/=..=//g;
    given ($_) {
    when ($_ =~ /^From\s+(.*\@.*\.\w+)\ .*$/ ) {$mail->{from}=lc($1)};
    when ($_ =~ /^\W+(\w+)-ALERT.*$/) {$mail->{type}=lc($1)};
    when ($_ =~ /^\W+Hostname:\s+(\w+).*$/) {$mail->{host}=$1};
    when ($_ =~ /^\W+Service:\s+(.*)$/) {$mail->{service}=$1};
    when ($_ =~ /^\W+State:\s+(\w+).*$/) {
        given ($1) {
	when ('OK') {$mail->{state}='0'}
	when ('WARNING') {$mail->{state}='1'}
	when ('DOWN') {$mail->{state}='1'}
	when ('CRITICAL') {$mail->{state}='2'}
	when ('UNREACHABLE') {$mail->{state}='2'}
	when ('UNKNOWN') {$mail->{state}='3'}
	default {$mail->{state}='4'}
	}
    };
    when ($_ =~ /^\s*\back\w*\b\s+(.*)$/i) {$mail->{message}=$1};
    };
};

# Livestatus abfrage
sub live{
    my $t = shift;
    my $ml = Monitoring::Livestatus->new(socket => $h->{socket});
    #$ml->errors_are_fatal(0);
    my $r = $ml->selectrow_hashref("GET $h->{$t}->{get}\n".
                                   "Columns: $h->{$t}->{cols}\n".
                                   "Filter: $h->{$t}->{filter}\n");
                               #if($Monitoring::Livestatus::ErrorCode) {
                               #    croak($Monitoring::Livestatus::ErrorMessage);
                               #};
    return ($r);
};

# COMMAND an Livestatus schicken
sub put{
    my $m = shift;
    my $ml = Monitoring::Livestatus->new(socket => $h->{socket});
    $ml->do("COMMAND $m\n");
};

# Achnowledgment pruefen und durchfuehren
sub ack{
    my $type = shift;
    my $live = shift;
    my $contact = shift;
    my $message = undef;
    if (($live->{state} eq $mail->{state}) && ($live->{acknowledged} eq '0')) {
        my $TIME=time;
	if ($type eq "host") {
            # ACKNOWLEDGE_HOST_PROBLEM;<host_name>;<sticky>;<notify>;<persistent>;<author>;<comment>
            my $message = "[$TIME] ACKNOWLEDGE_HOST_PROBLEM;$mail->{host};0;1;0;$contact->{name};$mail->{message}";
            &put($message);
	}elsif ($type eq "service"){
            # ACKNOWLEDGE_SVC_PROBLEM;<host_name>;<service_description>;<sticky>;<notify>;<persistent>;<author>;
            my $message = "[$TIME] ACKNOWLEDGE_SVC_PROBLEM;$mail->{host};$mail->{service};0;1;0;$contact->{name};$mail->{message}";
            &put($message);
	};
    }elsif (($live->{state} eq $mail->{state}) && ($live->{acknowledged} ne '0')) {
        # Acknowledgment besteht bereits
	exit 0;
    }else{
        # Status hat bereits gewechselt
	exit 0;
    };
};

# Einlesen der Mail von STDIN
while (<>) {
    &mailread($_);
};

# Abbruch falls die Mail nicht korrekt eingelesen wurde
foreach (values %$mail) {
    if (!defined $_) {
        say "ERROR during Mail Parsing";
        exit 1;
    };
};

# Livestatus-Filter nachtraeglich in den Hash schieben
$h->{host}->{filter} = "host_name = $mail->{host}";
$h->{service}->{filter} = "host_name = $mail->{host}\nFilter: description = $mail->{service}";
$h->{contact}->{filter} = "email = $mail->{from}";

# Main
given ($mail->{type}) {
    when ('host') {$ls = &live($mail->{type});
        $contact = &live('contact');
        &ack($mail->{type},$ls,$contact);
    }
    when ('service') {$ls = &live($mail->{type});
        $contact = &live('contact');
        &ack($mail->{type},$ls,$contact);
    }
    default {say "ERROR"; exit 1}
    };

exit 0;

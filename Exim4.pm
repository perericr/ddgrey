# ---- class Reporter::Exim4 ----
# Exim4 log reporter

package DDgrey::Reporter::Exim4;

use strict;
use integer;

use Data::Dumper; # DEBUG
use Date::Manip;
use Digest::MD5 qw(md5_hex);
use DDgrey::Perl6::Parameters;

use parent qw(DDgrey::TailReporter);

my $ip_re='[\d\.\:]+';
my $host_re='(?:\S+\s+\(\S+\)|\S+)\s+\[('.$ip_re.')\]';

# ---- constructor ----

sub new($class){
    # return:  new reporter of class from config
    # effect:  registers with select
    #          starts subprocess
    #          may raise exception

    my $file=($main::config->{exim4_mainlog} // '/var/log/exim4/mainlog');
    my $self=$class->SUPER::new($file);
    $self->{current}={};
    main::lm("following exim4 mainlog $file","exim4");
    return $self;
};

# ---- methods -----

sub service($self){
    # return: name of subsystem (for logging)
    return "exim4";
};

sub receive_line($self,$line){
    # effect: receives line, possibly makes report
    chomp $line;

    # configuration
    my $unknown = $main::config->{exim4_unknown} // 'verify';
    
    # extract date
    $line=~s/^(\d+\-\d+\-\d+ \d+\:\d+\:\d+)\s*//;
    my $date=$1 ? ParseDate($1) : undef;
    if(!$date){
	main::lm("unknown date in exim4 log ($line)","exim4","warning");
	return;
    };
    my $time=UnixDate($date,"%s");

    # unexcepted disconnect from MTA
    if($line=~/^unexpected disconnection while reading SMTP command from $host_re \(error: Connection reset by peer\)/){
	my $report=DDgrey::Report->new({
	    event=>'disconnect',
	    ip=>$1,
	    time=>$time,
	    reporter=>"exim4"
        });
	$self->report($report);
	return;
    };

    # unknown recipient (from special early logging clauses in ACL)
    if($line=~/^H=$host_re Warning: unknown recipient (\S+) from (\S+)/){
	if($unknown eq 'verify'){
	    my $report=DDgrey::Report->new({
		event=>'unknown',
		ip=>$1,
		e_from=>$3,
		e_to=>$2,
		time=>$time,
		reporter=>"exim4"
	    });
	    $self->report($report);
	};
	return;
    };
    
    # spam
    if($line=~/^(\S+) F=(\S+) H=$host_re P=esmtp rejected by local_scan\(\)\: Rejected\b/){
	my $report=DDgrey::Report->new({
	    event=>'spam',
	    mta_id=>$1,
	    e_from=>$2,
	    ip=>$3,
	    time=>$time,
	    reporter=>"exim4"
        });
	$self->report($report);
	return;
    };

    # relay
    if($line=~/^H=$host_re F=<(\S+)> rejected RCPT <(\S+)>\: relay not permitted\b/){
	my $report=DDgrey::Report->new({
	    event=>'relay',
	    ip=>$1,
	    e_from=>$2,
	    e_to=>$3,
	    time=>$time,
	    reporter=>"exim4"
        });
	$self->report($report);
	return;
    };

    # unknown recipient
    if($line=~/^H=$host_re F=<(\S+)> rejected RCPT <(\S+)>\: Unrouteable address\b/){
	if($unknown eq 'delivery'){
	    my $report=DDgrey::Report->new({
		event=>'unknown',
		ip=>$1,
		e_from=>$2,
		e_to=>$3,
		time=>$time,
		reporter=>"exim4"
	    });
	    $self->report($report);
	};
	return;
    };
    
    # external message accepted
    if($line=~/^(\S+) \<\= (\S+) H=$host_re/){
	$self->{current}->{$1}={
	    exim_id=>$1,
	    from=>$2,
	    ip=>$3
	};
	return;
    };
    if($line=~/^(\S+) \<\= (\S+) U=\S+ P=local\b/){
	$self->{current}->{$1}={
	    exim_id=>$1,
	    from=>$2,
	};
	return;
    };
    
    if($line=~/^(\S+)\s+(.*)$/ and defined($self->{current}->{$1})){
	my $exim_id=$1;
	my $rest=$2;

	# to-lines
	if($rest=~/^\=\> (\S+?\s+)?\<(\S+)\>/){
	    $self->{current}->{$exim_id}->{to}->{$2}=1;
	    return;
	};
	if($rest=~/^\=\> (\S+)/){
	    $self->{current}->{$exim_id}->{to}->{$1}=1;
	    return;
	};
	
	# message done, make report
	if($rest=~/^Completed\b/){
	    # skip local IP:s
	    if(!defined($self->{current}->{$exim_id}->{ip})){
		return;
	    };
	    
	    for my $to (keys %{$self->{current}->{$exim_id}->{to}}){
		my $report=DDgrey::Report->new({
		    event=>'ok',
		    mta_id=>$exim_id,
		    e_from=>$self->{current}->{$exim_id}->{from},
		    e_to=>$to,
		    ip=>$self->{current}->{$exim_id}->{ip},
		    time=>$time,
		    reporter=>"exim4"
		});
	        $self->report($report);
	    };
	    delete $self->{current}->{$exim_id};
	    return;
	};
    };

    # other to skip, for debug
    # $line=~/^Start queue run:/ and return;
    # $line=~/^End queue run:/ and return;
    # $line=~/^\S+ Message is frozen\b/ and return;
    # $line=~/^\S+ Unfrozen by errmsg timer\b/ and return;
    # $line=~/^unexpected disconnection while reading SMTP command\b/ and return;
    # $line=~/^SMTP command timeout on connection\b/ and return;
    # $line=~/^\S+ SA\:/ and return;
    # $line=~/^\S+ DKIM\:/ and return;
    # $line=~/^no IP address found for host\b/ and return;
    # $line=~/^no host name found for IP address\b/ and return;
    # $line=~/\S+ $host_re Network is unreachable/ and return;
    # $line=~/H=$host_re F=<\S+> temporarily rejected RCPT <\S+>\: greylisted\b/ and return;
    # warn "$line\n";
};

sub report($self,$report){
    # effekt: send report to dispatcher
    
    $main::debug > 1 and main::lm("sending report ".$report->unicode(),"exim4");
    $main::dispatcher->report($report);
};

# ---- package init ----
return 1;

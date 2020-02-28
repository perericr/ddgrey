# ---- class ReadClient ----
# read connection to server

package DDgrey::ReadClient;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

use DDgrey::Report;
use DDgrey::Sync;

use parent qw(DDgrey::Client);

# ---- constructor ----

sub new($class,$config){
    # return: new read client of class connecting to config argument 0

    my $self=$class->SUPER::new($config);

    # always start subscription after OK helo
    $self->{on_helo}=sub{$self->subscribe()};

    main::lm("read client querying $self->{host}:$self->{port} started",$self->service());
    return $self;
};

# ---- methods ----

sub service($self){
    # return: name of subsystem (for logging)
    return "read client";
};

sub close_fh($self){
    # effect: closes own fh

    delete($self->{subscribed});
    $self->SUPER::close_fh();
};

sub subscribe($self){
    # effect: starts subscription

    my $last=DDgrey::Sync->last_fetched($self->{peername});
    # set to somewhat lower value to compensate for possible clock skew
    $last=(defined($last) ? $last-60 : 0);

    $self->ensure_connected() or return undef;
    $self->send("subscribe $last\r\n");
    $self->{line_handler}=sub{$self->handle_subscribe(shift())};
};

sub handle_subscribe($self,$line){
    # effect: starts subscription if line indicates data will follow

    if($line=~/^302\D/){
	$self->{subscribed}=1;
	$self->{line_handler}=sub{$self->handle_subscribe_line(shift())};
    }
    else{
	main::lm("got error from server (".$line=~s/[\r\n]+$//r.")",$self->service(),"warning");
	delete($self->{line_handler});
    };
};

sub handle_subscribe_line($self,$line){
    # effect: handles line from subscribe
    
    if($line=~/^[\r\n]+$/){
	# handle report
	$self->handle_subscribe_report($self->{data});
	# data used, start over
	delete($self->{data});
    }
    else{
	# ordinary data line
	$line=~s/^\.//;
	$self->{data}.=$line;
    };
};

sub handle_subscribe_report($self,$data){
    # effect: handles text format report in data

    my $report=eval{DDgrey::Report->from_text($data)};
    if($@ or !defined($report)){
	chomp $@;
	main::lm("bad report from subscribe ($@)",$self->service(),"warning");
	return;
    };
    $main::debug > 1 and main::lm("got report ".$report->unicode(),$self->service());
    $main::dispatcher->report($report);
    DDgrey::Sync->update_fetched($self->{peername},time());
};

# ---- package init ----
return 1;

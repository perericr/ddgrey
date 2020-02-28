# ---- class Dispatcher ----
# handler of received reports

package DDgrey::Dispatcher;

use strict;
use integer;

use Data::Dumper; # DEBUG
use Date::Manip;
use Net::Netmask;
use DDgrey::Perl6::Parameters;

use DDgrey::Policy;
use DDgrey::ReadClient;
use DDgrey::Report;

# ---- constructor ----

sub new($class){
    # return: new dispatcher
    # effect: registers with select
    #         may raise exception

    my $self={};
    bless($self,$class);


    # start periodic cleaning of obsolete posts
    # $main::select->register_interval(60*60*4,sub{
    # $main::store->purge();
    # });

    return $self;
};

# ---- methods ----

sub register_client($self,$client,$read,$write){
    # effect: registers client as read and/or write
    # pre   : at least one of read och write is true
    
    if($read){
	push @{$self->{server_read}},$client;
    }; 
    if($write){
	push @{$self->{server_write}},$client;
    }; 
};

sub close($self){
    # effect: closes dispatcher and clients

    foreach my $server (@{$self->{server_write}}){
	$server->close();
    };
    foreach my $server (@{$self->{server_read}}){
	$server->close();
    };
};

# ---- methods for reports ----

sub report($self,$report){
    # effect: receives and acts on report, tries to ensure domain using DNS

    # skips dubletter
    if(my $d=$report->duplicate()){
	$main::debug > 1 and main::lm("skipping duplicate of ".$d->unicode(),"dispatch");
	return;
    };

    # ensure domain
    if(defined($report->{domain})){
	$self->report_resolved($report);
    }
    else{
	$report->resolve(sub{$self->report_resolved($report)});
    };
};

sub report_resolved($self,$report){
    # effect: receives and acts on report
    # pre   : attempt has been done to resolve domain of report

    # skip duplicates
    if(my $d=$report->duplicate()){
	$main::debug > 1 and main::lm("skipping duplicate of ".$d->unicode()." after resolved","dispatch");
	return;
    };

    $main::debug > 1 and main::lm("processing report ".$report->unicode(),"dispatch");

    # ensure stored
    if(!$report->{id}){
	$report->save();
	$main::debug > 1 and main::lm("saved report ".$report->unicode(),"dispatch");
    };

    # update policy if needed
    DDgrey::Policy->process_report($report);

    # send to possible subscribers (connections initiated by remote system)
    foreach my $subscriber (@{$self->{subscriber}}){
	&$subscriber($report);
    };
};

# ---- methods for event subscribers ----

sub register_subscriber($self,$f){
    # return: id for subscription
    # effect: registers function f to receive reports
    
    my $id=$#{$self->{subscriber}}+1;
    $self->{subscriber}->[$id]=$f;
    return $id;
};

sub unregister_subscriber($self,$id){
    # effect: unregisters subscription id

    delete $self->{subscriber}->[$id];
};

# ---- package init ----
return 1;

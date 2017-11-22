# ---- class Dispatcher ----
# class för själva hanteringen av mottagna rapporter

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

# ---- konstruktor ----

sub new($class){
    # retur:  ny dispatcher
    # effekt: registrerar hos select, kan sätta undantag

    my $self={};
    bless($self,$class);


    # startar periodisk rensning av gamla poster
    # $main::select->register_interval(60*60*4,sub{
    # $main::store->purge();
    # });

    return $self;
};

# ---- metoder ----

sub register_client($self,$client,$read,$write){
    # effekt: registrera klient. minst en av read och write ska vara sanna
    if($read){
	push @{$self->{server_read}},$client;
    }; 
    if($write){
	push @{$self->{server_write}},$client;
    }; 
};

sub close($self){
    # effekt: stänger dispatcher och klienter

    foreach my $server (@{$self->{server_write}}){
	$server->close();
    };
    foreach my $server (@{$self->{server_read}}){
	$server->close();
    };
};

# ---- metoder för rapporter ----

sub report($self,$report){
    # effekt: tar emot och agerar på report, försöker säkra DNS

    # hoppar över dubletter
    if(my $d=$report->duplicate()){
	$main::debug > 1 and main::lm("skipping duplicate of ".$d->unicode(),"dispatch");
	return;
    };

    # säkerställ att uppslagen
    if(defined($report->{domain})){
	$self->report_resolved($report);
    }
    else{
	$report->resolve(sub{$self->report_resolved($report)});
    };
};

sub report_resolved($self,$report){
    # effekt: tar emot och agerar på report

    # hoppar över dubletter
    if(my $d=$report->duplicate()){
	$main::debug > 1 and main::lm("skipping duplicate of ".$d->unicode()." after resolved","dispatch");
	return;
    };

    $main::debug > 1 and main::lm("processing report ".$report->unicode(),"dispatch");

    # säkerställ att lagrad
    if(!$report->{id}){
	$report->save();
	$main::debug > 1 and main::lm("saved report ".$report->unicode(),"dispatch");
    };

    # uppdatera policy vid behov
    DDgrey::Policy->process_report($report);

    # skicka vidare till prenumeranter (förbindelse initierad av fjärrsystem)
    foreach my $subscriber (@{$self->{subscriber}}){
	&$subscriber($report);
    };
};

# ---- metoder för prenumeranter på händelser ----

sub register_subscriber($self,$f){
    # retur : id för prenumeration
    # effekt: registrar funktion f att ta emot rapporter
    
    my $id=$#{$self->{subscriber}}+1;
    $self->{subscriber}->[$id]=$f;
    return $id;
};

sub unregister_subscriber($self,$id){
    # effekt: avregistrerad prenumeration

    delete $self->{subscriber}->[$id];
};

# ---- package init ----
return 1;

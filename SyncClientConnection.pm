# ---- class SyncClientConnection ----
# class for ddgrey client connection

package DDgrey::SyncClientConnection;

use strict;
use integer;

use DDgrey::Perl6::Parameters;
use Data::Dumper; # DEBUG
use Net::hostent;
use Socket;

use DDgrey::Config;
use DDgrey::Report;
use DDgrey::RemoteServer;

use parent qw(DDgrey::ClientConnection);

# ---- konstruktor ----

sub new($class,$server,$fh,$permission){
    # retur:  ny klientanslutning av class kring fh med rättighet permission
    # effekt: kan sätta undantag, registrerar hos server och select

    my $self=$class->SUPER::new($server,$fh);
    $self->{permission}=$permission;
    return $self;
};

# ---- metoder ----

sub handle_command($self,$item){
    # retur / effekt: försök utföra kommando beskrivet i item

    my $command=shift(@{$item->{arg}});
    if(!defined($command)){
	return "500 no command received\r\n";
    };

    # -- helo --
    if($command eq 'helo'){
	my $arg=$item->{arg}->[0];
	defined($arg) or return "500 argument missing\r\n";
	$arg=~/^[\w\.\-]+$/ or return "500 bad argument\r\n";
	$self->{peername}=$arg;
	return "200 welcome. I am ".$main::hostname."\r\n";
    };

    # -- quit --
    if($command eq 'quit'){
	$self->{closing}=1;
	return "250 closing connection\r\n";
    };

    # -- list --
    if($command eq 'list'){
	# kolla rättighet
	$self->{permission}->{read} or return "500 permission denied\r\n";

	my $arg=($item->{arg}->[0] or 0);
	$arg=~/^\d+$/ or return "500 bad argument\r\n";
	my @list=DDgrey::Report->list($arg);
	$self->send("300 document following\r\n");
	for my $l (@list){
	    $self->send($l->{id}."\t".$l->{origin}."\t".$l->{origin_id}."\t".$l->{stored}."\r\n");
	    # om många skickas på samma gång
	    $main::select->run_write([$self->{fh}]);
	};
	return ".\r\n";
    };

    # -- get --
    if($command eq 'get'){
	# kolla rättighet
	$self->{permission}->{read} or return "500 permission denied\r\n";

	my $arg=$item->{arg}->[0];
	defined($arg) or return "500 argument missing\r\n";
	$arg=~/^\d+$/ or return "500 bad argument\r\n";
	
	my $report=DDgrey::Report->get($arg);
	defined($report) or return "500 report not found\r\n";
	    
	$self->send("300 document following\r\n");
	$self->send($report->as_text());
	$self->send("\r\n");
	return;
    };

    # -- subscribe --
    if($command eq 'subscribe'){ 
    	# kolla rättighet
	$self->{permission}->{read} or return "500 permission denied\r\n";

	my $subscription=$main::dispatcher->register_subscriber(sub{$self->send_report(@_)});
	defined($subscription) or return "502 subscription failed\r\n";
	$self->{subscription}=$subscription;
	$self->{data_handler}=sub{$self->handle_subscribe()};
	
	# ev argument - rapportera anslutningar från tidpunkt tidigare än nu
	my $arg=($item->{arg}->[0]);
	my @list=();
	if(defined($arg)){
	    $arg=~/^\d+$/ or return "500 bad argument\r\n";
	    @list=DDgrey::Report->list($arg);
	};

	# skicka start och ev färdiga dokument
	$self->send("302 document following (interrupt with single dot)\r\n");
	foreach my $l (@list){
	    my $report=DDgrey::Report->get($l->{id});
	    $self->send_report($report);
	    # om många skickas på samma gång
	    $main::select->run_write([$self->{fh}]);
	};
	return;
    };
    
    # -- report --
    if($command eq 'report'){
	# kolla rättighet
	$self->{permission}->{write} or return "500 permission denied\n";
	$self->{data_handler}=sub{$self->handle_report()};
	return "301 go ahead\n";
    };

    # ---- övriva kommandon ----
    return "500 unknown command\r\n";
};

sub handle_subscribe($self){
    # retur : statusrad
    # effekt: avslutar prenumeration
    # pre   : får bara anropas när prenumeration är aktiv

    $main::dispatcher->unregister_subscriber($self->{subscription});
    $self->{data} and return "500 no text accepted during subscribe\r\n";
    return "200 subscription finished\r\n";
};

sub send_report($self,$report){
    # effekt: skicka report till klient

    $main::debug > 1 and main::lm("sending report ".$report->unicode(),$self->service());
    $self->send($report->as_text());
    # extra blankrad betyder att denna rapport är klar
    $self->send("\r\n");
};

sub handle_report($self){
    # retur : statusrad
    # effekt: ta hand om rapport i self->data
    
    my $report=eval{DDgrey::Report->from_text($self->{data})};
    if($@ or !defined($report)){
	my $e=$@;
	chomp($e);
	main::lm("bad report from client ($e)",$self->service(),"warning");
	return "500 bad report ($e)\r\n";
    }; 
    $main::debug > 1 and main::lm("got report ".$report->unicode(),$self->service());
    $main::dispatcher->report($report);
    return "200 accepted\r\n";
};

# ---- package init ----
return 1;

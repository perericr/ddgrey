# ---- class RemoteServer ----
# TCP server for synchronizing between ddgrey instances

package DDgrey::RemoteServer;

use strict;
use integer;

use Data::Dumper; # DEBUG
use Net::hostent;
use DDgrey::Perl6::Parameters;
use Socket;

use DDgrey::DNS qw(resolved);
use DDgrey::SyncClientConnection;

use parent qw(DDgrey::Server);

# ---- class methods ----

sub service($self){
    # return: name of subsystem (for logging)
    return "remote server";
};

# ---- constructor ----

sub new($class){
    # return:  new TCP server of class
    # effect: may raise exception

    my $self=bless({},$class);

    my $port=($main::config->{port} or ($< ? 1722 : 722));
    for my $n (0..20){
	$self->{fh}=IO::Socket::INET->new(Listen=>10,Proto=>'tcp',LocalPort=>$port) and last;
	main::lm("can't start server on port $port ($!), trying again",$self->service(),'warning');
	sleep 5;	
    };
    $self->{fh} or main::error("can't start server on port $port ($!)");
    $self->{fh}->blocking(0);
    $self->{fh}->timeout($main::debug ? 5 : 60);

    # configuration of accept parameters
    foreach my $r (@{$main::config->{accept}}){
	for my $ip (resolved($r)){
	    my $m=Net::Netmask->new2($ip) or main::error("unkown address/range $ip");
	    push @{$self->{accept_write}},$m;
	    push @{$self->{accept_read}},$m;
	};
    };
    foreach my $r (@{$main::config->{accept_reader}}){
	for my $ip (resolved($r)){
	    my $m=Net::Netmask->new2($ip) or main::error("unkown address/range $ip");
	    push @{$self->{accept_read}},$m;
	};
    };
    foreach my $r (@{$main::config->{accept_writer}}){
	for my $ip (resolved($r)){
	    my $m=Net::Netmask->new2($ip) or main::error("unkown address/range $ip");
	    push @{$self->{accept_write}},$m;
	};
    };
    foreach my $r (@{$main::config->{peer}}){
	my $peer=$r->{arg}->[0];
	for my $ip (resolved($peer)){
	    my $m=Net::Netmask->new2($ip) or main::error("unkown address/range $ip");
	    push @{$self->{accept_read}},$m;
	};
    };

    # register
    $main::select->register_read($self->{fh},sub{$self->receive_read(@_)});
    $main::select->register_exception($self->{fh},sub{$self->close()});
    main::lm("listening on port $port",$self->service());

    return $self;
};

# ---- methods ----

sub receive_read($self,$fh){
    # effect: handles activity on fh

    if($fh eq $self->{fh}){
	my $client_fh=$fh->accept();
	if(!defined($client_fh)){
	    main::lm("accept failed ($!)",$self->service(),"warning");
	    return 0;
	};
	$client_fh->autoflush(1);
	$client_fh->blocking(0);
	$client_fh->timeout($main::debug ? 5 : 60);

	# check accept permission
	my $ip=$client_fh->peerhost;
	my $accept={read=>0,write=>0};
	foreach my $m (@{$self->{accept_read}}){
	    if($m->match($ip)){
		$accept->{read}=1;
		last;
	    };
	};
	foreach my $m (@{$self->{accept_write}}){
	    if($m->match($ip)){
		$accept->{write}=1;
		last;
	    };
	};

	# close if no permission at all
	if(!($accept->{read} or $accept->{write})){
	    main::lm("denied connect from ".$client_fh->peerhost(),$self->service(),"warning");
	    $client_fh->shutdown(2);
	    $client_fh->close();
	    return;
	};

	my $client=DDgrey::SyncClientConnection->new($self,$client_fh,$accept);
    };
};

# ---- package init ----
return 1;

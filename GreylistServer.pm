# ---- class GreylistServer ----
# Greylist-server over UNIX-socket

package DDgrey::GreylistServer;

use strict;
use integer;

use Data::Dumper; # DEBUG
use IO::Socket::UNIX;
use DDgrey::Perl6::Parameters;
use Socket;

use DDgrey::GreylistClientConnection;
use DDgrey::Run qw(ensure_dir);

use parent qw(DDgrey::Server);

# ---- constructor ----

sub new($class){
    # return:  new UNIX server of class
    # effect: may raise exception

    my $self=bless({},$class);
    ensure_dir("_RUNDIR_",$main::uid,$main::gid);
    $self->{socket}=($main::dir // "_RUNDIR_")."/greylist.socket";
    unlink $self->{socket};
    
    $self->{fh}=IO::Socket::UNIX->new(Type=>SOCK_STREAM(),Listen=>1,Local=>$self->{socket});
    $self->{fh} or main::error("can't start server on $self->{socket} ($!)");
    $< == 0 and chown($main::uid,$main::gid,$self->{socket});
    $self->{fh}->blocking(0);
    $self->{fh}->timeout($main::debug ? 5 : 60);

    # register
    $main::select->register_read($self->{fh},sub{$self->receive_read(@_)});
    $main::select->register_exception($self->{fh},sub{$self->close()});
    main::lm("listening on $self->{socket}",$self->service());

    return $self;
};

# ---- methods ----

sub service($self){
    # return: name of subsystem (for logging)
    return "greylist server";
};

sub close($self){
    # effect: closes server

    unlink($self->{socket});
    $self->SUPER::close();
};

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

	my $client=DDgrey::GreylistClientConnection->new($self,$client_fh);
    };
};

# ---- package init ----
return 1;

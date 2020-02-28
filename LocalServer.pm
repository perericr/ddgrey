# ---- class LocalServer ----
# UNIX server for synchronizing from ddgrey-report

package DDgrey::LocalServer;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;
use Socket;

use DDgrey::DNS qw(resolved);
use DDgrey::Run qw(ensure_dir);
use DDgrey::SyncClientConnection;

use parent qw(DDgrey::Server);

# ---- class methods ----

sub service($self){
    # return: subsystem name (for logging)
    return "local server";
};

# ---- construktor ----

sub new($class){
    # return: new UNIX server of class
    # effect: may raise exception

    my $self=bless({},$class);
    ensure_dir("_RUNDIR_",$main::uid,$main::gid);
    $self->{socket}=($main::dir // "_RUNDIR_")."/ddgrey.socket";
    unlink $self->{socket};
    
    $self->{fh}=IO::Socket::UNIX->new(Type=>SOCK_STREAM(),Listen=>1,Local=>$self->{socket});
    $self->{fh} or main::error("can't start server on $self->{socket} ($!)");
    $< == 0 and chown($main::uid,$main::gid,$self->{socket});
    $self->{fh}->blocking(0);
    $self->{fh}->timeout($main::debug ? 5 : 60);

    # register
    $main::select->register_read($self->{fh},sub{$self->receive_read(@_)});
    $main::select->register_exception($self->{fh},sub{$self->close()});
    main::lm("listening on $self->{socket}","local server");

    return $self;
};

# ---- methods ----

sub receive_read($self,$fh){
    # effect: handles activity on fh

    if($fh eq $self->{fh}){
	my $client_fh=$fh->accept();
	if(!defined($client_fh)){
	    main::lm("accept failed ($!)","local server","warning");
	    return 0;
	};
	$client_fh->autoflush(1);
	$client_fh->blocking(0);
	$client_fh->timeout($main::debug ? 5 : 60);
	binmode($client_fh,":encoding(UTF-8)");

	my $accept={read=>1,write=>1};
	my $client=DDgrey::SyncClientConnection->new($self,$client_fh,$accept);
    };
};

# ---- package init ----
return 1;

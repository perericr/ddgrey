 # ---- class ClientConnection ----
# base class for client connection to this server via TCP or UNIX socket

package DDgrey::ClientConnection;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;
use Socket;

use DDgrey::Config;
use DDgrey::Policy;

# ---- constructor ----

sub new($class,$server,$fh){
    # return: new client connection of class using fh
    # effect: registers with server and select
    #         may raise exception

    my $self={};
    bless($self,$class);

    $self->{fh}=$fh;
    $self->{server}=$server;
    $self->{service}=$server->service();
    $self->{closing}=0;      # 1 if closing, 2 if closing and no write possible
                             # 3 if closed and unregistered from server
    $self->{pending_send}=0; # number of concurrent tasks resulting in data

    # set client id to save
    $self->{client_id}=$self->client_id();

    # register
    $main::select->register_line($self->{fh},sub{$self->receive_line(@_)});
    $main::select->register_exception($self->{fh},sub{
	$self->handle_exception();
    });

    $self->{server}->register_client($self);

    $main::debug and main::lm("connection established from ".$self->client_id(),$self->service());

    return $self;
};

# ---- methods ----

sub service($self){
    # return: name of subsystem (for logging)
    return $self->{service} // 'unknown service';
};

sub client_id($self){
    # return: suitable id for connection

    # tried cached id
    defined($self->{client_id}) and return $self->{client_id};

    # otherwise, return new
    if($self->{fh}->can('peerhost')){
	# use peer host if TCP
	return eval{
	    $self->{fh}->peerhost();
	} // 'closed socket';
    }
    else{
	# something else, probably UNIX socket
	return $self->{fh}=~s/.*?(0x[\dabcdef]+).*/$1/r;
    };
};

sub receive_line($self,$line){
    # effect: handles line from client

    $main::debug > 2 and main::lm("got ".$line=~s/[\r\n]+$//r,$self->service());
    if(defined($self->{data_handler})){
	# handle data
	if($line=~/^\.[\r\n]+$/){
	    # run data handler
	    $self->send(&{$self->{data_handler}}());
	    # data used, start over
	    delete($self->{data_handler});
	}
	else{
	    # ordinary data line
	    $line=~s/^\.//;
	    $self->{data}.=$line;
	};
    }
    else{
	# ordinary command
	my $item=eval{
	    my $l=DDgrey::Config::row_lex($line,0,0);
	    defined($l) or return undef;
	    DDgrey::Config::line_parse($l);
	};
	if($@){
	    chomp $@;
	    $self->send("500 syntax error ($@)\r\n");
	    return;
	};
	defined($item) or return undef;
	
	# run command
	my $r=$self->handle_command($item);
	defined($r) and $self->send($r);
    };
};

sub quit($self){
    # effect: deregisters where registered and close, with logging
    
    $main::debug and main::lm("closing connection on client request from ".$self->client_id(),$self->service());
    $self->close();
};

sub close($self){
    # effect: deregisters where registered and closes

    if(!defined($self->{server})){
	return;
    };
    $main::select->unregister($self->{fh});
    $self->{server}->unregister_client($self);

    $self->{fh}->shutdown(2);
    $self->{fh}->close();
    $main::debug and main::lm("closed connection from ".$self->client_id(),$self->service());
    
    # delete server pointer to avoid circular references
    delete($self->{server});
    # mark as closed
    $self->{closing}=3;
};

sub handle_exception($self){
    # effect: handles exception from select

    if($self->{fh}->eof()){
	# connection closed
	if($self->{pending_send} > 0){
	    $main::debug and main::lm("connection closed from ".$self->client_id().", waiting for data",$self->service());
	    $main::select->unregister($self->{fh},1,0);
	    # mark as closing, no write possible
	    $self->{closing}=2;
	}
	else{
	    $main::debug and main::lm("connection closed from ".$self->client_id().", closing",$self->service());
	    $self->close();
	};
    }
    else{
	# other exception
	$main::debug and main::lm("connection exception from ".$self->client_id(),$self->service());
	$self->close();
    };
};

sub send($self,$line;$next){
    # effect: sends line to client, run next when sent
    
    if(($self->{closing} // 0) < 2){
	$main::debug > 2 and main::lm("sending ".$line=~s/[\r\n]+$//r,$self->service());
	$main::select->write($self->{fh},$line,$next);
    }
    else{
	$main::debug > 2 and main::lm("not sending (because of closing) ".$line=~s/[\r\n]+$//r,$self->service());
    };
    $self->close_if_done();
};

sub close_if_done($self){
    # effect: close if no pending_send and closing requested

    if($self->{closing} and $self->{pending_send}==0){
	$main::debug and main::lm("last data sent, closing connection to ".$self->client_id(),$self->service());
	$self->close();
    };
};

# ---- package init ----
return 1;

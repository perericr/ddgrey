# ---- class Client ----
# base class for connection to server over TCP or UNIX socket

package DDgrey::Client;

use strict;
use integer;

use IO::Socket::INET;
use IO::Socket::UNIX;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

# ---- constructor ----

sub new($class,$config;$retry){
    # return: new client of class connected to config argument 0
    #        retry is interval in s between retries
    
    $retry //= ($main::debug ? 5 : 60);
    
    my $self={};
    bless($self,$class);
    
    # make UNIX or TCP connection
    defined($config->{arg}->[0]) or main::error("no socket/host specified");
    if($config->{arg}->[0]=~/^\//){
	$self->{socket}=$config->{arg}->[0]; 
    }
    else{
	$self->{host}=$config->{arg}->[0]; 
	$self->{port}=($config->{arg}->[1] or ($< ? 1722 : 722));
    };

    # start periodic task to ensure connected
    $main::select->register_interval($retry,sub{
	$self->ensure_connected();
    });

    $self->ensure_connected();
    return $self;
};

# ---- methods ----

sub log_connect{
    # return: whether connect should be logged
    return 1;
}

sub helo($self){
    # effect: sends helo to server

    $self->ensure_connected() or return undef;
    $self->send("helo ".$main::hostname."\r\n");
    $self->{line_handler}=sub{$self->handle_helo(shift())};
};

sub handle_helo($self,$line){
    # effect: starts reception if line indicates helo success
    
    if($line=~/^200\D.*I am ([\w\.\-]+)/i){
	$self->{peername}=$1;
	delete($self->{line_handler});

	# next to do after helo
	if(defined($self->{on_helo})){
	    &{$self->{on_helo}}();
	}
	else{
	    $self->check_on_prompt();
	};
    }
    else{
	main::lm("client error from server (".$line=~s/[\r\n]+$//r.")",$self->service(),"warning");
	delete($self->{line_handler});
    };
};

sub connected($self){
    # return: whether fh exists and is connected
    return (defined($self->{fh}) and $self->{fh}->connected());
};

sub ensure_connected($self){
    # return: whether connected
    # effect: tries to ensure fh is connected to socket / host and port

    # check if connected
    if($self->connected()){
	return 1;
    };

    # make new connection
    $self->close_fh();

    if(defined($self->{socket})){
	$self->{fh}=IO::Socket::UNIX->new(Type=>SOCK_STREAM(),Peer=>$self->{socket});
    }
    else{
	$self->{fh}=IO::Socket::INET->new(PeerAddr =>$self->{host},PeerPort=>$self->{port},Proto=>'tcp');
    };

    
    # log connected status
    my $status=$self->connected();
    if($status){
	($self->log_connect() or $main::debug) and main::lm('connected to server '.($self->{socket} // $self->{host}),$self->service());
    }
    else{
	main::lm('could not connect to server '.($self->{socket} // $self->{host}),$self->service(),"warning");
        $self->close_fh();
    };

    #  set up parameters for new connection
    if(defined($self->{fh})){
	$self->{fh}->autoflush(0);
	$self->{fh}->blocking(0);
	$self->{fh}->timeout($main::debug ? 5 : 60);
	$main::select->register_line($self->{fh},sub{$self->receive_line(@_)});
	$main::select->register_exception($self->{fh},sub{
	    main::lm("disconnected from server ".($self->{socket} // $self->{host}),$self->service(),"warning");
            $self->close_fh();
	});

	# send helo and possibly run on_helo
	$self->helo();
    };

    return $status;
};

sub close_fh($self){
    # effect: closes own fh

    if(defined($self->{fh})){
	($self->log_connect() or $main::debug) and main::lm("connection closed to server ".($self->{socket} // $self->{host}),$self->service());
	$main::select->unregister($self->{fh});
	$self->{fh}->shutdown(2);
        $self->{fh}->close();
    };
    delete($self->{fh});
};

sub close($self){
    # effect: closes client connection
    
    # send quit if connected and at prompt
    if(!(defined($self->{data_handler}) or !defined($self->{line_handler}))){
	if($self->connected()){
	    $self->send("quit\r\n");
	    $self->{line_handler}=sub{delete $self->{line_handler}};
	};
    };
    $self->close_fh();
};

sub send($self,$line){
    # effect: sends line to client

    $main::debug > 2 and main::lm("sending ".$line=~s/[\r\n]+$//r,$self->service());
    $main::select->write($self->{fh},$line);
};

sub receive_line($self,$line){
    # effect: handles line from client

    $main::debug > 2 and main::lm("got ".$line=~s/[\r\n]+$//r,$self->service());
    
    # handle data
    if(defined($self->{data_handler})){
	if($line=~/^\.$/){
	    # run data handler
	    &{$self->{data_handler}}();
	    # end of data
	    delete($self->{data_handler});
	    delete($self->{data});
	    $self->check_on_prompt();
	}
	else{
	    # ordinary data line
	    $line=~s/^\.//;
	    $self->{data}.=$line;
	};

	return 1;
    };

    # handle line
    if(defined($self->{line_handler})){
	&{$self->{line_handler}}($line);
	$self->check_on_prompt();
	return 1;
    };
    
    # default handler - will log unexpected messages
    chomp $line;
    main::lm("unexpected line from server ($line)",$self->service(),"warning");
};

# -- queue of commands to run --

sub schedule($self,$f){
    # effect: adds f to TODO-list
    #         runs f if possible

    push(@{$self->{todo}},$f);
    $self->check_on_prompt();
};

sub check_on_prompt($self){
    # effect: runs possible command from TODO 
    
    if($self->connected()){
	if(!defined($self->{data_handler}) and !defined($self->{line_handler})){
	    if(defined(my $f=shift(@{$self->{todo}}))){
		&$f();
	    };
	};
    };
};

# ---- package init ----
return 1;

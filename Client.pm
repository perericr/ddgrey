# ---- klass Client ----
# basklass för anslutning till server via TCP eller UNIX-socket

package DDgrey::Client;

use strict;
use integer;

use IO::Socket::INET;
use IO::Socket::UNIX;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

# ---- konstruktor ----

sub new($class,$config;$retry){
    # retur: ny klient av class ansluten till config argument 0
    #        retry är hur ofta försök att ansöka ska göras
    
    $retry //= ($main::debug ? 5 : 60);
    
    my $self={};
    bless($self,$class);
    
    # gör UNIX- eller TCP-anslutning
    defined($config->{arg}->[0]) or main::error("no socket/host specified");
    if($config->{arg}->[0]=~/^\//){
	$self->{socket}=$config->{arg}->[0]; 
    }
    else{
	$self->{host}=$config->{arg}->[0]; 
	$self->{port}=($config->{arg}->[1] or ($< ? 1722 : 722));
    };

    # startar periodisk kontroll för att hålla förbindelse uppe
    $main::select->register_interval($retry,sub{
	$self->ensure_connected();
    });

    $self->ensure_connected();
    return $self;
};

# ---- metoder ----

sub log_connect{
    # retur: huruvida logga anslutning
    return 1;
}

sub helo($self){
    # effekt: säger helo till server

    $self->ensure_connected() or return undef;
    $self->send("helo ".$main::hostname."\r\n");
    $self->{line_handler}=sub{$self->handle_helo(shift())};
};

sub handle_helo($self,$line){
    # effekt: startar helo-mottagning om line verkar OK

    if($line=~/^200\D.*I am ([\w\.\-]+)/i){
	$self->{peername}=$1;
	delete($self->{line_handler});

	# kod att köra efter helo
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
    # retur: huruvida fh finns och är anslutet
    return (defined($self->{fh}) and $self->{fh}->connected());
};

sub ensure_connected($self){
    # effekt: ser till att försöker ansluta fh till socket / host och port
    # retur : huruvida förbindelse är uppe

    # kolla om redan uppe
    if($self->connected()){
	return 1;
    };

    # gör ny anslutning
    $self->close_fh();

    if(defined($self->{socket})){
	$self->{fh}=IO::Socket::UNIX->new(Type=>SOCK_STREAM(),Peer=>$self->{socket});
    }
    else{
	$self->{fh}=IO::Socket::INET->new(PeerAddr =>$self->{host},PeerPort=>$self->{port},Proto=>'tcp');
    };

    
    # returnera huruvida lyckat
    my $status=$self->connected();
    if($status){
	($self->log_connect() or $main::debug) and main::lm('connected to server '.($self->{socket} // $self->{host}),$self->service());
    }
    else{
	main::lm('could not connect to server '.($self->{socket} // $self->{host}),$self->service(),"warning");
        $self->close_fh();
    };

    # sätter i ordning ny förbindelse
    if(defined($self->{fh})){
	$self->{fh}->autoflush(0);
	$self->{fh}->blocking(0);
	$self->{fh}->timeout($main::debug ? 5 : 60);
	binmode($self->{fh},":encoding(UTF-8)");
	$main::select->register_line($self->{fh},sub{$self->receive_line(@_)});
	$main::select->register_exception($self->{fh},sub{
	    main::lm("disconnected from server ".($self->{socket} // $self->{host}),$self->service(),"warning");
            $self->close_fh();
	});

	# skickar helo över ny förbindelse och kör ev on_helo
	$self->helo();
    };

    return $status;
};

sub close_fh($self){
    # effekt: stänger eget fh

    if(defined($self->{fh})){
	($self->log_connect() or $main::debug) and main::lm("connection closed to server ".($self->{socket} // $self->{host}),$self->service());
	$main::select->unregister($self->{fh});
	$self->{fh}->shutdown(2);
        $self->{fh}->close();
    };
    delete($self->{fh});
};

sub close($self){
    # effekt: stänger klientanslutning inklusive fh

    # skicka quit om i default-läge och ansluten
    if(!(defined($self->{data_handler}) or !defined($self->{line_handler}))){
	if($self->connected()){
	    $self->send("quit\r\n");
	    $self->{line_handler}=sub{delete $self->{line_handler}};
	};
    };
    $self->close_fh();
};

sub send($self,$line){
    # effekt: skickar line till klient

    $main::debug > 2 and main::lm("sending ".$line=~s/[\r\n]+$//r,$self->service());
    $main::select->write($self->{fh},$line);
};

sub receive_line($self,$line){
    # effekt: behandlar rad line från klient

    $main::debug > 2 and main::lm("got ".$line=~s/[\r\n]+$//r,$self->service());
    
    # hantera data
    if(defined($self->{data_handler})){
	if($line=~/^\.$/){
	    # kör hanterare av data
	    &{$self->{data_handler}}();
	    # slut på data
	    delete($self->{data_handler});
	    delete($self->{data});
	    $self->check_on_prompt();
	}
	else{
	    # vanlig datarad - ta bort ev inledande punkt
	    $line=~s/^\.//;
	    $self->{data}.=$line;
	};

	return 1;
    };

    # hantera rad
    if(defined($self->{line_handler})){
	&{$self->{line_handler}}($line);
	$self->check_on_prompt();
	return 1;
    };
    
    # default-hanterare
    chomp $line;
    main::lm("unexpected line from server ($line)",$self->service(),"warning");
};

# -- kö med kommandon att utföra --

sub schedule($self,$f){
    # effekt: lägger till i att-göra listan
    #         kör f om det kan göras omedelbart

    push(@{$self->{todo}},$f);
    $self->check_on_prompt();
};

sub check_on_prompt($self){
    # effekt: kör ev funktion vid promten om sådan registrerad
    if($self->connected()){
	if(!defined($self->{data_handler}) and !defined($self->{line_handler})){
	    if(defined(my $f=shift(@{$self->{todo}}))){
		&$f();
	    };
	};
    };
};

# ---- init av paket ----
return 1;

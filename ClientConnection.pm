 # ---- klass GreylistClientConnection ----
# basklass för klientanslutning till server via TCP eller UNIX-socket

package DDgrey::ClientConnection;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;
use Socket;

use DDgrey::Config;
use DDgrey::Policy;

# ---- konstruktor ----

sub new($class,$server,$fh){
    # retur:  ny klientanslutning av class kring fh
    # effekt: kan sätta undantag, registrerar hos server och select

    my $self={};
    bless($self,$class);

    $self->{fh}=$fh;
    $self->{server}=$server;
    $self->{service}=$server->service();
    $self->{closing}=0;
    $self->{pending_send}=0; # antal uppdrag på gång som ska sända data

    # sätt client_id för att spara
    $self->{client_id}=$self->client_id();

    # registrera
    $main::select->register_line($self->{fh},sub{$self->receive_line(@_)});
    $main::select->register_exception($self->{fh},sub{
	$self->handle_exception();
    });

    $self->{server}->register_client($self);

    $main::debug and main::lm("connection established from ".$self->client_id(),$self->service());

    return $self;
};

# ---- metoder ----

sub service($self){
    # retur: namn på undersystem (för loggning)
    return $self->{service} // 'unknown service';
};

sub client_id($self){
    # retur: lämpligt id för anslutning

    # prova cache
    defined($self->{client_id}) and return $self->{client_id};

    # gör nytt
    if($self->{fh}->can('peerhost')){
	# TCP
	return eval{
	    $self->{fh}->peerhost();
	} // 'closed socket';
    }
    else{
	# något annat, troligen UNIX
	return $self->{fh}=~s/.*?(0x[\dabcdef]+).*/$1/r;
    };
};

sub receive_line($self,$line){
    # effekt: behandlar rad line från klient

    $main::debug > 2 and main::lm("got ".$line=~s/[\r\n]+$//r,$self->service());
    if(defined($self->{data_handler})){
	# hantera data
	if($line=~/^\.[\r\n]+$/){
	    # kör hanterare av data
	    $self->send(&{$self->{data_handler}}());
	    # slut på data
	    delete($self->{data_handler});
	}
	else{
	    # vanlig datarad - ta bort ev inledande punkt
	    $line=~s/^\.//;
	    $self->{data}.=$line;
	};
    }
    else{
	# vanligt kommando
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
	
	# kör kommando
	my $r=$self->handle_command($item);
	defined($r) and $self->send($r);
    };
};

sub quit($self){
    # effekt: avregistrera där registrerad och stäng
    $main::debug and main::lm("closing connection on client request from ".$self->client_id(),$self->service());
    $self->close();
};

sub close($self){
    # effekt: avregistrera där registrerad och stäng

    if(!defined($self->{server})){
	return;
    };
    $main::select->unregister($self->{fh});
    $self->{server}->unregister_client($self);

    $self->{fh}->shutdown(2);
    $self->{fh}->close();
    $main::debug and main::lm("closed connection from ".$self->client_id(),$self->service());
    # för att undvika cirkelreferenser
    delete($self->{server});
};

sub handle_exception($self){
    # effekt: hantera undantag från select
    if($self->{fh}->connected() and $self->{fh}->eof()){
	if($self->{pending_send} > 0){
	    $main::debug and main::lm("connection closed from ".$self->client_id().", waiting for data",$self->service());
	    $main::select->unregister($self->{fh},1,0);
	    $self->{closing}=1;
	}
	else{
	    $main::debug and main::lm("connection closed from ".$self->client_id().", closing",$self->service());
	    $self->close();
	};
    }
    else{
	$main::debug and main::lm("connection exception from ".$self->client_id(),$self->service());
	$self->close();
    };
};

sub send($self,$line;$next){
    # effekt: skickar line till klient, kör next när skickat
    $main::debug > 2 and main::lm("sending ".$line=~s/[\r\n]+$//r,$self->service());
    $main::select->write($self->{fh},$line,$next);
    if($self->{closing} and $self->{pending_send}==0){
	$main::debug and main::lm("last data sent, closing connection to ".$self->client_id(),$self->service());
	$self->close();
    };
};

# ---- package init ----
return 1;

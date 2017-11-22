 # ---- klass GreylistClientConnection ----
# klass för klientanslutning till greylist-server

package DDgrey::GreylistClientConnection;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;
use Socket;

use DDgrey::Config;
use DDgrey::GreylistServer;
use DDgrey::Policy;
use DDgrey::Run qw(ensure_dir);

use parent qw(DDgrey::ClientConnection);

# ---- metoder ----

sub handle_command($self,$item){
    # retur / effekt: försök utföra kommando beskrivet i item

    my $command=shift(@{$item->{arg}});
    if(!defined($command)){
	return "500 no command received\r\n";
    };

    # -- check --
    if($command eq 'check'){
	@{$item->{arg}} < 3 and return "500 arguments missing\r\n";
	@{$item->{arg}} > 3 and return "500 too many arguments\r\n";
	my $ip=$item->{arg}->[0];
	my $from=$item->{arg}->[1];
	my $to=$item->{arg}->[2];
	$ip=~/^\d+\.\d+\.\d+\.\d+$/ or return "500 bad IP address format\r\n";
	$main::debug > 1 and main::lm("checking $ip $from $to",$self->service());
	$self->{pending_send}++;
	DDgrey::Policy->check(
	    $ip,$from,$to,
	    sub{
		$self->{pending_send}--;
		$self->send("200 ".$_[0]."\r\n",undef);
	    });
	return;
    };

    # -- check_quit --
    if($command eq 'check_quit'){
	@{$item->{arg}} < 3 and return "500 arguments missing\r\n";
	@{$item->{arg}} > 3 and return "500 too many arguments\r\n";
	my $ip=$item->{arg}->[0];
	my $from=$item->{arg}->[1];
	my $to=$item->{arg}->[2];
	$ip=~/^\d+\.\d+\.\d+\.\d+$/ or return "500 bad IP address format\r\n";
	$main::debug > 1 and main::lm("checking $ip $from $to",$self->service());
	$self->{pending_send}++;
	DDgrey::Policy->check(
	    $ip,$from,$to,
	    sub{
		$self->{pending_send}--;
		$self->send("200 ".$_[0]."",sub{$self->quit()});
	    });
	return;
    };
    
    # -- quit --
    if($command eq 'quit'){
	$self->send("250 closing connection\r\n",sub{$self->quit()});
    };

    # ---- övriva kommandon ----
    return "500 unknown command\r\n";
};

# ---- package init ----
return 1;


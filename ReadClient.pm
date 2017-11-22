# ---- class ReadClient ----
# klass för läs-anslutning till server

package DDgrey::ReadClient;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

use DDgrey::Report;
use DDgrey::Sync;

use parent qw(DDgrey::Client);

# ---- konstruktor ----

sub new($class,$config){
    # retur: ny läsklient av class till config argument 0

    my $self=$class->SUPER::new($config);

    # startar alltid prenumeration efter OK helo
    $self->{on_helo}=sub{$self->subscribe()};

    main::lm("read client querying $self->{host}:$self->{port} started",$self->service());
    return $self;
};

# ---- metoder ----

sub service($self){
    # retur: namn på undersystem (för loggning)
    return "read client";
};

sub close_fh($self){
    # effekt: stänger eget fh

    delete($self->{subscribed});
    $self->SUPER::close_fh();
};

sub subscribe($self){
    # effekt: startar prenumeration

    my $last=DDgrey::Sync->last_fetched($self->{peername});
    # sätt till något lägre värde för att kompensera ev klockjusteringar
    $last=(defined($last) ? $last-60 : 0);

    $self->ensure_connected() or return undef;
    $self->send("subscribe $last\r\n");
    $self->{line_handler}=sub{$self->handle_subscribe(shift())};
};

sub handle_subscribe($self,$line){
    # effekt: startar subscribe-mottagning om line verkar OK

    if($line=~/^302\D/){
	$self->{subscribed}=1;
	$self->{line_handler}=sub{$self->handle_subscribe_line(shift())};
    }
    else{
	main::lm("got error from server (".$line=~s/[\r\n]+$//r.")",$self->service(),"warning");
	delete($self->{line_handler});
    };
};

sub handle_subscribe_line($self,$line){
    # effekt: hanterar rad line från subscribe
    
    if($line=~/^[\r\n]+$/){
	# kör hanterare av data
	$self->handle_subscribe_report($self->{data});
	# slut på data
	delete($self->{data});
    }
    else{
	# vanlig datarad - ta bort ev inledande punkt
	$line=~s/^\.//;
	$self->{data}.=$line;
    };
};

sub handle_subscribe_report($self,$data){
    # effekt: hanterar mottagen rapport i textform data

    my $report=eval{DDgrey::Report->from_text($data)};
    if($@ or !defined($report)){
	chomp $@;
	main::lm("bad report from subscribe ($@)",$self->service(),"warning");
	return;
    };
    $main::debug > 1 and main::lm("got report ".$report->unicode(),$self->service());
    $main::dispatcher->report($report);
    DDgrey::Sync->update_fetched($self->{peername},time());
};

# ---- package init ----
return 1;

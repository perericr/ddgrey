# ---- class Select ----
# class för register över objekt som lyssnar på filhandtag

package DDgrey::Select;

use strict;
use integer;

use Data::Dumper; # DEBUG
use IO::Select;
use List::MoreUtils qw(uniq);
use DDgrey::Perl6::Parameters;

# ---- konstruktor ----

sub new($class){
    # retur : nytt objekt
    # effekt: kan sätta undantag

    my $self={};
    $self->{closing}=0;
    $self->{select}=IO::Select->new();
    $self->{select} or main::error("can't start select ($!)");
    $self->{write_select}=IO::Select->new();
    $self->{write_select} or main::error("can't start select ($!)");
    $self->{read_more}={};

    # maximal väntetid (kan ändras av kortare intervall)
    $self->{sleep}=5;

    return bless($self,$class);
};

# ---- metoder för registrering ----

sub register_read($self,$fh,$f){
    # effekt: registerar fh i select och f för att hantera läsning från fh

    $self->{select}->add($fh);
    $self->{read_handler}->{$fh}=$f;
};

sub register_read_and_exception($self,$fh,$f,$timeout){
    # effekt: registerar fh i select och
    # f för att hantera läsning och undantag från fh
    # ev undantag om inget lästs efter timeout

    # timeout för läsning
    my $t=$self->register_timer($timeout // 60,sub{&$f($fh)},$fh);
    
    $self->register_read($fh,sub{
	my $fh=shift();
	$t->{time}=time()+$t->{timeout};
	&$f($fh);
    });
    $self->register_exception($fh,$f);
};

sub register_line($self,$fh,$f){
    # effekt: registerar fh i select och f för att hantera rad läst från fh
    # pre   : fh är satt icke-blockerande

    $self->{select}->add($fh);
    $self->{read_handler}->{$fh}=sub{
	if(!defined($self->{read_more}->{$fh})){
	    $fh->eof() and return $self->handle_exception($fh);
	};

	if(defined(my $line=$fh->getline())){
	    # markera att fler rader kan finnas
	    $self->{read_more}->{$fh}=$fh;
	    # kör
	    &$f($line);
	}
	else{
	    # ta bort markering att fler rader finns
	    delete $self->{read_more}->{$fh};
	};
    };
};

sub register_exception($self,$fh,$f){
    # effekt: registerar fh i select och f för att hantera undantag från fh
    $self->{exception_handler}->{$fh}=$f;
};

sub unregister($self,$fh;$r,$w){
    # effekt: avregistrera fh, som standard från alla register
    #         om r==1 avregistreras från läsning, om w==1 från skrivning
   
    if($r//1){
	$self->{select}->remove($fh);
	delete($self->{read_more}->{$fh});
	delete($self->{read_handler}->{$fh});
	delete($self->{exception_handler}->{$fh});
	if(defined($self->{fh_timer}->{$fh})){
	    $self->unregister_timer($self->{fh_timer}->{$fh});
	    delete($self->{fh_timer}->{$fh});
	};
    };
    if($w//1){
	$self->{write_select}->exists($fh) and $self->{write_select}->remove($fh);
	delete($self->{write_buffer}->{$fh});
    };
};

sub register_timer($self,$timeout,$f;$fh){
    # effekt: registerar funktion f att köra om timeout sekunder
    #         registrera som tillhörande fh om sådan given
    my $t={
	function=>$f,
	timeout=>$timeout,
	time=>time()+$timeout
    };
    push @{$self->{timer}},$t;
    if(defined($fh)){
	$self->{fh_timer}->{$fh}=$t;
    };
    return $t;
};

sub register_interval($self,$interval,$f){
    # effekt: registerar funktion f att köra var f sekund

    # anger att körning börjar efter väntetid
    my $i={
	function=>$f,
	called=>time(),
	interval=>$interval
    };
    push(@{$self->{interval}},$i);
    return $i;
};

sub unregister_timer($self,$t){
    foreach my $i (0 .. $#{$self->{timer}}){
       if(defined($self->{timer}->[$i]) and $t==$self->{timer}->[$i]){
	   delete($self->{timer}->[$i]);
       };
    };
};

sub unregister_interval($self,$t){
    foreach my $i (0 .. $#{$self->{interval}}){
	$t==$self->{interval}->[$i] and delete($self->{interval}->[$i]);
    };
};

# ---- metoder för körning ----

sub sleep($self){
    # retur: hur länge vänta i select

    my $sleep=$self->{sleep};

    # kolla interval
    foreach my $i (0 .. $#{$self->{interval}}){
	defined(my $interval=$self->{interval}->[$i]) or next;
	$interval->{interval} < $sleep and $sleep=$interval->{interval};
    };

    # kolla timer
    foreach my $i (0 .. $#{$self->{timer}}){
	defined(my $timer=$self->{timer}->[$i]) or next;
	my $s=$timer->{time}-time();
	$s < $sleep and $sleep=$s;
    };

    # minst 0
    $sleep < 0 and $sleep=0;

    return $sleep;
};

sub run($self){
    # effekt: väntar på filhandtagsaktivitet och skickar till lyssnare

    while(!$self->{closing}){
	$self->run_once(undef);
    };
};

sub run_once($self,$sleep){

    $sleep //= (keys %{$self->{read_more}} ? 0 : $self->sleep());
    $main::debug > 2 and main::lm("running select sleep:$sleep handles:".(scalar $self->{select}->handles()));
    
    my($read,$write,$exception)=IO::Select->select($self->{select},$self->{write_select},$self->{select},$sleep);
    
    # handtag med undantag
    foreach my $fh (@$exception){
	$self->handle_exception($fh);
    };
    
    # läsbara handtag
    # warn Dumper([$self->{select}->handles()],$self->{read_more});
    foreach my $fh (uniq(@$read,keys %{$self->{read_more}})){
	defined(my $f=$self->{read_handler}->{$fh}) or next;
	&$f($fh);
    };
    
    # kolla timer
    foreach my $i (0 .. $#{$self->{timer}}){
	defined(my $timer=$self->{timer}->[$i]) or next;
	if($timer->{time} <= time()){
	    &{$timer->{function}}();
	    # tar bort timer
	    delete $self->{timer}->[$i];
	};
    };
    
    # kolla intervall
    foreach my $interval (@{$self->{interval}}){
	if($interval->{called}+$interval->{interval} < time()){
	    &{$interval->{function}}();
	    # uppdatera senast-anropad
	    $interval->{called}=time();
	};
    };
    
    # handtag som kan skrivas till
    $self->run_write($write);
};

sub write($self,$fh,$line;$next){
    # effekt: skriv line till fh (eller lägg i buffer)
    #         kör next när skickat
    
    $self->{write_select}->exists($fh) or $self->{write_select}->add($fh);
    $self->{write_buffer}->{$fh} //= [];
    push @{$self->{write_buffer}->{$fh}},$line;
    defined($next) and push @{$self->{write_buffer}->{$fh}},$next;
    $self->run_write([$fh]);
};

sub run_write($self,$write){
    # effekt: försök skriva från write_buffer till filhandtag i write
    #         om write_buffer innehåller funktioner körs de
    
    for my $fh (@$write){
      CHUNK:while(defined(my $f=shift(@{$self->{write_buffer}->{$fh}}))){
	    if(ref($f)){
		# kör om det är funktion
		&$f();
	    }
	    else{
		# annars försök skriva
		my $sent=$fh->connected() ? $fh->send($f) : undef;
		if(defined($sent)){
		    if($sent == length($f)){
			$fh->flush();
		    }
		    else{
			$main::debug > 2 and main::lm("partial write on $fh (sent $sent of ".length($self->{write_buffer}->{$fh}).")",undef,"warning");
			unshift @{$self->{write_buffer}->{$fh}},substr($f,$sent);
			last CHUNK;
		    }
		}
		else{
		    main::lm("could not write to $fh",undef,"warning");
		    unshift @{$self->{write_buffer}->{$fh}},$f;
		    last CHUNK;
		};
	    };	    
	};

	# ta bort om inget mer fanns att skriva
	if(!@{$self->{write_buffer}->{$fh}}){
	    delete $self->{write_buffer}->{$fh};
	    $self->{write_select}->remove($fh);
	};
    };
};

sub load($self){
    # effekt: belastning 0=låg 1=hög 2=mycket hög

    my $count=scalar $self->{select}->handles();
    $count > 100 and return 2;
    $count > 50 and return 1;
    return 0;
};

sub handle_exception($self,$fh){
    # effekt: hanterar undantag (ofta stängd förbindelse) på fh

    if(defined($self->{exception_handler}->{$fh})){
	return &{$self->{exception_handler}->{$fh}}($fh);
    }
    else{
	# avregistrera
	$main::debug and main::lm("default closing of $fh");
        $self->unregister($fh);
    };
};

sub exit($self){
    # effekt: avslutar loop
    $self->{closing}=1;
};

sub close($self){
    # effekt: stänger select och skickar undantag till registrerade fh
    
    foreach my $fh ($self->{select}->handles()){
	$self->handle_exception($fh);
    };
};

# ---- package init ----
return 1;

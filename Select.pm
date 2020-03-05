# ---- class Select ----
# listener to file handles

package DDgrey::Select;

use strict;
use integer;

use Encode qw(encode decode);
use Data::Dumper; # DEBUG
use IO::Select;
use List::MoreUtils qw(uniq);
use DDgrey::Perl6::Parameters;

# ---- constructor ----

sub new($class){
    # return: new object
    # effect: may raise exception

    my $self={};
    $self->{closing}=0; # 1 = main select loop should quit
    $self->{select}=IO::Select->new();
    $self->{select} or main::error("can't start select ($!)");
    $self->{write_select}=IO::Select->new();
    $self->{write_select} or main::error("can't start select ($!)");
    $self->{read_more}={}; # internal mark of more to read, from register_line

    # max waiting time (can be shorter by specific instructions)
    $self->{sleep}=5;

    return bless($self,$class);
};

# ---- methods for registrering ----

sub register_read($self,$fh,$f){
    # effect: registers fh with select, using f for handling read from fh

    $self->{select}->add($fh);
    $self->{read_handler}->{$fh}=$f;
};

sub register_read_and_exception($self,$fh,$f,$timeout){
    # effect: registers fh with select, using
    #         f for reading and exceptions from fh
    #         may raise exception if timeout passed

    # read timeout
    my $t=$self->register_timer($timeout // 60,sub{&$f($fh)},$fh);
    
    $self->register_read($fh,sub{
	my $fh=shift();
	$t->{time}=time()+$t->{timeout};
	&$f($fh);
    });
    $self->register_exception($fh,$f);
};

sub register_line($self,$fh,$f){
    # effect: registers fh with select, using f for handling lines read from fh
    #         lines will be decoded from UTF-8
    # pre   : fh is set to non-blocking

    $self->{select}->add($fh);
    $self->{read_handler}->{$fh}=sub{
	if(!defined($self->{read_more}->{$fh})){
	    $fh->eof() and return $self->handle_exception($fh);
	};

	if(defined(my $b_line=$fh->getline())){
	    # decode
	    my $line=eval{decode('UTF-8',$b_line)};
	    if($@){
		# warn if decode error
		main::lm("decode error on $fh ($@)",undef,"warning");
	    }
	    else{
		# else, run line handler
		&$f($line);
	    };
	    
	    # mark possibly more lines
	    $self->{read_more}->{$fh}=$fh;
	}
	else{
	    # remove mark for possibly more lines
	    delete $self->{read_more}->{$fh};
	};
    };
};

sub register_exception($self,$fh,$f){
    # effect: registers fh with select, using f for handling exceptions from fh
    $self->{exception_handler}->{$fh}=$f;
};

sub unregister($self,$fh;$r,$w){
    # effect: unregister fh, by default from all registers
    #         if r==1 from reading, if w==1 from writing
   
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
    # return: timer object
    # effect: registers function f to run in timeout seconds
    #         registers self as belonging to fh if given

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
    # effect: registers function f to run each interval seconds
    # return: interval object

    # create post, mark to make first run after interval
    my $i={
	function=>$f,
	called=>time(),
	interval=>$interval
    };
    push(@{$self->{interval}},$i);
    return $i;
};

sub unregister_timer($self,$t){
    # effect: unregisters timer t
    
    foreach my $i (0 .. $#{$self->{timer}}){
       if(defined($self->{timer}->[$i]) and $t==$self->{timer}->[$i]){
	   delete($self->{timer}->[$i]);
       };
    };
};

sub unregister_interval($self,$t){
    # effect: unregisters interval t
    
    foreach my $i (0 .. $#{$self->{interval}}){
	$t==$self->{interval}->[$i] and delete($self->{interval}->[$i]);
    };
};

# ---- methods for running ----

sub sleep($self){
    # return: number of seconds to wait in select until timeout

    my $sleep=$self->{sleep};

    # check intervals
    foreach my $i (0 .. $#{$self->{interval}}){
	defined(my $interval=$self->{interval}->[$i]) or next;
	$interval->{interval} < $sleep and $sleep=$interval->{interval};
    };

    # check timers
    foreach my $i (0 .. $#{$self->{timer}}){
	defined(my $timer=$self->{timer}->[$i]) or next;
	my $s=$timer->{time}-time();
	$s < $sleep and $sleep=$s;
    };

    # at least 0
    $sleep < 0 and $sleep=0;

    return $sleep;
};

sub run($self){
    # effect: waits for all file handle activity (or timeout)
    #         and runs registered event handlers until closing

    while(!$self->{closing}){
	$self->run_once(undef);
    };
};

sub run_once($self,$sleep){
    # effect: waits for one file handle activity (or timeout)
    #         and runs registered event handler

    $sleep //= (keys %{$self->{read_more}} ? 0 : $self->sleep());
    $main::debug > 2 and main::lm("running select sleep:$sleep handles:".(scalar $self->{select}->handles()));
    
    my($read,$write,$exception)=IO::Select->select($self->{select},$self->{write_select},$self->{select},$sleep);
    
    # file handles with exceptions
    foreach my $fh (@$exception){
	$self->handle_exception($fh);
    };
    
    # readable file handles
    foreach my $fh (uniq(@$read,keys %{$self->{read_more}})){
       	if(defined(my $f=$self->{read_handler}->{$fh})){
	    &$f($fh);
	}
	else{
	    delete $self->{read_more}->{$fh};
	    next;
	};
    };
    
    # check timers
    foreach my $i (0 .. $#{$self->{timer}}){
	defined(my $timer=$self->{timer}->[$i]) or next;
	if($timer->{time} <= time()){
	    # run and remove timer
	    &{$timer->{function}}();
	    delete $self->{timer}->[$i];
	};
    };
    
    # check intervals
    foreach my $interval (@{$self->{interval}}){
	if($interval->{called}+$interval->{interval} < time()){
	    # run and update interval
	    &{$interval->{function}}();
	    $interval->{called}=time();
	};
    };
    
    # handles that may be written to
    $self->run_write($write);
};

sub write($self,$fh,$line;$next){
    # effect: writes line to fh (or add to buffer)
    #         runs next when sent
    
    $self->{write_select}->exists($fh) or $self->{write_select}->add($fh);
    $self->{write_buffer}->{$fh} //= [];
    push @{$self->{write_buffer}->{$fh}},$line;
    defined($next) and push @{$self->{write_buffer}->{$fh}},$next;
    $self->run_write([$fh]);
};

sub run_write($self,$write){
    # effect: attempts to write from buffers to file handles in write
    #         if write buffer contains a function, it will be run instead
    
    for my $fh (@$write){
      CHUNK:while(defined(my $f=shift(@{$self->{write_buffer}->{$fh}}))){
	    if(ref($f)){
		# run if function
		&$f();
	    }
	    else{
		# otherwise, write
		my $u=encode('UTF-8',$f);
		my $sent=$fh->connected() ? ($fh->send($u)) : undef;
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
		    $main::debug and main::lm("could not write to $fh",undef);
		    unshift @{$self->{write_buffer}->{$fh}},$f;
		    last CHUNK;
		};
	    };	    
	};

	# delete buffer if nothing more to write
	if(!@{$self->{write_buffer}->{$fh}}){
	    delete $self->{write_buffer}->{$fh};
	    $self->{write_select}->remove($fh);
	};
    };
};

sub load($self){
    # return: internal system load, 0=low 2=very high

    my $count=scalar $self->{select}->handles();
    $count > 100 and return 2;
    $count > 50 and return 1;
    return 0;
};

sub handle_exception($self,$fh){
    # effect: handles exception (often closed connection) on fh

    # remove mark of more to read
    delete $self->{read_more}->{$fh};
    
    if(defined($self->{exception_handler}->{$fh})){
	# run registered handler
	return &{$self->{exception_handler}->{$fh}}($fh);
    }
    else{
	# otherwise, unregister
	$main::debug and main::lm("default closing of $fh");
        $self->unregister($fh);
    };
};

sub exit($self){
    # effect: marks loop for closing
    
    $self->{closing}=1;
};

sub close($self){
    # effect: closes select, send exception to registered file handles
    
    foreach my $fh ($self->{select}->handles()){
	$self->handle_exception($fh);
    };
};

# ---- package init ----
return 1;

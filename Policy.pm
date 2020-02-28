# ---- class Policy ----
# policy per IP address

package DDgrey::Policy;

use strict;
use integer;

use Data::Dumper; # DEBUG
use List::Util qw(sum max min);
use DDgrey::Perl6::Parameters;
use Net::Netmask;
use Socket;

use DDgrey::Config;
use DDgrey::DBStore qw($db);
use DDgrey::DNS qw(resolved);
use DDgrey::Report;
use DDgrey::Traps qw($traps);

use parent qw(DDgrey::DBModel);

my $search_duration;
my $trusted;

# plugins for checking (traps, unknown recipients ...)
our @check_plugin=();

# description
our $table='policy';
our @fields=('id integer primary key autoincrement','ip text unique','domain text','grey integer','black integer','fdate integer','tdate integer','score integer','reason text');
our %indexes=(
    'id'=>['id'],
    'ip'=>['ip'],
    'domain'=>['domain'],
    );

# ---- class methods ----

sub check($class,$ip,$from,$to,$next){
    # effect: eventually runs next with "white", "grey" eller "black" for
    #         combination of ip, from och to
    #         logs call, for use in individual triplet greylisting

    # check whitelist
    foreach my $m (@$trusted){
	if($m->match($ip)){
	    $main::debug > 1 and main::lm("trusted, always white for $ip",'policy');
	    return &$next('white');
	};
    };
    
    $class->ensure_policy(
	$ip,
	sub{
	    my $self=shift();
	    $self->check_resolved($ip,$from,$to,$next);
	});
};
    
sub process_report($class,$report){
    # effect: updates policy based on report

    my $self=$class->lookup($report->{ip});
    $self or return;

    # skips check
    if($report->{event} eq 'check'){
	return;
    };
    
    # skips good reports if whitelisted
    if($report->{event}=~/^(?:ok)$/ and !defined($self->{grey}) and !defined($self->{black})){
	return;
    };

    # skips bad reports if blacklisted
    if(not $report->{event}=~/^(?:ok)$/ and defined($self->{black})){
	return;
    };

    # otherwise, update
    $main::debug and main::lm("start updating policy for $self->{ip} due to report","policy");
    $self->update(sub{$self->{prel}//0 or $self->save()});
};

sub delete_expired($class){
    # effect: deletes expired policy
    
    $main::debug and main::lm("running delete_expired","policy");
    $db->query("delete from policy where tdate < ?",time());
};
       
# ---- constructors ----

sub ensure_policy($class,$ip,$next){
    # effect: runs next, with new policy for ip

    my $self=$class->lookup($ip);
    if($self){
	$main::debug > 1 and main::lm("found saved policy for $ip",'policy');
	return &$next($self);
    };

    # create new
    $self=$class->new($ip);
    $self->update(sub{
	if(my $other=$class->lookup($ip)){
	    $main::debug and main::lm("other request already created policy for $ip, not saving",'policy');
	    return &$next($other);
	};
	$self->save();
	&$next($self);
    });
};

sub lookup($class,$ip){
    # return: possible existing policy for ip
    
    my $self=$db->query_first('select * from policy where ip=?',$ip);
    $self or return undef;
    bless($self,$class);
    return $self;
};

sub new($class,$ip){
    # return: new (unsaved) policy for ip
    
    my $self={
	ip=>$ip,
    };
    bless($self,$class);
    return $self;
};

# ---- methods for access ----

sub check_resolved($self,$ip,$from,$to,$next){
    # effect: eventually runs next with "white", "grey" eller "black" for
    #         combination of ip, from och to
    #         logs call, for use in individual triplet greylisting
    
    # hämta resultat
    my $res=$self->check_status($from,$to);

    # make report of ckeck
    # used for individual triplet greylisting
    my $report=DDgrey::Report->new({
	unique_event=>1,
	reporter=>'check',
	event=>'check',
	'ip'=>$ip,
	'e_from'=>$from,
	'e_to'=>$to,
    });
    $main::debug > 1 and main::lm("reporting check ".$report->unicode(),"policy");
    $main::dispatcher->report($report);

    # gör rapport om träffat spamtrap
    $traps->check($ip,$from,$to);
    
    return &$next($res);
};

sub check_status($self,$from,$to){
    # return: status for this policy for from och to

    # black or grey if blacklisted
    if($self->{black}){
	# answer grey if recently blacklisted (to avoid leak traps information)
	if(time() > $self->{black}){
	    return 'grey';
	}
	else{
	    return 'black';
	};
    };

    # send white
    if(!defined($self->{grey})){
	return 'white';
    };

    # otherwise, search for triplet in previous checks
    if(DDgrey::Report->domain_check($self->{domain},$from,$to,time()-$self->{grey}-($main::config->{retry} // $search_duration),time()-$self->{grey})){
	return 'white';
    }
    else{
	return 'grey';
    };
};

# ---- methods for changing -----

sub resolve($self,$next){
    # effect: sets value of domain, runs next

    DDgrey::DNS::verified_domain_next(
	$self->{ip},
	sub{
	    my $domain=shift();
	    $self->{domain}=defined($domain) ? $domain : $self->{ip};
	    &$next($domain);
	}
    );
};

sub update($self,$next){
    # effect: calculates policy based on reports, then runs next
    $main::debug and main::lm("start updating policy for $self->{ip}","policy");
    
    $self->resolve(sub{
	$self->{resolved}=shift();
	$self->update_if_ready($next);
    });
    DDgrey::DNS::is_dynamic_next($self->{ip},sub{
	$self->{is_dynamic}=shift();
	$self->update_if_ready($next);
    });
    DDgrey::DNS::bl_lookup_next($self->{ip},'zen.spamhaus.org',sub{
	my $res=shift();
	$self->{spamhaus}=defined($res) ? @$res : undef;
	$self->update_if_ready($next);
   });
    DDgrey::DNS::bl_lookup_next($self->{ip},'bl.spamcop.net',sub{
	my $res=shift();
	$self->{spamcop}=defined($res) ? @$res : undef;
	$self->update_if_ready($next);
   });
    DDgrey::DNS::bl_lookup_next($self->{ip},'dnsbl.sorbs.net',sub{
	my $res=shift();
	$self->{sorbs}=defined($res) ? grep {$_ ne '127.0.0.10' } @$res : undef;
	$self->update_if_ready($next);
   });
    DDgrey::DNS::dnswl_score_next($self->{ip},sub{
	$self->{dnswl}=shift();
	$self->update_if_ready($next);
    });
};

sub update_if_ready($self,$next){
    # effect: calculates policy based on reports, then runs next
    #         if name resolution is done
    
    if(
	exists($self->{resolved}) and 
	exists($self->{is_dynamic}) and 
	exists($self->{spamhaus}) and 
	exists($self->{spamcop}) and 
	exists($self->{sorbs}) and 
	exists($self->{dnswl})
	){
	$self->update_resolved($next);
    };
};

sub update_resolved($self,$next){
    # effect: calculates policy based on reports, then runs next
    # pre   : name resolution is done

    $main::debug and main::lm("updating policy for $self->{ip}","policy");

    # duration constants
    my $search_duration=$main::config->{search_duration} // 60*60*24*60;
    my $policy_duration=$main::config->{policy_duration} // 60*60*24*7;
    my $grey_min=$main::config->{grey_min} // 10;
    my $grey_short=$main::config->{grey_short} // 60*10;
    my $grey_default=$main::config->{grey_default} // 60*60*4;
    my $grey_long=$main::config->{grey_long} // 60*60*12;
    my $grey_max=$main::config->{grey_max} // 60*60*24;
    
    # default values
    $self->{fdate}=time();
    $self->{tdate}=time()+$policy_duration;
    $self->{black}=undef;
    $self->{grey}=$grey_default;

    # variables for score and reason
    my $scores={};
    my $reasons={};

    # -- IP reputation from external services --

    # sätt prel om domän är preliminär
    if(!defined($self->{resolved})){
	$self->set_prel();
    };
    # lower score for non-validated domain
    if($self->{resolved} and not $self->{is_dynamic}//1){
	if($self->{domain}=~/^[\d\.\:]+$/){
	    $scores->{reverse}=-10;
	    $reasons->{reverse}='no reverse IP';
	}
	elsif(not $self->{domain}=~/.*\.(?:com|org|net|gov|edu|mil|int|\w\w)$/){
	    $scores->{novelty}=-5;
	    $reasons->{novelty}='novelty TLD';
	};
    };

    # lower score for dynamic IP
    if(!defined($self->{is_dynamic})){
	$self->set_prel();
    };
    if($self->{is_dynamic}){
	$scores->{dynamic}=-10;
	$reasons->{dynamic}='dynamic IP';
    };

    # lowest score if listed in Spamhaus ZEN 
    if(!defined($self->{spamhaus})){
	$self->set_prel();
    };
    if($self->{spamhaus}){
	$scores->{spamhaus}=-100;
	$reasons->{spamhaus}='Spamhaus ZEN';
    };

    # lowest score if listed in Spamcop 
    if(!defined($self->{spamcop})){
	$self->set_prel();
    };
    if($self->{spamcop}){
	$scores->{spamcop}=-80;
	$reasons->{spamcop}='Spamcop';
    };

    # lowest score if listed in SORBS
    if(!defined($self->{sorbs})){
	$self->set_prel();
    };
    if($self->{sorbs}){
	$scores->{sorbs}=-10;
	$reasons->{sorbs}='SORBS';
    };

    # score DNSWL
    if(!defined($self->{dnswl})){
	$self->set_prel();
    }
    else{
	if($self->{dnswl}==1){
	    $scores->{dnswl}=10;
	    $reasons->{dnswl}='DNSWL low';
	};
	if($self->{dnswl} > 1){
	    $scores->{dnswl}=50;
	    $reasons->{dnswl}='DNSWL medium or high';
	};
    };

    # -- recent correspondence --
    
    my $count_1=DDgrey::Report->domain_count($self->{domain},'ok',time()-$search_duration,time()-60*60*24);
    my $count_7=DDgrey::Report->domain_count($self->{domain},'ok',time()-$search_duration,time()-60*60*24*7);
    $self->{ok_7}=$count_7;
    if($count_1 > 0){
	$reasons->{ok}='mail accepted';
	$scores->{ok}=5;
    };
    if($count_7 > 4){
	$reasons->{ok}='5 mail accepted';
	$scores->{ok}=20;
    };
    if($count_7 > 14){
	$reasons->{ok}='15 mail accepted';
	$scores->{ok}=30;
    };

    # -- blacklist result adjustment --
    
    # remove score from probably erratic SORBS listing
    if(($scores->{ok}//0 >= 20 or $self->{dnswl} > 1) and $reasons->{sorbs}){
	$reasons->{sorbs}='SORBS false';
	delete $scores->{sorbs};
    };
    # remove score from probably erratic Spamcop listing
    if(($scores->{ok}//0 >= 30 or $self->{dnswl} > 1) and $reasons->{spamcop}){
	$reasons->{spamcop}='Spamcop false';
	delete $scores->{spamcop};
    };

    # -- manual reports --
    
    my $count;
    
    $count=DDgrey::Report->count_grouped($self->{ip},'manual',time()-$search_duration,time());
    if($count > 0){
	$reasons->{manual}='manual report';
	$scores->{manual}=-100-50*$count;
    };

    # -- spam traps --

    if(DDgrey::Report->find($self->{ip},'hard_trap',time()-$search_duration,time())){
	$reasons->{hard_trap}='hard trap';
	$scores->{hard_trap}=-500;
    };

    $count=DDgrey::Report->count_grouped($self->{ip},'soft_trap',time()-$search_duration,time());
    if($count == 1){
	$reasons->{soft_trap}='soft trap';
	$scores->{soft_trap}=-50;
    };
    if($count > 1){
	$reasons->{soft_trap}='soft traps';
	$scores->{soft_trap}=-50*$count;
    };

    # -- unknown recipients --

    $count=DDgrey::Report->count_grouped($self->{ip},'unknown',time()-$search_duration,time());
    if($count > 0){
	# accept some percentage unknown from trusted domain
	if($self->{count_7}//0 > 0 and ($self->{dnswl}//0 > 0 or $scores->{ok}//0 > 10) and !($self->{spamcop}//1) and !($self->{spamhaus}//1) and !($self->{is_dynamic}//1)){
	    no integer;
	    my $share=$count / $self->{count_7};
 	    if($share > 0.1){
		$reasons->{unknown}='many unknown from reputable';
		$scores->{unknown}=-10*($count+1);
	    }
	    else{
		$reasons->{unknown}='some unknown from reputable';
	    };
	}
	else{
	    $reasons->{unknown}='unknown from non-reputable';
	    $scores->{unknown}=-30*$count;
	};
   };
 
    # -- spam --

    $count=DDgrey::Report->count_grouped($self->{ip},'spam',time()-$search_duration,time());
    if($count > 0 and $count <= 2){
	$reasons->{spam}='spam';
	$scores->{spam}=-20*($count);
    };
    if($count > 2){
	$reasons->{spam}='many spam';
	$scores->{spam}=-50*($count);
    };

    # -- relay attempt --

    $count=DDgrey::Report->count_grouped($self->{ip},'relay',time()-$search_duration,time());
    if($count > 0){
	$reasons->{relay}='relay';
	$scores->{relay}=-60*($count);
    };

    # -- disconnect --
    
    $count=DDgrey::Report->count_grouped($self->{ip},'disconnect',time()-$search_duration,time());
    if($count > 0){
	$reasons->{disconnect}='disconnect';
	$scores->{disconnect}=max(-10*($count),-50);
    };

    # -- conclude and make delay durations or blacklist --

    $self->{reason}=(join(',',sort values %{$reasons}) or 'basic');
    my $score=sum(values %{$scores}) // 0;
    $self->{score}=$score;
    if($score < -100){
	$self->set_black();
    }
    elsif($score < -20){
	$self->{grey}=$grey_max;
    }
    elsif($score < -5){
	$self->{grey}=$grey_long;
    }
    elsif($score < 5){
	$self->{grey}=$grey_default;
    }
    elsif($score < 10){
	$self->{grey}=$grey_short;
    }
    elsif($score < 20){
	$self->{grey}=$grey_min;
    }
    else{
	$self->{grey}=undef;
    };

    $main::debug and main::lm("updated policy for $self->{ip} to score: $self->{score} reason: $self->{reason}","policy");

    # continues
    &$next();
};

sub set_black($self){
    # effect: sets self to blacklist

    # blacklisting is enabled directly for any non-Null value of black
    # black is timestamp from when "black" will be returned directly
    # before that, "grey" is returned
    # this is done, with a random delay, to prevent leaking information on traps
    
    $self->{grey}=undef;
    $self->{black}=time()+60*60*24+int(rand(60*60*24*7)); # när blir black
};

sub set_prel($self,$reason){
    # effect: sets self to preliminary (short valid time)
    $self->{tdate}=time()+60*60*1;
    $self->{prel}=1;
};

# ---- package init ----

# fetch values from configuration
push @main::on_done,sub{
    $search_duration=$main::config->{search_duration} // 60*60*24*60;
    foreach my $r (@{$main::config->{trusted}}){
	for my $ip (resolved($r)){
	    my $m=Net::Netmask->new2($ip) or main::error("unkown address/range $ip");
	    push @$trusted,$m;
	};
    };
};

# delete expired policy
push @main::on_done,sub{
    __PACKAGE__->delete_expired();
    $main::select->register_interval(
	60,
	sub{
	    __PACKAGE__->delete_expired();
	}
    );
};

DDgrey::DBStore::register_model(__PACKAGE__);
return 1;

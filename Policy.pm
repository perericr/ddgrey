# ---- class Policy ----
# class för IP address policy

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

# plugin för check (kontroll av trap, okända mottagare mm)
our @check_plugin=();

# beskrivning
our $table='policy';
our @fields=('id integer primary key autoincrement','ip text unique','domain text','grey integer','black integer','fdate integer','tdate integer','score integer','reason text');
our %indexes=(
    'id'=>['id'],
    'ip'=>['ip'],
    'domain'=>['domain'],
    );

# ---- klassmetoder ----

sub check($class,$ip,$from,$to,$next){
    # effekt: kör next med "white", "grey" eller "black" för
    #         kombination av ip, from och to
    #         loggar förfrågan från dessa tre värden

    # kollar om värd är vitlistad
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
    # effekt: uppdaterar policy baserat på report

    my $self=$class->lookup($report->{ip});
    $self or return;

    # hoppar över check
    if($report->{event} eq 'check'){
	return;
    };
    
    # hoppar över bra rapporter för whitelist
    if($report->{event}=~/^(?:ok)$/ and !defined($self->{grey}) and !defined($self->{black})){
	return;
    };

    # hoppar över dåliga rapporter för blacklist
    if(not $report->{event}=~/^(?:ok)$/ and defined($self->{black})){
	return;
    };

    # uppdatera i övriga fall
    $main::debug and main::lm("start updating policy for $self->{ip} due to report","policy");
    $self->update(sub{$self->{prel}//0 or $self->save()});
};

sub delete_expired($class){
    # effekt: tar bort utgången policy
    $main::debug and main::lm("running delete_expired","policy");
    $db->query("delete from policy where tdate < ?",time());
};
       
# ---- konstruktorer ----

sub ensure_policy($class,$ip,$next){
    # effekt: kör next med policy för ip

    my $self=$class->lookup($ip);
    if($self){
	$main::debug > 1 and main::lm("found saved policy for $ip",'policy');
	return &$next($self);
    };

    # gör ny
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
    # retur: ev policy för ip
    my $self=$db->query_first('select * from policy where ip=?',$ip);
    $self or return undef;
    bless($self,$class);
    return $self;
};

sub new($class,$ip){
    # retur : ny policy för ip
    my $self={
	ip=>$ip,
    };
    bless($self,$class);
    return $self;
};

# ---- metoder för åtkomst ----

sub check_resolved($self,$ip,$from,$to,$next){
    # effekt: kör next med "white", "grey" eller "black" utifrån
    #         from, to och policy i self
    #         loggar förfrågan från dessa tre värden
    
    # hämta resultat
    my $res=$self->check_status($from,$to);

    # gör rapport om check
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
    # retur: status för denna policy för from och to

    # svara black eller grey om svartlistad
    if($self->{black}){
	# svara grey om nyligen svartlistad (för att undvika avslöja traps)
	if(time() > $self->{black}){
	    return 'grey';
	}
	else{
	    return 'black';
	};
    };

    # skicka direkt om vitlistad
    if(!defined($self->{grey})){
	return 'white';
    };

    # sök i övriga fall bland tidigare check
    if(DDgrey::Report->domain_check($self->{domain},$from,$to,time()-$self->{grey}-($main::config->{retry} // $search_duration),time()-$self->{grey})){
	return 'white';
    }
    else{
	return 'grey';
    };
};

# ---- metoder för ändring -----

sub resolve($self,$next){
    # effekt: sätter värde domain, kör next

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
    # effekt: räknar ut policy baserat på rapporter, kör sen next
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
    # effekt: räknar ut policy baserat på rapporter, kör sen next
    # pre   : namnuppslagningar är skickade
    
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
    # effekt: räknar ut policy baserat på rapporter, kör sen next
    # pre   : uppgifter från namnuppslagning är färdiga

    $main::debug and main::lm("updating policy for $self->{ip}","policy");

    # tider
    my $search_duration=$main::config->{search_duration} // 60*60*24*60;
    my $policy_duration=$main::config->{policy_duration} // 60*60*24*7;
    my $grey_min=$main::config->{grey_min} // 10;
    my $grey_short=$main::config->{grey_short} // 60*10;
    my $grey_default=$main::config->{grey_default} // 60*60*4;
    my $grey_long=$main::config->{grey_long} // 60*60*12;
    my $grey_max=$main::config->{grey_max} // 60*60*24;
    
    # defaultvärden
    $self->{fdate}=time();
    $self->{tdate}=time()+$policy_duration;
    $self->{black}=undef;
    $self->{grey}=$grey_default;

    # poäng från olika granskningar mellan -100 och 100
    my $scores={};
    my $reasons={};

    # -- rykte för IP från externa tjänster --

    # sätt prel om domän är preliminär
    if(!defined($self->{resolved})){
	$self->set_prel();
    };
    # längre tid för icke-validerad domän
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

    # längre tid för dynamiskt IP
    if(!defined($self->{is_dynamic})){
	$self->set_prel();
    };
    if($self->{is_dynamic}){
	$scores->{dynamic}=-10;
	$reasons->{dynamic}='dynamic IP';
    };

    # längst tid om listad i spamhaus
    if(!defined($self->{spamhaus})){
	$self->set_prel();
    };
    if($self->{spamhaus}){
	$scores->{spamhaus}=-100;
	$reasons->{spamhaus}='Spamhaus ZEN';
    };

    # längst tid om listad i spamcop
    if(!defined($self->{spamcop})){
	$self->set_prel();
    };
    if($self->{spamcop}){
	$scores->{spamcop}=-80;
	$reasons->{spamcop}='Spamcop';
    };

    # längst tid om listad i SORBS (utöver dynamisk)
    if(!defined($self->{sorbs})){
	$self->set_prel();
    };
    if($self->{sorbs}){
	$scores->{sorbs}=-10;
	$reasons->{sorbs}='SORBS';
    };

    # kollar DNSWL
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

    # -- senaste korrespondens --
    
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

    # -- justering av BL-resultat --
    
    # ta bort poäng för troligen felaktigt SORBS-listade
    if(($scores->{ok}//0 >= 20 or $self->{dnswl} > 1) and $reasons->{sorbs}){
	$reasons->{sorbs}='SORBS false';
	delete $scores->{sorbs};
    };
    # ta bort poäng för troligen felaktigt Spamcop-listade
    if(($scores->{ok}//0 >= 30 or $self->{dnswl} > 1) and $reasons->{spamcop}){
	$reasons->{spamcop}='Spamcop false';
	delete $scores->{spamcop};
    };

    # -- manuella rapporter av mail --
    
    my $count;
    
    $count=DDgrey::Report->count_grouped($self->{ip},'manual',time()-$search_duration,time());
    if($count > 0){
	$reasons->{manual}='manual report';
	$scores->{manual}=-100-50*$count;
    };

    # -- spamfällor --

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

    # -- okända mottagare --

    $count=DDgrey::Report->count_grouped($self->{ip},'unknown',time()-$search_duration,time());
    if($count > 0){
	# acceptera viss andel okända för betrodda domäner
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

    # -- försök till relay --

    $count=DDgrey::Report->count_grouped($self->{ip},'relay',time()-$search_duration,time());
    if($count > 0){
	$reasons->{relay}='relay';
	$scores->{relay}=-60*($count);
    };

    # -- avbrutet --
    
    $count=DDgrey::Report->count_grouped($self->{ip},'disconnect',time()-$search_duration,time());
    if($count > 0){
	$reasons->{disconnect}='disconnect';
	$scores->{disconnect}=max(-10*($count),-50);
    };

    # -- sammanfatta --

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

    # fortsätter
    &$next();
};

sub set_black($self){
    # effekt: sätter self till svartlistad
    $self->{grey}=undef;
    $self->{black}=time()+60*60*24+int(rand(60*60*24*7)); # när blir black
};

sub set_prel($self,$reason){
    # effekt: sätter self som preliminärt resultat (kort tid)
    $self->{tdate}=time()+60*60*1;
    $self->{prel}=1;
};

# ---- package init ----

# hämtar värden från konfiguration
push @main::on_done,sub{
    $search_duration=$main::config->{search_duration} // 60*60*24*60;
    foreach my $r (@{$main::config->{trusted}}){
	for my $ip (resolved($r)){
	    my $m=Net::Netmask->new2($ip) or main::error("unkown address/range $ip");
	    push @$trusted,$m;
	};
    };
};

# raderar utgångna poster
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

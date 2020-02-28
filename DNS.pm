# ---- package DNS ---
# functions for DNS resolution

package DDgrey::DNS;

use strict;
use integer;

use Cache::MemoryCache;
use Data::Dumper; # DEBUG
use Domain::PublicSuffix;
use Net::DNS::Resolver;
use DDgrey::Perl6::Parameters;
use Socket;

use parent qw(Exporter);

our @EXPORT_OK=qw(resolved);

our $suffix_parser;
our $resolver;

# ---- functions for DNS ----

sub ip_reverse($ip){
    # return: ip reversed
    $ip=~/(\d+)\.(\d+)\.(\d+)\.(\d+)/ and return "$4.$3.$2.$1";
    return undef;
};

# ---- functions for sync DNS (only for use in startup phase) ----

sub resolved($name){
    # return: name to array with ip addresses (if not already address)
    # effect: raises exception if nothing found
        
    $name=~/^[\d\.\:\/]+$/ and return $name;
    my $names=name_to_ips($name);
    defined($names->[0]) or main::error("no IP found for $name");
    return @$names;
};

sub ip_to_name($ip){
    # return: possible host name for ip
    my $ip_n=inet_aton($ip);
    return gethostbyaddr($ip_n,AF_INET);
};

sub name_to_ips($name){
    # return: array ref with possible ip addresses for name
    my @addr;
    (undef,undef,undef,undef,@addr)=gethostbyname($name);
    return [map {inet_ntoa($_)} @addr];
};

# ---- functions for async DNS ----

my $sockets={};
my $cache=Cache::MemoryCache->new({default_expires_in => 600});

sub dns_lookup($query,$next){
    # effect: looks up query, calls next with resulting Net::DNS::Packet
    #         calls with undef if no answer within time limit

    # check cache
    my $response=$cache->get($query);
    if(defined($response)){
	$main::debug > 1 and main::lm("cache hit $query","dns");
	return &$next($response);
    };
    
    # make new request
    $main::debug > 1 and main::lm("sending query $query","dns");
    my $socket=$resolver->bgsend($query);
    if(!defined($socket)){
	return &$next(undef);
    };
    $main::select->register_read_and_exception($socket,sub{
	my $socket=shift();
	my $response;
	if($resolver->bgisready($socket)){
	    $response=$resolver->bgread($socket);
	    $main::debug > 1 and main::lm("got response for $query","dns");
	}
	else{
	    $main::debug > 1 and main::lm("no response for $query","dns");
	    $response=undef;
	};
	$main::select->unregister($socket);
	$socket->close();
	defined($response) and $cache->set($query,$response);
	&$next($response);
    },10);
    return $socket;
};

sub ip_to_name_next($ip,$next){
    # effect: runs next with name for ip
    #         if no name was found, use ''
    #         if no reply received, use unsef

    return dns_lookup($ip,sub{
	my $response=shift();
	$response or return &$next(undef);
	my @answer=grep {$_->isa("Net::DNS::RR::PTR")} $response->answer();
	@answer or return &$next('');
	my $name=$answer[0]->ptrdname();
	$name=~s/\.$//;
	&$next($name);
    });
};

sub name_to_ips_next($name,$next){
    # effect: runs next with ip addresses for name (arrayref, possibly empty)
    #         if no reply received, use unsef

    return dns_lookup($name,sub{
	my $response=shift();
	$response or return &$next(undef);
	my @answer=$response->answer();
	my $ips=[
	    map{
		$_->address()
	    } grep {
		$answer[0]->isa("Net::DNS::RR::A")
	    } @answer];
	&$next($ips);
    });
};

sub verified_domain_next($ip,$next){
    # effect: runs next with domain for ip, or ip. domain is used if
    #         forward and reverse matches, and ip is not dynamic
    #         if no reply received, use unsef

    is_dynamic_next($ip,sub{
	# dynamic addresses alway counted by itself, with no domain reputation
	my $res=shift();
	$res and return &$next($ip);
	
	ip_to_name_next($ip,sub{
	    # resolves name
	    my $name=shift();
	    defined($name) or return &$next(undef);
	    $name eq '' and return &$next($ip);

	    # uses domain if IP matches
	    name_to_ips_next($name,sub{
		my $ips=shift();
		defined($ips) or return &$next(undef);
		grep {$_ eq $ip} @$ips or return &$next($ip);
		my $root=$suffix_parser->get_root_domain($name);
		$root or return &$next($ip);
		return &$next($root);
	   });
       });
    });
};

# -- blacklist resolution --

sub bl_lookup_next($ip,$bl,$next){
    # effect: runs next with ip looked up i bl (arrayref, possibly empty)
    #         if no reply received, use unsef

    if($ip=~/^(?:10\.|172.(?:16|17|17|19|2?|30|31)|192\.168\.|127\.)/){
	$main::debug > 1 and main::lm("no dnsbl lookup for private address $ip","dns");
	return &$next([]);
    };
    
    my $ip_r=ip_reverse($ip);
    $ip_r or return &$next(undef);
    return name_to_ips_next($ip_r.'.'.$bl,$next);
};

sub is_dynamic_next($ip,$next){
    # effect: checks if ip is dynamic, runs next with result
    #         if no reply could be determined, use undef

    my $done={};

    # run both lookups concurrently
    ip_to_name_next($ip,sub{
	my $name=shift();
	if(defined($name)){
	    if($name eq ''){
		$done->{name}=1;
	    }
	    else{
		$done->{name}=($name=~/\b(?:host|cust|customers?|dyn|dynamic|static|bredband|broadband|dhcp|dialup|a?dsl)\b/ and !$name=~/\b(?:smtp|mail)\b/ and $name=~/\d+\D+\d+/);
	    };
	}
	else{
	    $done->{name}=undef;
	};
	is_dynamic_if_ready($done,$next);
    });
    bl_lookup_next($ip,'dul.dnsbl.sorbs.net',sub{
	my $res=shift();
	$done->{dul}=(defined($res) ? scalar @$res : undef);
	is_dynamic_if_ready($done,$next);
    });
};

sub is_dynamic_if_ready($done,$next){
    # effect: runs next with result from done

    if(exists($done->{name}) and exists($done->{dul})){
	if($done->{name} or $done->{dul}){
	    return &$next(1);
	};
	if(defined($done->{name}) and defined($done->{dul})){
	    return &$next(0);
	};
	return &$next(undef);
    };
};

sub dnswl_score_next($ip,$next){
    # effect: checks dnswl score for ip, run next with result
    #         if no reply received, use undef

    bl_lookup_next(
	$ip,'list.dnswl.org',sub{
	    my $res=shift();
	    defined($res) or return &$next(undef);
	    scalar @$res or return &$next(0);

	    if($res->[0]=~/127.\d+\.\d+\.(\d+)/){
		return &$next($1);
	    }
	    else{
		main::lm("DNSWL returned strange answer ($res->[0])","dns","warning");
		return &$next(undef);
	    };
	});
};

# ---- package init ----

$suffix_parser=Domain::PublicSuffix->new({
    'data_file' => "_DATADIR_/public_suffix_list.dat"
    });
$resolver=Net::DNS::Resolver->new();
return 1;


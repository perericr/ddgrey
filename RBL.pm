# ---- package RBL ---
# functions for DNS based blocklists

package DDgrey::RBL;

use strict;
use integer;

use Cache::MemoryCache;
use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;
use DDgrey::DNS;
use Socket;

use parent qw(Exporter);

our @EXPORT_OK=qw(rbls);

# ---- RBL:s ----

our @current_rbls;
our @default_rbl_names=qw(spamcop sorbs uce-2);

our @RBLS=(
    {name=>'uce-2',title=>'Uceprotect level 2',zone=>'dnsbl-2.uceprotect.net',score=>-50,ipv6=>0},
    {name=>'uce-3',title=>'Uceprotect level 3',zone=>'dnsbl-3.uceprotect.net',score=>-50,ipv6=>0},
    {name=>'backscatter',title=>'Backscatter',zone=>'ips.backscatterer.org',score=>-50,ipv6=>0,false=>20},
    {name=>'barracuda',title=>'Barracuda',zone=>'b.barracudacentral.org',score=>-80,ipv6=>0,false=>20},
    {name=>'spamhaus',title=>'Spamhaus ZEN',zone=>'zen.spamhaus.org',score=>-100,ipv6=>0},
    {name=>'spamcop',title=>'Spamcop',zone=>'bl.spamcop.net',score=>-80,ipv6=>0,false=>20},
    {name=>'sorbs',title=>'SORBS',score=>-10,zone=>'dnsbl.sorbs.net',ipv6=>0,filter=>sub{shift() ne '127.0.0.10'},false=>20},
);

# ---- functions for lookup ----

sub rbls(){
    # return: RBLs to use as list
    return @current_rbls;
};

sub bl_lookup_next($ip,$bl_zone,$next){
    # effect: runs next with ip looked up i bl (arrayref, possibly empty)
    #         if no reply received, use unsef

    if($ip=~/^(?:10\.|172.(?:16|17|17|19|2?|30|31)|192\.168\.|127\.)/){
       $main::debug > 1 and main::lm("no dnsbl lookup for private address $ip","dns");
       return &$next([]);
    };
    
    my $ip_r=DDgrey::DNS::ip_reverse($ip);
    $ip_r or return &$next(undef);
    DDgrey::DNS::name_to_ips_next($ip_r.'.'.$bl_zone,$next);
};

sub rbl_lookup_next($rbl,$ip,$next){
    # effect: runs next with ip looked up by rbl. results passed as arrayref
    #         if no reply received, use undef

    bl_lookup_next($ip,$rbl->{zone},sub{rbl_lookup_done($rbl,shift(),$next)});
};

sub rbl_lookup_done($rbl,$ips,$next){
    # effect: run next with results of RBL lookup with rbl based on ips

    my @ips=@$ips;
    if($rbl->{filter}){
	@ips=grep {&{$rbl->{filter}}($_)} @ips;
    };
    &$next([@ips]);
};

sub verified_domain_next($ip,$next){
    # effect: runs next with domain for ip, or ip. domain is used if
    #         forward and reverse matches, and ip is not dynamic
    #         if no reply received, use unsef

    is_dynamic_next($ip,sub{
	# dynamic addresses alway counted by itself, with no domain reputation
	my $res=shift();
	$res and return &$next($ip);
	
	DDgrey::DNS::ip_to_name_next($ip,sub{
	    # resolves name
	    my $name=shift();
	    defined($name) or return &$next(undef);
	    $name eq '' and return &$next($ip);

	    # uses domain if IP matches
	    DDgrey::DNS::name_to_ips_next($name,sub{
		my $ips=shift();
		defined($ips) or return &$next(undef);
		grep {$_ eq $ip} @$ips or return &$next($ip);
		my $root=$DDgrey::DNS::suffix_parser->get_root_domain($name);
		$root or return &$next($ip);
		return &$next($root);
	   });
       });
    });
};

sub is_dynamic_next($ip,$next){
    # effect: checks if ip is dynamic, runs next with result
    #         if no reply could be determined, use undef

    my $done={};

    # run both lookups concurrently
    DDgrey::DNS::ip_to_name_next($ip,sub{
	my $name=shift();
	if(defined($name)){
	    if($name eq ''){
		$done->{name}=1;
	    }
	    else{
		$done->{name}=($name=~/\b(?:host|cust|customers?|priv|private|dyn|dynamic|static|bredband|broadband|dhcp|dialup|a?dsl)\b/ and !$name=~/\b(?:smtp|mail)\b/ and $name=~/\d+\D+\d+/);
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

# set up current RBLs
push @main::on_done,sub{
    my $rbls={};
    for my $rbl (@RBLS){
	$rbls->{$rbl->{name}}=$rbl;
    };
    
    my $names=$main::config->{rbls} // [@default_rbl_names];

    for my $name (@$names){
       defined(my $rbl=$rbls->{$name}) or main::error("unkown RBL $name");
       push @current_rbls,$rbl;
    };
};

return 1;

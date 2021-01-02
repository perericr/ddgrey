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

our @EXPORT_OK=qw(resolved suffix_parser);

our $resolver;
our $suffix_parser;

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
	$main::debug > 1 and main::lm("could not initiate query $query","dns");
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

# ---- package init ----

# initiate suffix database
$suffix_parser=Domain::PublicSuffix->new({
    'data_file' => "_DATADIR_/public_suffix_list.dat"
});

# initiate resolver
$resolver=Net::DNS::Resolver->new();

return 1;


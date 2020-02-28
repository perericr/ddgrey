# ---- class Report ----
# repport

package DDgrey::Report;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

use DDgrey::DBStore qw($db);

use parent qw(DDgrey::DBModel);

# values for på event:
# check      check done by MTB (used for individual per-triplet greylisting)
# disconnect host closed connection to MTA
# hard_trap  email sent to hard spam trap
# soft_trap  email sent to soft spam trap
# manual     manual spam report
# unknown    attempt at sending to unknown recipient   
# relay      attempt at relay usage
# spam       spam received
# ok         mail delivered by MTA to recipient    

# description
our $table='report';
our @fields=('id integer primary key autoincrement','origin text','origin_id integer','reporter text','time integer','stored integer','ip text','domain text','event text','e_from text','e_to text','mta_id text');
our %indexes=(
    'id'=>['id'],
    'time'=>['time'],
    'stored'=>['stored'],
    'ip'=>['ip','event','time'],
    'domain'=>['domain','event','time'],
    );

# ---- class methods for overview (does not return instance) ----

sub list($class,$from){
    # return: overview of reports since from (timestamp)
    #         format att raw data, not class instances

    return $db->query_all("select id,origin,origin_id,stored from report where stored >= ? order by stored asc",$from);
};

sub count_grouped($class,$ip,$event,$fdate,$tdate){
    # return: number of hits for event from ip between fdate-tdate
    #         grouped by e_from and e_to
    
    return $db->query_first_one('select count(*) from (select * from report where ip=? and event=? and time >= ? and time <= ? group by e_from,e_to)',$ip,$event,$fdate,$tdate);
};

sub domain_count($class,$domain,$event,$fdate,$tdate){
    # return: number of hits for event from domain between fdate-tdate

    return $db->query_first_one('select count(id) from report where domain=? and event=? and time >= ? and time <= ?',$domain,$event,$fdate,$tdate);
};

sub domain_check($class,$domain,$from,$to,$fdate,$tdate){
    # return: whether check has been done for domain and email from,to
    #         between fdate-tdate
    
    my $self=$db->query_first('select * from report where domain=? and event=? and e_from=? and e_to=? and time >= ? and time <= ?',$domain,'check',$from,$to,$fdate,$tdate);
    $self or return undef;
    bless($self,$class);
    return $self;
};

# ---- class methods for searching (returns class instances) ----

sub find($class,$ip,$event,$fdate,$tdate){
    # return: possible hits for event from IP between fdate-tdate

    return map {
	bless($_,$class);
    } $db->query_all('select * from report where ip=? and event=? and time >= ? and time <= ?',$ip,$event,$fdate,$tdate);
};

sub find_ok($class,$ip,$mta_id){
    # return: possible hits for 'OK' event from IP, mtda_id between fdate-tdate

    return map {
	bless($_,$class);
    } $db->query_all('select * from report where event=? and ip=? and mta_id=?','ok',$ip,$mta_id);
};

sub get($class,$id){
    # return: possible report with local id id

    my $data=$db->query_first("select * from report where id=?",$id);
    $data or return undef;
    return DDgrey::Report->new($data);
};

# ---- constructor ----

sub new($class,$proto){
    # return: new report from proto
    # effect: may raise exception

    my $self=$proto;
    defined($self->{time}) or $self->{time}=time();
    defined($self->{origin}) or $self->{origin}=$main::hostname;
    return bless($self,$class);
};

sub from_text($class,$text){
    # return: new report from text (without id field)
    # effect: may raise exception

        my $keys={
	'origin'=>'^[\w\-\.]+$',
	'origin_id'=>'^\d+$',
	'reporter'=>'^[\w\-\.]+$',
	'time'=>'^\d+$',
	'ip'=>'^[\d\.]+$',
	'domain'=>'^\S+$',
	'event'=>'^.+$',
	'e_from'=>'^.+$',
	'e_to'=>'^.+$',
	'mta_id'=>'^\S+$',
	'stored'=>'^\d+$',
    };
    my $req={
	'origin'=>0,
	'origin_id'=>0,
	'reporter'=>1,
	'time'=>1,
	'ip'=>1,
	'domain'=>0,
	'event'=>1,
	'e_from'=>0,
	'e_to'=>0,
	'mta_id'=>0,
	'stored'=>0,
    };
    my $number={
	'origin_id'=>1,
	'time'=>1,
	'stored'=>1,
    };

    # interpret
    my $self={};
    my @rows=split(/[\r\n]+/,$text);
    foreach my $row (@rows){
	$row=~/^(\w+)\:(.*)$/ or die "bad row format\n";
	defined($keys->{$1}) or next;
	$self->{$1}=$2 ? $2 : undef;
    };

    # validate values
    foreach my $key (keys %$keys){
	exists($self->{$key}) or die "missing field $key\n";
	if(defined($self->{$key})){
	    my $re=$keys->{$key};
	    $self->{$key}=~/$re/ or die "format error in field $key\n";
	    $number->{$key} and $self->{$key}+=0;
	}
	else{
	    $req->{$key} and die "empty required field $key\n";
	};
    };

    return bless($self,$class);
};

# ---- class methods for changing ----

sub resolve_unresolved($class){
    # effect: tries to set DNS-name for reports missing such
    
    $main::debug and main::lm("running resolve_unresolved","report");
    $db->query('delete from report where origin IS NULL or origin_id IS NULL');
    for my $report (map {bless($_,$class)} $db->query_all('select * from report where domain IS NULL ORDER BY random() LIMIT 20')){
	if($main::select->load()){
	    $main::debug and main::lm("quitting resolve_unresolved due to query load","report");
	    last;
	};
	$report->resolve(
	    sub{
		my $domain=shift();
		$domain and $report->save();
	    });
    };
};

# ---- methods for access ----

sub unicode($self){
    # return: self as human readable one-line string
    
    my @r=();
    if(defined($self->{origin}) and defined($self->{origin_id})){
	push @r,$self->{origin};
	push @r,$self->{origin_id}.":";
    };
    push @r,$self->{reporter};
    push @r,$self->{event};
    push @r,$self->{time};
    return join(' ',@r);
};

sub duplicate($self){
    # return: possible duplicate of self in database
    # pre  : self has no id value, and is not stored in database

    my @where=('origin=?','ip=?','event=?','time=?');
    my @args=($self->{origin},$self->{ip},$self->{event},$self->{time});

    # some events (like check) are allowed to store seemingly similiar of,
    # because several similiar checks can be done at the same second
    my @extra_keys=qw(reporter mta_id e_from e_to);
    if($self->{unique_event}){
	push @extra_keys,'origin','origin_id';
    };
    
    for my $key (@extra_keys){
	if(defined($self->{$key})){
	    push @where,"$key=?";
	    push @args,$self->{$key};
	}
	else{
	    push @where,"$key IS NULL";
	};
    };
    
    my $dup=$db->query_first('select * from report where '.join(' AND ',@where),@args);
    $dup or return undef;
    bless($dup,ref($self));
    return $dup;
};

# ---- methods for changing ----

sub resolve($self,$next){
    # effect: sets value for domain from DNS, runs next on success

    DDgrey::DNS::verified_domain_next(
	$self->{ip},
	sub{
	    my $domain=shift();
	    defined($domain) and $self->{domain}=$domain;
	    &$next($domain);
	}
    );
};

sub save($self){
    # effect: saves

    $self->{stored}=time();
    $self->SUPER::save();

    $db->query('begin transaction');
    if(!defined($self->{origin_id}) and $self->{origin} eq $main::hostname){
	$self->{origin_id}=$self->{id};
	$db->query('update '.$self->get_table().' set origin_id=? where id=?',$self->{origin_id},$self->{id});
    };
    $db->query('commit');
};

# ---- package init ----

# start resulution of domains one every minute
push @main::on_done,sub{
    __PACKAGE__->resolve_unresolved();
    $main::select->register_interval(
	60,
	sub{
	    __PACKAGE__->resolve_unresolved();
	}
    );
};

# register model
DDgrey::DBStore::register_model(__PACKAGE__);

return 1;

# ---- class Report ----
# class för rapport

package DDgrey::Report;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

use DDgrey::DBStore qw($db);

use parent qw(DDgrey::DBModel);

# värden på event:
# check      koll gjord av MTA
# disconnect värd avbyt förbindelse mot protokoll
# hard_trap  e-post till hård spamfälla
# soft_trap  e-post till mjuk spamfälla
# manual     manuell spamrapport
# unknown    försök att skicka till okänd mottagare   
# relay      försök att använda som relä
# spam       spam mottaget
# ok         levererat av MTA till mottagare    

# beskrivning
our $table='report';
our @fields=('id integer primary key autoincrement','origin text','origin_id integer','reporter text','time integer','stored integer','ip text','domain text','event text','e_from text','e_to text','mta_id text');

# ---- klassmetoder för översikt (ger ej objekt) ----

sub list($class,$from){
    # retur: översikt över rapport registrerade från och med from (timestamp)
    #        ej som rapport-objekt

    return $db->query_all("select id,origin,origin_id,stored from report where stored >= ? order by stored asc",$from);
};

sub count_grouped($class,$ip,$event,$fdate,$tdate){
    # retur: antal träffar av event för ip från tid, grupperade på e_from, e_to
    return $db->query_first_one('select count(*) from (select * from report where ip=? and event=? and time >= ? and time <= ? group by e_from,e_to)',$ip,$event,$fdate,$tdate);
};

sub domain_count($class,$domain,$event,$fdate,$tdate){
    # retur: antal träffar av event för domain mellan fdate och tdate
    return $db->query_first_one('select count(id) from report where domain=? and event=? and time >= ? and time <= ?',$domain,$event,$fdate,$tdate);
};

sub domain_check($class,$domain,$from,$to,$fdate,$tdate){
    # retur: huruvida check gjort från domain, from, to mellan fdate och tdate
    my $self=$db->query_first('select * from report where domain=? and event=? and e_from=? and e_to=? and time >= ? and time <= ?',$domain,'check',$from,$to,$fdate,$tdate);
    $self or return undef;
    bless($self,$class);
    return $self;
};

# ---- klassmetoder för sökning (ger Report-objekt) ----

sub find($class,$ip,$event,$fdate,$tdate){
    # retur: ev träffar av event för ip från tid
    return map {
	bless($_,$class);
    } $db->query_all('select * from report where ip=? and event=? and time >= ? and time <= ?',$ip,$event,$fdate,$tdate);
};

sub find_ok($class,$ip,$mta_id){
    # retur: ev träffar av event för ip och mta_id
    return map {
	bless($_,$class);
    } $db->query_all('select * from report where event=? and ip=? and mta_id=?','ok',$ip,$mta_id);
};

sub get($class,$id){
    # retur: ev rapport med lokalt id (form "id")

    my $data=$db->query_first("select * from report where id=?",$id);
    $data or return undef;
    return DDgrey::Report->new($data);
};

# ---- konstruktor ----

sub new($class,$proto){
    # retur: ny rapport från proto
    # effekt: kan sätta undantag

    my $self=$proto;
    defined($self->{time}) or $self->{time}=time();
    defined($self->{origin}) or $self->{origin}=$main::hostname;
    return bless($self,$class);
};

sub from_text($class,$text){
    # retur : ny rapport från text (utan id-fält)
    # effekt: kan sätta undantag

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

    # tolka
    my $self={};
    my @rows=split(/[\r\n]+/,$text);
    foreach my $row (@rows){
	$row=~/^(\w+)\:(.*)$/ or die "bad row format\n";
	defined($keys->{$1}) or next;
	$self->{$1}=$2 ? $2 : undef;
    };

    # granska värden till new
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

# ---- klassmetoder för ändring ----

sub resolve_unresolved($class){
    # effekt: försöker sätta DNS-namn för poster som saknar sådant
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

# ---- metoder för åtkomst ----

sub unicode($self){
    # retur: self som läsbar enraders sträng

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
    # retur: ev kopia i databas som kommer från samma källa
    # pre  : self saknas id och är inte i databas

    my @where=('origin=?','ip=?','event=?','time=?');
    my @args=($self->{origin},$self->{ip},$self->{event},$self->{time});

    # vissa händelser (till exempel check) är OK att ha synbart lika
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

# ---- metoder för ändring ----

sub resolve($self,$next){
    # effekt: sätter värde domain, kör next

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
    # effekt: sparar

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

# slår upp kvarstående namn en gång i minuten
push @main::on_done,sub{
    __PACKAGE__->resolve_unresolved();
    $main::select->register_interval(
	60,
	sub{
	    __PACKAGE__->resolve_unresolved();
	}
    );
};

# registrera modell
DDgrey::DBStore::register_model(__PACKAGE__);

return 1;

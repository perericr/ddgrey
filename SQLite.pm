# ---- klass DB::SQLite ----
# klass för Sqlite-databas

package DDgrey::DB::SQLite;

use strict;
use integer;

use Carp;
use DBI;
use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

our @CARP_NOT=qw(DDgrey::DB::SQLite);

# ---- konstruktor ----

sub new($class){
    # retur : ny sqlite-databasanslutning
    # effekt: kan sätta undantag

    my $self={};
    bless($self,$class);

    # anslut
    my $file=($main::dir // "_DATADIR_")."/ddgrey.sqlite";
    my $dsn="DBI:SQLite:dbname=$file";
    my $dbh=DBI->connect($dsn,{RaiseError=>1,AutoCommit=>1});
    defined($dbh) or main::error("can't connect to database ($!)");
    $< or chown($main::uid,$main::gid,$file);
    $self->{dbh}=$dbh;

    return $self;
};

# ---- metoder ----

sub query_all($self){
    my $st=$self->query(@_);
    my $data=$st->fetchall_arrayref({});
    $st->finish();
    return @$data;
};

sub query_all_one($self){
    my $st=$self->query(@_);
    my $data=$st->fetchall_arrayref([]);
    $st->finish();
    return map {$_->[0]} @$data;
};

sub query_first($self){
    my $st=$self->query(@_);
    my $data=$st->fetchrow_hashref();
    $st->finish();
    return $data;
};

sub query_first_one($self){
    my $st=$self->query(@_);
    my $data=$st->fetchrow_array();
    $st->finish();
    return $data;
};

sub query($self,$query){
    # effekt: kör query med varargs
    # retur : statement-handtag för query

    my @arg=@_;
    
    local $SIG{__DIE__}=sub{$_=shift;chomp;croak $_};
    local $SIG{__WARN__}=sub{$_=shift;chomp;croak $_};
    
    if(!defined($self->{sth}->{$query})){
	$self->{sth}->{$query}=$self->{dbh}->prepare($query);
    };

    $self->{sth}->{$query}->execute(@arg);
    
    return $self->{sth}->{$query};    
};

sub insert_id($self){
    # retur: insert_id för senaste insert
    return $self->{dbh}->last_insert_id("","","","");
};

sub close($self){
    # effekt: stänger anslutning
    $self->{dbh}->disconnect();
};

# ---- init av paket ----
return 1;

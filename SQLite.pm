# ---- class DB::SQLite ----
# SQLite database

package DDgrey::DB::SQLite;

use strict;
use integer;

use Carp;
use DBI;
use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

our @CARP_NOT=qw(DDgrey::DB::SQLite);

# ---- constructor ----

sub new($class){
    # return: new SQLite database connection
    # effect: may raise exception

    my $self={};
    bless($self,$class);

    # connect
    my $file=($main::dir // "_DATADIR_")."/ddgrey.sqlite";
    my $dsn="DBI:SQLite:dbname=$file";
    my $dbh=DBI->connect($dsn,{RaiseError=>1,AutoCommit=>1});
    defined($dbh) or main::error("can't connect to database ($!)");
    $< or chown($main::uid,$main::gid,$file);
    $self->{dbh}=$dbh;

    return $self;
};

# ---- methods ----

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
    # effect: runs query with varargs
    # return: statement handle for query

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
    # return: insert_id for latest insert
    return $self->{dbh}->last_insert_id("","","","");
};

sub close($self){
    # effect: closes connection
    $self->{dbh}->disconnect();
};

# ---- package init ----
return 1;

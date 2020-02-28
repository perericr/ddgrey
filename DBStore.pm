# ---- class DBStore ----
# base class for SQL-based data store

package DDgrey::DBStore;

use strict;
use integer;

use DBI;
use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

use DDgrey::DB::SQLite;

use parent qw(Exporter);

our @EXPORT_OK=qw($store $db);

our $store;
our $db;

# virtual package - no direct instances

# ---- models register ----

our @models=();

sub register_model($model){
    if(defined($db)){
	# run code directly
	$model->ensure_tables();
    }
    else{
	# save until DB is ready
	push @models,$model;
    };
};

# ---- class methods ----

# ---- constructor ----

sub init($class){
    # return: new DB-based storage
    # effect: may raise exception

    defined($store) and return $store;

    my $self={};
    bless($self,$class);
    $self->{db}=DDgrey::DB::SQLite->new();
    
    $store=$self;
    $db=$self->{db};

    # ensure tables
    for my $cl (@models){
	$cl->ensure_tables();
    };
    
    return $self;
};

sub close($self){
    # effect: closes connection
    $self->{db}->close();
};

# ---- package init ----
return 1;

# ---- klass DBStore ----
# klass för SQL-lagring av uppgifter

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

# ---- register över modeller ----

our @models=();

sub register_model($model){
    if(defined($db)){
	# kör kod direkt
	$model->ensure_tables();
    }
    else{
	# sparar tills databas är igång
	push @models,$model;
    };
};

# ---- klassmetoder ----

# ---- konstruktor ----

sub init($class){
    # retur : ny DB-baserad lagring
    # effekt: kan sätta undantag

    defined($store) and return $store;

    my $self={};
    bless($self,$class);
    $self->{db}=DDgrey::DB::SQLite->new();
    
    $store=$self;
    $db=$self->{db};

    # säkerställ tabeller
    for my $cl (@models){
	$cl->ensure_tables();
    };
    
    return $self;
};

sub close($self){
    # effekt: stänger anslutning
    $self->{db}->close();
};

# ---- init av paket ----
return 1;

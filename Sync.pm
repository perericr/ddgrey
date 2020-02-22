# ---- class Sync ----
# class for remote server last sync notes

package DDgrey::Sync;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

use DDgrey::DBStore qw($db);

use parent qw(DDgrey::DBModel);

# beskrivning
our $table='sync';
our @fields=('id integer primary key autoincrement','name text','last integer');
our %indexes=(
    'id'=>['id'],
    'name'=>['name'],
    );


# ---- klassmetoder för översikt (ger ej objekt) ----

sub last_fetched($class,$name){
    # retur: senast hämtade uppgift från server name, om någon
    return $db->query_first_one("select last from sync where name=?",$name);
};

# ---- klassmetoder för ändring ----

sub update_fetched($class,$name,$time){
    # effekt: sätter senast-hämtade uppgift för server name time
    
    my $self=($db->query_first("select * from sync where name=?",$name) // {name=>$name});
    bless($self,$class);
    if($time > $self->{last} // 0){
	$self->{last}=$time;
    };
    $self->save();
};

# ---- package init ----

# registrera modell
DDgrey::DBStore::register_model(__PACKAGE__);

return 1;

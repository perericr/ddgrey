# ---- class Sync ----
# remote server last sync notes

package DDgrey::Sync;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

use DDgrey::DBStore qw($db);

use parent qw(DDgrey::DBModel);

# description
our $table='sync';
our @fields=('id integer primary key autoincrement','name text','last integer');
our %indexes=(
    'id'=>['id'],
    'name'=>['name'],
    );

# ---- class methods for overview (no instances returned) ----

sub last_fetched($class,$name){
    # return: last fetched report from server name, if any
    return $db->query_first_one("select last from sync where name=?",$name);
};

# ---- class methods for changing ----

sub update_fetched($class,$name,$time){
    # effect: sets last-changed for server name to time
    
    my $self=($db->query_first("select * from sync where name=?",$name) // {name=>$name});
    bless($self,$class);
    if($time > $self->{last} // 0){
	$self->{last}=$time;
    };
    $self->save();
};

# ---- package init ----

# register modell
DDgrey::DBStore::register_model(__PACKAGE__);

return 1;

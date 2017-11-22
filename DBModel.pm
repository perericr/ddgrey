# ---- class DBModel ----
# base class for database based models

package DDgrey::DBModel;

use strict;
use integer;

use DDgrey::DBStore qw($db);
use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

# ---- klassmetoder ----

sub get_table($class){
    $class=ref($class)||$class;
    no strict 'refs';
    return ${$class.'::table'};
};

sub ensure_tables($class){
    # effekt: ser till att databas innehåller rätt tabeller
    $class=ref($class)||$class;
    no strict 'refs';
    $db->query('create table if not exists '.${$class.'::table'}.' ('.join(',',@{$class.'::fields'}).')');
};

sub get_fields($class){
    # retur: fältnamn att använda i db
    $class=ref($class)||$class;
    no strict 'refs';
    my @res=();
    for my $f (@{$class.'::fields'}){
	push @res,$f=~s/^(\w+).*/$1/r;
    };
    return @res;
};

# ---- metoder för åtkomst ----

sub as_text($self){
    # retur: self i textformat

    my $r='';
    foreach my $key ($self->get_fields()){
	$r.=$key.":".(defined($self->{$key}) ? $self->{$key} : '')."\r\n";
    };
    return $r;
};

# ---- metoder för ändring ----

sub save($self){
    # effekt: sparar policy
    my @fields=grep {$_ ne 'id'} $self->get_fields();
    if(defined($self->{id})){
	$db->query('update '.$self->get_table().' set '.join(',',map {'"'.$_.'"=?'} @fields).' where id=?',(map {$self->{$_}} @fields),$self->{id});
    }
    else{
	$db->query('insert into '.$self->get_table().' ('.join(',',map {'"'.$_.'"'} @fields).') VALUES ('.join(',',map {'?'} @fields).')',map {$self->{$_}} @fields);
	$self->{id}=$db->insert_id();
    };
};

# ---- init av paket ----
return 1;

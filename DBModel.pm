# ---- class DBModel ----
# base class for database based models

package DDgrey::DBModel;

use strict;
use integer;

use DDgrey::DBStore qw($db);
use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

# variables to override if needed
our $indexes={};

# ---- class methods ----

sub get_table($class){
    # return: table name for cass
    
    $class=ref($class)||$class;
    no strict 'refs';
    return ${$class.'::table'};
};

sub ensure_tables($class){
    # effect: ensures that database contains the correct tables and indexes
    # pre   : database may only contain correct table or no table for class
    
    $class=ref($class)||$class;
    no strict 'refs';

    $main::debug and main::lm("checking tables and index for $class");
    
    # ensures table
    $db->query('create table if not exists '.${$class.'::table'}.' ('.join(',',@{$class.'::fields'}).')');

    # ensures possible indexes
    my %indexes=%{$class.'::indexes'};
    for my $name (keys %indexes){
	$db->query('create index if not exists '.$name.' on '.${$class.'::table'}.' ('.join(',',@{$indexes{$name}}).')');
	
    };
};

sub get_fields($class){
    # return: field names to use in DB
    $class=ref($class)||$class;
    no strict 'refs';
    my @res=();
    for my $f (@{$class.'::fields'}){
	push @res,$f=~s/^(\w+).*/$1/r;
    };
    return @res;
};

# ---- methods for access ----

sub as_text($self){
    # return: self as text

    my $r='';
    foreach my $key ($self->get_fields()){
	$r.=$key.":".(defined($self->{$key}) ? $self->{$key} : '')."\r\n";
    };
    return $r;
};

# ---- methods for changing ----

sub save($self){
    # effect: saves
    
    my @fields=grep {$_ ne 'id'} $self->get_fields();
    if(defined($self->{id})){
	$db->query('update '.$self->get_table().' set '.join(',',map {'"'.$_.'"=?'} @fields).' where id=?',(map {$self->{$_}} @fields),$self->{id});
    }
    else{
	$db->query('insert into '.$self->get_table().' ('.join(',',map {'"'.$_.'"'} @fields).') VALUES ('.join(',',map {'?'} @fields).')',map {$self->{$_}} @fields);
	$self->{id}=$db->insert_id();
    };
};

# ---- package init ----
return 1;

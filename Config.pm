# ---- klass Config ----
# configuration

package DDgrey::Config;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;
use Text::Balanced;

sub new($class,$name;$opt){
    # return: new configuration from name, possible parsing instructions in opt
    # effect: may raise exception if error in configuration

    my $file=($main::dir // "_CONFIGDIR_")."/$name";
    open FILE,$file or main::error("can't open $file ($!)");
    my $rows=[<FILE>];
    close FILE;

    # -- instructions for parsing --
    
    # list of commands
    my $allowed={};
    if(defined($opt->{commands})){
	foreach my $key (@{$opt->{commands}}){
	    $allowed->{$key}=1;
	};
    };
    
    # list of commands, several of same allowed
    my $multiple={};
    if(defined($opt->{multiple})){
	foreach my $key (@{$opt->{multiple}}){
	    $multiple->{$key}=1;
	    $allowed->{$key}=1;
	};
    };
    # lista of complex commands
    my $complex={};
    if(defined($opt->{complex})){
	foreach my $key (@{$opt->{complex}}){
 	    $complex->{$key}=1;
	    $allowed->{$key}=1;
	};
    };

    # -- parsing --

    my $commands=[];
    my $count=0;  # row number
    
    foreach my $row (@$rows){
	$count++;

	# parse row
	my $line=row_lex($row,$count,1) or next;
	
	# parse arguments
	if($complex->{$line->{symbols}->[0]}){
	    # complex row
	    my $item=line_parse($line);
	    my $key=shift(@{$item->{arg}});
	    # merge
	    if(defined($opt->{merge}->{$key})){
		# keep original as property
		$item->{'command'}=$key;
		$key=$opt->{merge}->{$key};
	    };
	    push(@$commands,[$key,$item]);
	}
	else{
	    # basic row
	    my $key=shift(@{$line->{symbols}});
	    grep {$_ eq '='} @{$line->{symbols}} and main::error("key-value data not allowed for $key on line $line->{nr}");
	    for my $symbol (@{$line->{symbols}}){
		push(@$commands,[$key,$symbol]);
	    };
	};
    };
	
    # -- add commands to configuration --
    my $self={};
    foreach my $command (@$commands){
	my($key,$value)=@$command;
	defined($allowed->{$key}) or main::error("unknown key \"$key\" in $name"); 
	# add row
	if($multiple->{$key}){
	    # add array if multiple
	    push @{$self->{$key}},$value;
	}
	else{
	    # otherwise, replace
	    $self->{$key}=$value;
	};
    };
	
    return bless($self,$class);
};

# ---- functions ----

sub row_lex($row,$count,$allow_assign){
    # return: row split in symbols, with id count (for error messages)
    # effect: may raise exception

    # skip empty rows
    $row=~/^\s*(?:$|\#)/ and return undef;

    # remove trailing space
    $row=~s/\s*$//;
    
    my $symbols=[];
    while(1){
	my($extracted,$remainder)=Text::Balanced::extract_delimited($row);
	if($extracted){
	    $extracted=~s/^.(.*?).$/$1/;
	}
	elsif($allow_assign and $row=~/^\s*(\=)(.*)/){
	    $extracted=$1;
	    $remainder=$2;
	}
	elsif($allow_assign and $row=~/^\s*(\S+?)((?:$|\=|\s).*)/){
	    $extracted=$1;
	    $remainder=$2;
	}
	elsif(!$allow_assign and $row=~/^\s*(\S+?)((?:$|\s).*)/){
	    $extracted=$1;
	    $remainder=$2;
	}
	else{
	    $extracted='';
	    $remainder='';
	};
	$row=$remainder;
	push @$symbols,$extracted;
	if($remainder ne '' and $extracted eq ''){
	    main::error("parsing error on line $count");
	};
	$remainder eq '' and last;
    };

    return {nr=>$count,symbols=>$symbols};
};

sub line_parse($line){
    # return: parsing of line to arguments and key-value pairs
    # effect: may raise exception

    my $item={};
    my $count=$line->{nr};
    my $symbols=$line->{symbols};

    # arguments
    while(scalar @$symbols){
	if(defined($symbols->[1]) and $symbols->[1] eq '='){
	    if(!defined($symbols->[2])){
		main::error("assigment without value on line $count");
	    };
	    my($key,undef,$value)=splice(@$symbols,0,3);
	    $item->{$key}=$value;
	}
	else{
	    push @{$item->{arg}},shift(@$symbols);
	};
    };

    return $item;
};

# ---- package init ----
return 1;

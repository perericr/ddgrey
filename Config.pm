# ---- klass Config ----
# klass för konfiguration

package DDgrey::Config;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;
use Text::Balanced;

sub new($class,$name;$opt){
    # retur : ny konfiguration från name, med ev tolkningsanvisningar opt
    # effekt: sätter undantag om fel i konfiguration

    my $file=($main::dir // "_CONFIGDIR_")."/$name";
    open FILE,$file or main::error("can't open $file ($!)");
    my $rows=[<FILE>];
    close FILE;

    # -- instruktioner för parsing --
    # lista över kommandon
    my $allowed={};
    if(defined($opt->{commands})){
	foreach my $key (@{$opt->{commands}}){
	    $allowed->{$key}=1;
	};
    };
    
    # lista över kommandon där flera kan finnas av samma sort
    my $multiple={};
    if(defined($opt->{multiple})){
	foreach my $key (@{$opt->{multiple}}){
	    $multiple->{$key}=1;
	    $allowed->{$key}=1;
	};
    };
    # lista över komplexa kommandon
    my $complex={};
    if(defined($opt->{complex})){
	foreach my $key (@{$opt->{complex}}){
 	    $complex->{$key}=1;
	    $allowed->{$key}=1;
	};
    };

    # -- parsing --

    my $commands=[];
    my $count=0;  # radnummer
    
    foreach my $row (@$rows){
	$count++;

	# tolka rad
	my $line=row_lex($row,$count,1) or next;
	
	# tolka argument
	if($complex->{$line->{symbols}->[0]}){
	    # komplex rad
	    my $item=line_parse($line);
	    my $key=shift(@{$item->{arg}});
	    # slå ihop med merge
	    if(defined($opt->{merge}->{$key})){
		# behåll ursprunglig som egenskap
		$item->{'command'}=$key;
		$key=$opt->{merge}->{$key};
	    };
	    push(@$commands,[$key,$item]);
	}
	else{
	    # enkel rad
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
	# lägg till rad
	if($multiple->{$key}){
	    # lägg till array om multiple
	    push @{$self->{$key}},$value;
	}
	else{
	    # ersätt i övriga fall
	    $self->{$key}=$value;
	};
    };
	
    return bless($self,$class);
};

# ---- funktioner ----

sub row_lex($row,$count,$allow_assign){
    # retur : row uppdelad i symboler, med id count (för felmeddelanden)
    # effekt: kan sätta undantag

    # skippa tomma rader
    $row=~/^\s*(?:$|\#)/ and return undef;

    # ta bort blankt på slutet
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
    # retur : tolkning av line till argument och nyckel-värdepar
    # effekt: kan sätta undantag

    my $item={};
    my $count=$line->{nr};
    my $symbols=$line->{symbols};

    # argument
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

# ---- init av paket ----
return 1;

# ---- klass Traps ----
# spam traps

package DDgrey::Traps;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;
use Socket;

use DDgrey::Config;

use parent qw(Exporter);

our @EXPORT_OK=qw($traps);

our $traps;
our $loaded={};

# ---- constructor ----

sub init($class){
    # return: new traps list
    # effect: may raise exception
    defined($traps) and return $traps;

    my $self={};
    bless($self,$class);
    $self->reload(0);
	
    $traps=$self;
    return $self;
};

# ---- methods ----

sub reload_if_changed($self,$missing_ok){
    # effekt: re-reads list of spamtraps if changed
    #         if missing_ok, a missing traps file will only result in a warning
    
    for my $f (@{$main::config->{traps}}){
	my @stat=stat($f);
	!defined($stat[9]) and !defined($loaded->{$f}) and next;
	if(
	    defined($stat[9]) and !defined($loaded->{$f}) or
	    !defined($stat[9]) and defined($loaded->{$f}) or
	    $stat[9] > $loaded->{$f}
	    ){
	    main::lm("reloading due to change in $f","traps");
	    return $self->reload($missing_ok);
	};
	
    };
};

sub reload($self,$missing_ok){
    # effect: re-reads list of spamtraps
    #         if missing_ok, a missing traps file will only result in a warning
    
    %{$self}=(); 
    for my $t (@{$main::config->{soft_trap}}){
	$self->{$t}='soft';
    };
    for my $t (@{$main::config->{hard_trap}}){
	$self->{$t}='hard';
    };
    # read from file
    for my $f (@{$main::config->{traps}}){
	$loaded->{$f}=time();
	main::lm("reading traps from $f","traps");
	if(!open F,$f){
	    $missing_ok or main::error("can't open file $f");
	    main::lm("can't open file $f","traps","warning");
	    $loaded->{$f}=undef;
	    return;
	};
	while(defined(my $in=<F>)){
	    chomp($in);
	    $in=~/^\s*(?:$|\#)/ and next;
	    if($in=~/^\s*(\S*)\s*\:\s*(hard|soft)\s*(?:$|\#)/){
		$self->{$1}=$2;
	    }
	    else{
		main::lm("unknown line in traps file ($in)","traps","warning");
	    };
	};
	close F;
    };
};

sub check($self,$ip,$from,$to){
    # effect: reports ip, from, to and report if mail is sent to spamtrap

    if(defined($self->{$to})){
	# log
	my $report=DDgrey::Report->new({
	    reporter=>'traps',
	    event=>$self->{$to}.'_trap',
	    'ip'=>$ip,
	    'e_from'=>$from,
	    'e_to'=>$to,
        });
	$main::debug > 1 and main::lm("sending report ".$report->unicode(),"traps");
	$main::dispatcher->report($report);
    };

};

# ---- package init ----

# re-read traps file one a minute
push @main::on_done,sub{
    __PACKAGE__->init();
    $main::select->register_interval(
	($main::debug ? 5 : 60),
	sub{
	    $traps->reload_if_changed(1);
	}
    );
};

return 1;



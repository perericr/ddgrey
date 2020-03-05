# ---- klass Run ----
# functions for logging and running

package DDgrey::Run;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;
use Encode qw(encode decode);
use Sys::Syslog;

use parent qw(Exporter);

our @EXPORT_OK=qw(lm error ensure_dir);
our $syslog_started=0;

# --- functions -----

sub ensure_dir($dir,$uid,$gid){
    # effect: ensures that dir exists
    if(!-d $dir){
	mkdir($dir) or error("can't create $dir ($!)");
    };
    if($< == 0){
	chown($uid,$gid,$dir);
    };
};

sub syslog_init($program){
    # effect: starts logging
    openlog($program,"cons,pid","daemon") or error("can't open syslog");
    $syslog_started=1;
};

sub lm($m;$system,$cat){
    # effect: logs message m
    $cat //= "info";
    $system and $m="$system: $m";
    $cat eq 'info' or $m="[$cat] $m";
    # encode
    my $b_m=encode('UTF-8',$m);
    # send
    if($main::debug){
	warn("$b_m\n");
    };
    $syslog_started and syslog($cat,$b_m);
    
    return 1;
};

sub error($m;$system){
    # effect: logs message m, die
    $cat="error";
    $system and $m="$system $m";
    $m="[error] $m";
    # encode
    my $b_m=encode('UTF-8',$m);
    # send
    $syslog_started and syslog("err",$b_m);
    die("$b_m\n");
};

# ---- package init ----
return 1;

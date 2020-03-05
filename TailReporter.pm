# ---- class TailReporter ----
# common class for Reporter reading log files

package DDgrey::TailReporter;

use strict;
use integer;

use Data::Dumper; # DEBUG
use IO::File;
use DDgrey::Perl6::Parameters;

use parent qw(DDgrey::Reporter);

# virtual class - no direct instances
# to be implemented by subclass: receive_line

# ---- constructor ----
sub new($class,$file){
    # return:  new reporter of class, following file
    # effect:  registers with select
    #          starts subprocess
    #          may raise exception

    my $self=$class->SUPER::new();

    -r $file or main::error("can't read $file");
    $self->{file}=$file;
    
    # open file handle
    $self->open();

    # set interval for running seek
    $main::select->register_interval(
	5,
	sub{
	    # no file handle, try opening
	    if(!$self->{fh}){
		main::lm("no $self->{file} found, trying to reopen",$self->service(),"warning");
		$self->open();
	    };

	    # re-open if nothing changed for a while
	    if($self->{fh}){
		if(time()-$self->{changed} > 60*60){
		    $self->close();
		    $self->open();
		};
	    };

	    # check if still need of pausing (due to system load)
	    if($self->{fh}){
		if($self->{paused} and $main::select->load() < 1){
		    $main::debug and main::lm("resuming tail reporter",$self->service());
		    $self->{paused}=0;
		    $self->register();
		};
	    };
	    
	    # seek and reset end of file flag
	    if($self->{fh}){
		if($self->{eof}){
		    $self->{fh}->seek(0,1);
		    $self->{eof}=0;
		    $self->register();
		};
	    };
	});
	
    return $self;
};

# ---- methods -----

sub open($self){
    # effect: tries to open configured file handle

    delete $self->{fh};
    my $fh;
    open($fh,$self->{file}) or return;
    $self->{fh}=$fh;
    
    $self->{fh}->blocking(0);
    $self->{changed}=time();
    $self->{eof}=0;
    $self->{paused}=0;
    
    # register
    $self->register();
};

sub register($self){
    # effect: registers with select

    $main::select->register_line($self->{fh},sub{
	$self->process_line(@_);
    });
    $main::select->register_exception($self->{fh},sub{
	$main::select->unregister($self->{fh});
	$self->{eof}=1;
    });
};

sub close($self){
    # effect: closes

    if(defined($self->{fh})){
	$main::select->unregister($self->{fh});
	$self->{fh}->close();
    };
};

sub process_line($self,$line){
    # effect: handles line
    
    $self->receive_line($line);
    $self->{changed}=time();

    if($main::select->load()){
	$main::debug and main::lm("pausing tail reporter due to query load",$self->service());
	$main::select->unregister($self->{fh});
	$self->{paused}=1;
    };
};

# ---- package init ----
return 1;

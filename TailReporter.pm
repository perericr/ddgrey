# ---- class TailReporter ----
# gemensam class för Reporter som läser loggar

package DDgrey::TailReporter;

use strict;
use integer;

use Data::Dumper; # DEBUG
use IO::File;
use DDgrey::Perl6::Parameters;

use parent qw(DDgrey::Reporter);

# virtuell class - inga direkta instanser
# dessa metoder ska implementeras av underclass: receive_line

# ---- konstruktor ----
sub new($class,$file){
    # retur:  ny rapportör av class från config, följer file
    # effekt: registrerar hos select, startar underprocess, kan sätta undantag

    my $self=$class->SUPER::new();

    -r $file or main::error("can't read $file");
    $self->{file}=$file;
    # öppna filhandtag
    $self->open();

    # sätt interval för att köra seek
    $main::select->register_interval(
	5,
	sub{
	    # provar att öppna om inget filhandtag
	    if(!$self->{fh}){
		main::lm("no $self->{file} found, trying to reopen",$self->service(),"warning");
		$self->open();
	    };

	    # öppnar igen om inte ändrad på ett tag
	    if($self->{fh}){
		if(time()-$self->{changed} > 60*60){
		    $self->close();
		    $self->open();
		};
	    };

	    # kollar om fortfarande behöver vara pausad
	    if($self->{fh}){
		if($self->{paused} and $main::select->load() < 1){
		    $main::debug and main::lm("resuming tail reporter",$self->service());
		    $self->{paused}=0;
		    $self->register();
		};
	    };
	    
	    # tar bort markering om filslut
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

# ---- metoder -----

sub open($self){
    # effekt: försöker öppnar filhandtag

    delete $self->{fh};
    my $fh;
    open($fh,$self->{file}) or return;
    $self->{fh}=$fh;
    
    $self->{fh}->blocking(0);
    $self->{changed}=time();
    $self->{eof}=0;
    $self->{paused}=0;
    
    # registrera
    $self->register();
};

sub register($self){
    # effekt: registrerar i select

    $main::select->register_line($self->{fh},sub{
	$self->process_line(@_);
    });
    $main::select->register_exception($self->{fh},sub{
	$main::select->unregister($self->{fh});
	$self->{eof}=1;
    });
};

sub close($self){
    # effekt: stänger

    $main::select->unregister($self->{fh});
    $self->{fh}->close();
};

sub process_line($self,$line){
    # effekt: tar hand om rad
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

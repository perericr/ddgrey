# ---- class ReportClient ----
# klass för skriv-anslutning till server för att skicka rapporter

package DDgrey::ReportClient;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

use DDgrey::Report;

use parent qw(DDgrey::Client);

# ---- konstruktor ----

# ---- metoder ----

sub service($self){
    # retur: namn på undersystem (för loggning)
    return "report client";
};

sub log_connect{
    # retur: huruvida logga anslutning
    return 0;
}

sub report($self,$report){
    # effekt: skicka report till server

    $main::debug > 1 and main::lm("scheduling report ".$report->unicode(),"report client");
    $self->schedule(sub{
	$self->send("report\r\n");
	$self->{line_handler}=sub{$self->handle_go(shift(),$report)};
    });
};

sub handle_go($self,$line,$report){
    # effekt: skickar report om line verkar OK

    if($line=~/^301\D/){
	$self->send($report->as_text().".\r\n");
	$self->{line_handler}=sub{$self->handle_reported(shift(),$report)};
    }
    else{
	main::lm("got error from server (".$line=~s/[\r\n]+$//r.")",$self->service(),"warning");
	delete($self->{line_handler});
    };
};

sub handle_reported($self,$line,$report){
    # effekt: accepterar line

    $main::debug > 1 and main::lm("sent report ".$report->unicode(),"report client");
    if(not $line=~/^200\D/){
	main::lm("got error from server (".$line=~s/[\r\n]+$//r.")",$self->service(),"warning");
    };
    delete($self->{line_handler});
};

# ---- package init ----
return 1;

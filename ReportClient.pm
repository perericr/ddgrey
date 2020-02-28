# ---- class ReportClient ----
# write connection to server for sending reports

package DDgrey::ReportClient;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;

use DDgrey::Report;

use parent qw(DDgrey::Client);

# ---- constructor ----

# ---- methods ----

sub service($self){
    # return: name of subsystem (for logging)
    return "report client";
};

sub log_connect{
    # return: whether to log connect
    return 0;
}

sub report($self,$report){
    # effect: sends report to server

    $main::debug > 1 and main::lm("scheduling report ".$report->unicode(),"report client");
    $self->schedule(sub{
	$self->send("report\r\n");
	$self->{line_handler}=sub{$self->handle_go(shift(),$report)};
    });
};

sub handle_go($self,$line,$report){
    # effect: sends report to server if line inidicates possible

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
    # effect: handles line
    # pre:    line is result of sending report to server

    $main::debug > 1 and main::lm("sent report ".$report->unicode(),"report client");
    if(not $line=~/^200\D/){
	main::lm("got error from server (".$line=~s/[\r\n]+$//r.")",$self->service(),"warning");
    };
    delete($self->{line_handler});
};

# ---- package init ----
return 1;

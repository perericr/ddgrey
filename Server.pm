# ---- class Server ----
# base class for socket server

package DDgrey::Server;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;
use Socket;


# ---- methods ----

sub close($self){
    # effect: closes server

    # close client connections
    foreach my $client (values %{$self->{client_connection}}){
	$client->close();
    };

    # close server
    $main::select->unregister($self->{fh});
    $self->{fh}->shutdown(2);
    $self->{fh}->close();
};

sub register_client($self,$client){
    # effect: registers client connection client
    
    $self->{client_connection}->{$client}=$client;
};

sub unregister_client($self,$client){
    # effect: deregisters client connection client
    
    delete $self->{client_connection}->{$client};
};

# ---- package init ----
return 1;

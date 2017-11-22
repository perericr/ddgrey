# ---- klass Server ----
# basklass för socket-server

package DDgrey::Server;

use strict;
use integer;

use Data::Dumper; # DEBUG
use DDgrey::Perl6::Parameters;
use Socket;


# ---- metoder ----

sub close($self){
    # effekt: stänger server

    # stänger klientförbindelser
    foreach my $client (values %{$self->{client_connection}}){
	$client->close();
    };

    # stänger server
    $main::select->unregister($self->{fh});
    $self->{fh}->shutdown(2);
    $self->{fh}->close();
};

sub register_client($self,$client){
    # effekt: registrera klientförbindelse client
    
    $self->{client_connection}->{$client}=$client;
};

sub unregister_client($self,$client){
    # effekt: avregistrera klientförbindelse client
    
    delete $self->{client_connection}->{$client};
};

# ---- init av paket ----
return 1;

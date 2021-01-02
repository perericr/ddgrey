# ---- class MainConfig ----
# main configuration

package DDgrey::MainConfig;

use strict;
use integer;

use DDgrey::Perl6::Parameters;

use parent qw(DDgrey::Config);

# ---- constructor ----

sub new($class){
    # return: new main configuration
    # effect: may raise exception

    return $class->SUPER::new("ddgrey.conf",{commands=>['user','name','port','search_duration','policy_duration','retry','grey_default','grey_short','grey_min','grey_max','blacklist','exim4_mainlog','exim4_unknown','report_verify'],multiple=>['accept_reader','accept_writer','accept','server_read','server_write','server','peer','traps','hard_trap','soft_trap','service','trusted','rbls'],'complex'=>['server','server_read','server_write','peer']});
};

# ---- package init ----
return 1;

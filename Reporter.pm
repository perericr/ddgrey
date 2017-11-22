# ---- class Reporter ----
# class för rapportör

package DDgrey::Reporter;

use strict;
use integer;

use DDgrey::Perl6::Parameters;

use DDgrey::Report;

# virtuell class - inga direkta instanser

# ---- konstruktor ----
sub new($class){
    # retur:  ny rapportör av class från config, användande select

    my $self={};
    return bless($self,$class);
};

# ---- init av paket ----
return 1;

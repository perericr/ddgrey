# ---- class Reporter ----
# reporter

package DDgrey::Reporter;

use strict;
use integer;

use DDgrey::Perl6::Parameters;

use DDgrey::Report;

# virtual class - no direct instances

# ---- construktor ----
sub new($class){
    # return:  new reporter of class

    my $self={};
    return bless($self,$class);
};

# ---- package init ----
return 1;

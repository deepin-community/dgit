# -*- perl -*-

package Debian::Dgit::Infra;

use strict;
use warnings;

# Scripts and programs which are going to `use Debian::Dgit' but which
# live in dgit-infrastructure (ie are installed with install-infra)
# should `use Debian::Dgit::Infra' first.  All this module does is
# adjust @INC so that the script gets the version of the script from
# the dgit-infrastructure package (which is installed in a different
# location and may be a different version).

# unshift @INC, q{/usr/share/dgit/infra/perl5}; ###substituted###

1;

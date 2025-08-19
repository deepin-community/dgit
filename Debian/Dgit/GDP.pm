# -*- perl -*-

package Debian::Dgit::GDP;

use strict;
use warnings;

# Scripts and programs which are going to `use Debian::Dgit' but which
# live in git-debpush (ie are installed with install-gdp)
# should `use Debian::Dgit::GDP' first.  All this module does is
# adjust @INC so that the script gets the version of the script from
# the git-debpush package (which is installed in a different
# location and may be a different version).

# To use this with ExitStatus, put at the top (before use strict, even):
#
#   END { $? = $Debian::Dgit::ExitStatus::desired // -1; };
#   use Debian::Dgit::GDP;
#   use Debian::Dgit::ExitStatus;
#
# and then replace every call to `exit' with `finish'.
# Add a `finish 0' to the end of the program.

# unshift @INC, q{/usr/share/dgit/gdp/perl5}; ###substituted###

1;

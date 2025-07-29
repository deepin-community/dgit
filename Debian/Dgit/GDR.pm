# -*- perl -*-

package Debian::Dgit::GDR;

use strict;
use warnings;

# Scripts and programs which are going to `use Debian::Dgit' but which
# live in git-debrebase (ie are installed with install-gdr)
# should `use Debian::Dgit::GDR' first.  All this module does is
# adjust @INC so that the script gets the version of the script from
# the git-debrebase package (which is installed in a different
# location and may be a different version).

# To use this with ExitStatus, put at the top (before use strict, even):
#
#   END { $? = $Debian::Dgit::ExitStatus::desired // -1; };
#   use Debian::Dgit::GDR;
#   use Debian::Dgit::ExitStatus;
#
# and then replace every call to `exit' with `finish'.
# Add a `finish 0' to the end of the program.

# unshift @INC, q{/usr/share/dgit/gdr/perl5}; ###substituted###

1;

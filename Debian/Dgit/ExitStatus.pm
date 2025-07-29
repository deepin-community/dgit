# -*- perl -*-

package Debian::Dgit::ExitStatus;

# To use this, at the top (before use strict, even):
#
#   END { $? = $Debian::Dgit::ExitStatus::desired // -1; };
#   use Debian::Dgit::ExitStatus;
#
# and then replace every call to `exit' with `finish'.
# Add a `finish 0' to the end of the program.

BEGIN {
    use Exporter;
    @ISA = qw(Exporter);
    @EXPORT = qw(finish $desired);
}

our $desired;

sub finish ($) {
    $desired = $_[0] // 0;
    exit $desired;
}

1;

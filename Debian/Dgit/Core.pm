# -*- perl -*-
# dgit
# Debian::Dgit::Core: functions common to programs from all binary packages
#
# Copyright (C)2015-2020,2022,2023,2025 Ian Jackson
# Copyright (C)2020,2025                Sean Whitton
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.

package Debian::Dgit::Core;

use strict;
use warnings;

use Carp;
use Debian::Dgit::I18n;

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter);
    @EXPORT = qw(shellquote);
}

sub shellquote {
    # Quote an argument list for use as a fragment of shell text.
    #
    # Shell quoting doctrine in dgit.git:
    #  * perl lists are always unquoted argument lists
    #  * perl scalars are always individual arguments,
    #    or if being passed to a shell, quoted shell text.
    #
    # So shellquote returns a scalar.
    #
    # When invoking ssh-like programs, that concatenate the arguments
    # with spaces and then treat the result as a shell command, we never
    # use the concatenation.  We pass the intended script as a single
    # parameter (which is in accordance with the above doctrine).
    my @out;
    local $_;
    defined or confess __ 'internal error' foreach @_;
    foreach my $a (@_) {
	$_ = $a;
	if (!length || m{[^-=_./:0-9a-z]}i) {
	    s{['\\]}{'\\$&'}g;
	    push @out, "'$_'";
	} else {
	    push @out, $_;
	}
    }
    return join ' ', @out;
}

1;

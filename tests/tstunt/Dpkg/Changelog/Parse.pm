# -*- perl -*-
#
# Copyright (C) 2015-2016  Ian Jackson
#
# Some bits stolen from the proper Dpkg::Changelog::Parse
# (from dpkg-dev 1.16.16):
#
# Copyright (C) 2005, 2007 Frank Lichtenheld <frank@lichtenheld.de>
# Copyright (C) 2009       Raphael Hertzog <hertzog@debian.org>
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

package Dpkg::Changelog::Parse;

use strict;
use warnings;

our $VERSION = "1.00";

use Dpkg::Control::Changelog;

use base qw(Exporter);
our @EXPORT = qw(changelog_parse);

die +(join " ", %ENV)." ?" if $ENV{'DGIT_NO_TSTUNT_CLPARSE'};

sub changelog_parse {
    my (%options) = @_; # largely ignored

#use Data::Dumper;
#print STDERR "CLOG PARSE ", Dumper(\%options);
#
# We can't do this because lots of things use `since' which
# we don't implement, and it's the test cases that arrange that
# the since value happens to be such that we are to print one output.
#
#    foreach my $k (keys %options) {
#	my $v = $options{$k};
#	if ($k eq 'file') { }
#	elsif ($k eq 'offset') { die "$v ?" unless $v <= 1; } # wtf, 1==0 ?
#	elsif ($k eq 'count') { die "$v ?" unless $v == 1; }
#	else { die "$k ?"; }
#    }

    $options{'file'} //= 'debian/changelog';

    open P, "dpkg-parsechangelog -l$options{'file'} |" or die $!;

    my $fields = Dpkg::Control::Changelog->new();
    $fields->parse(\*P, "output of stunt changelog parser");

#use Data::Dumper;
#print STDERR "PARSE $0 ", Dumper($fields);

    close P or die "$! $?";

    return $fields;
}

1;

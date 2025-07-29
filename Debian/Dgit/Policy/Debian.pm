# -*- perl -*-

package Debian::Dgit::Policy::Debian;

use strict;
use warnings;

use POSIX;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    $VERSION     = 1.00;
    @ISA         = qw(Exporter);
    @EXPORT      = qw(poldb_path poldb_setup $poldbh);
    %EXPORT_TAGS = ( );
    @EXPORT_OK   = qw();
}

our @EXPORT_OK;

our $poldbh;

sub poldb_path ($) {
    my ($repos) = @_;
    return "$repos/policy.sqlite3";
}

sub poldb_setup ($;$) {
    my ($policydb, $hook) = @_;

    $poldbh ||= DBI->connect("dbi:SQLite:$policydb",'','', {
	RaiseError=>1, PrintError=>1, AutoCommit=>0
			   });

    $hook->() if $hook;

    $poldbh->do("PRAGMA foreign_keys = ON");
}

1;

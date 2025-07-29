# -*- perl -*-
# dgit
# Debian::Dgit::Proto: protocol helper utilities
#
# Copyright (C)2015-2020,2022-2024 Ian Jackson
# Copyright (C)2020-2024           Sean Whitton
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

package Debian::Dgit::ProtoConn;

use strict;
use warnings;

use Debian::Dgit;
use Debian::Dgit::I18n;

use Carp;
use IPC::Open2 ();

sub new ($$) {
    # Arguments to new:
    #   $fh_r      filehandle to read from
    #   $fh_w      filehandle to write to
    my ($class, $fh_r, $fh_w) = @_;
    bless {
        R => $fh_r,
        W => $fh_w,
	Cmd => undef,
	Pid => undef,
	Desc => undef,
        EofHook => sub { undef; },
        FailHook => sub { undef; },
    } => $class;
}

sub open2 {
    my $class = shift;
    my $pid = IPC::Open2::open2(my $fh_r, my $fh_w, @_);
    my $r = Debian::Dgit::ProtoConn->new($fh_r, $fh_w);
    $r->{Pid} = $pid;
    $r->{Cmd} = [ @_ ];
    $r
}

# $hook is called when we get unexpected eof and
# should return a (translated) message,
# or undef if a generic message is fine.
#
# The hook is called by the following functions:
#   expect
#   read_bytes
#   readfail
# in each case, if the stream got EOF, but not if our read got an error.
sub set_eof_hook ($$) {
    my ($self, $hook) = @_;

    $self->{EofHook} = $hook;
}

# $hook is called just before fail, and it is passed the error message as sole argument
sub set_fail_hook ($$) {
    my ($self, $hook) = @_;

    $self->{FailHook} = $hook;
}

sub set_description ($$) {
    my ($self, $desc) = @_;

    $self->{Desc} = $desc;
}

sub _fail ($$) {
    my ($self, $m) = @_;
    $self->{FailHook}($m);
    fail +(defined $self->{Desc} ? $self->{Desc}.': ' : '').$m;
}

sub bad ($$) {
    my ($self, $m) = @_;
    $self->_fail(f_ "connection lost: %s", $!) if $self->{R}->error;
    $self->_fail(f_ "protocol violation; %s not expected", $m);
}

sub get_pid ($$) {
    my ($self) = @_;
    $self->{Pid};
}
sub get_command ($$) {
    my ($self) = @_;
    $self->{Cmd};
}

# die due to a read error.
#
# `$wh` is a (translated) description of what we were trying to read
# (which is used on EOF, if set_eof_hook was not called.)
sub readfail ($$) {
    my ($self, $wh) = @_;
    $self->_fail(f_ "connection lost: %s", $!) if $!;
    my $report = $self->{EofHook}();
    $self->_fail($report) if defined $report;
    $self->bad(f_ "eof (reading %s)", $wh);
}

# Expects to receive a message in some particular form(s)
#
# $match->() is used to analyse the received message.
# Calls $match->() having set `$_` to the received line (chomped).
#
# In array context, calls $match->() in array context;
# a nonempty array means the value matched,
# and is then returned.
#
# In other contexts, calls $match->() in scalar context;
# a true value means the value matched, and is returned.
#
# If $match returns false, it is bad (expect calls $self->bad()).
sub expect ($&) {
    my ($self, $match) = @_;
    # Bind $_ for the benefit of the user's matcher.
    local $_ = readline $self->{R};
    defined && chomp or $self->readfail(__ "protocol message");
    printdebug +($self->{Desc} // '')."<< $_\n";
    if (wantarray) {
	my @r = &$match;
	return @r if @r;
    } else {
	my $r = &$match;
	return $r if $r;
    }
    $self->bad(f_ "\`%s'", $_);
}

sub read_bytes ($$) {
    my ($self, $nbytes) = @_;
    $nbytes =~ m/^[1-9]\d{0,5}$|^0$/ or $self->bad(__ "bad byte count");
    my $d;
    my $got = read $self->{R}, $d, $nbytes;
    $got==$nbytes or $self->readfail(__ "data block");
    return $d;
}

# Receive data sent via zero or more `data-block` messages.
#
# Successive data blocks are passed as the sole argument to `$take_data`.
#
# The caller should consider doing at least one `printdebug`
# before calling this function, if there isn't one nearby already.
sub receive_data_blocks ($&) {
    my ($self, $take_data) = @_;
    for (;;) {
	my ($more_data, $l) = $self->expect(sub {
	    m/^data-block (.+)$/ ? (1,$1) :
	    m/^data-end$/        ? (0,)   :
	                           ();
	});
	last unless $more_data;
	my $d = $self->read_bytes($l);
	$take_data->($d);
    }
}

sub receive_file ($$) {
    my ($self, $ourfn) = @_;
    printdebug +($self->{Desc} // '')."() $ourfn\n";
    my $pf = new IO::File($ourfn, ">") or die "$ourfn: $!";
    $self->receive_data_blocks(sub {
	print $pf $_[0] or confess "$!";
    });
    close $pf or confess "$!";
}

# Like `send` but doesn't add a newline and doesn't call `printdebug`
sub send_raw (&$) {
    my ($self, $msg) = @_;
    my $fh = $self->{W};
    print $fh $msg or confess "$!";
}

sub send (&$) {
    my ($self, $msg) = @_;
    printdebug +($self->{Desc} // '').">> $msg\n";
    $self->send_raw("$msg\n");
}

sub send_counted_message ($$$) {
    my ($self, $command, $message) = @_;
    $self->send("$command ".length($message));
    $self->send_raw($message);
}

sub send_file ($$) {
    my ($self, $ourfn) = @_;
    my $pf = new IO::File($ourfn, '<') or die "$ourfn: $!";
    my $fh = $self->{W};
    for (;;) {
	my $d;
	my $got = (read $pf, $d, 65536) // die "$ourfn: $!";
	last if !$got;
	print $fh "data-block ".length($d)."\n" or confess "$!";
	print $fh $d or confess "$!";
    }
    $pf->error and die "$ourfn $!";
    print $fh "data-end\n" or confess "$!";
    close $pf;
}

1;

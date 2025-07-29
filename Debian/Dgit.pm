# -*- perl -*-
# dgit
# Debian::Dgit: functions common to dgit and its helpers and servers
#
# Copyright (C)2015-2020,2022-2023 Ian Jackson
# Copyright (C)2020                Sean Whitton
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

package Debian::Dgit;

use strict;
use warnings;

use Carp;
use POSIX;
use IO::Handle;
use Config;
use Digest::SHA;
use Data::Dumper;
use IPC::Open2;
use File::Path qw(make_path);
use File::Basename;
use Dpkg::Control::Hash;
use Debian::Dgit::ExitStatus;
use Debian::Dgit::I18n;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    $VERSION     = 1.00;
    @ISA         = qw(Exporter);
    @EXPORT      = qw(setup_sigwarn forkcheck_setup forkcheck_mainprocess
		      dep14_version_mangle
                      debiantags debiantag_new
		      debiantag_maintview
		      upstreamversion
		      upstream_commitish_search resolve_upstream_version
		      stripepoch source_file_leafname is_orig_file_of_p_v
		      server_branch server_ref
                      stat_exists link_ltarget rename_link_xf
		      hashfile
                      fail failmsg ensuredir ensurepath
		      must_getcwd rmdir_r executable_on_path
                      waitstatusmsg failedcmd_waitstatus
		      failedcmd_report_cmd failedcmd
                      runcmd runcmd_quieten
		      shell_cmd cmdoutput cmdoutput_errok
		      @git
                      git_rev_parse changedir_git_toplevel git_cat_file
		      git_get_ref git_get_symref git_for_each_ref
                      git_for_each_tag_referring is_fast_fwd
		      git_check_unmodified
		      git_reflog_action_msg  git_update_ref_cmd
		      rm_subdir_cached read_tree_subdir
		      read_tree_debian read_tree_upstream
		      make_commit hash_commit hash_commit_text
		      reflog_cache_insert reflog_cache_lookup
		      $failmsg_prefix
                      $package_re $component_re $suite_re $deliberately_re
		      $distro_re $versiontag_re $series_filename_re
		      $orig_f_comp_re $orig_f_sig_re
		      $tarball_f_ext_re $orig_f_tail_re
		      $extra_orig_namepart_re
		      $git_null_obj
                      $branchprefix
		      $ffq_refprefix $gdrlast_refprefix
                      initdebug enabledebug enabledebuglevel
                      printdebug debugcmd
                      $printdebug_when_debuglevel $debugcmd_when_debuglevel
                      $atext_re $dot_atom_text_re $addr_spec_re $angle_addr_re
                      $debugprefix *debuglevel *DEBUG
                      shellquote printcmd messagequote
                      $negate_harmful_gitattrs
		      changedir git_slurp_config_src
		      gdr_ffq_prev_branchinfo
                      tainted_objects_message
		      parsecontrolfh parsecontrol parsechangelog
		      getfield parsechangelog_loop
		      playtree_setup playtree_write_gbp_conf);
    # implicitly uses $main::us
    %EXPORT_TAGS = ( policyflags => [qw(NOFFCHECK FRESHREPO NOCOMMITCHECK)],
		     playground => [qw(record_maindir $maindir $local_git_cfg
				       $maindir_gitdir $maindir_gitcommon
				       fresh_playground
                                       ensure_a_playground)]);
    @EXPORT_OK   = ( @{ $EXPORT_TAGS{policyflags} },
		     @{ $EXPORT_TAGS{playground} } );
}

our @EXPORT_OK;

our $package_re = '[0-9a-z][-+.0-9a-z]*';
our $component_re = '[0-9a-zA-Z][-+.0-9a-zA-Z]*';
our $suite_re = '[-+.0-9a-z]+';
our $deliberately_re = "(?:TEST-)?$package_re";
our $distro_re = $component_re;
our $versiontag_re = qr{[-+.\%_0-9a-zA-Z/]+};
our $branchprefix = 'dgit';
our $series_filename_re = qr{(?:^|\.)series(?!\n)$}s;
our $extra_orig_namepart_re = qr{[-0-9a-zA-Z]+};
our $orig_f_comp_re = qr{orig(?:-$extra_orig_namepart_re)?};
our $orig_f_sig_re = '\\.(?:asc|gpg|pgp)';
our $tarball_f_ext_re = "\\.tar(?:\\.\\w+)?(?:$orig_f_sig_re)?";
our $orig_f_tail_re = "$orig_f_comp_re$tarball_f_ext_re";
our $git_null_obj = '0' x 40;
our $ffq_refprefix = 'ffq-prev';
our $gdrlast_refprefix = 'debrebase-last';
our $printdebug_when_debuglevel = 1;
our $debugcmd_when_debuglevel = 1;

# This is RFC 5322's 'atext'.
our $atext_re         = qr([[:alnum:]!#$%&'*+\-/=?^_`{|}~])a;
# This is RFC 5322's 'dot-atom-text' without comments and whitespace.
our $dot_atom_text_re = qr($atext_re(?:\.|$atext_re)*)a;
# This is RFC 5322's 'addr-spec' without obsolete syntax.
our $addr_spec_re = qr($dot_atom_text_re\@$dot_atom_text_re);
# This is RFC 5322's 'angle-addr' without obsolete syntax.
our $angle_addr_re = qr(\<($addr_spec_re)\>)a;

our (@git) = qw(git);

# these three all go together, only valid after record_maindir
our $maindir;
our $maindir_gitdir;
our $maindir_gitcommon;

# policy hook exit status bits
# see dgit-repos-server head comment for documentation
# 1 is reserved in case something fails with `exit 1' and to spot
# dynamic loader, runtime, etc., failures, which report 127 or 255
sub NOFFCHECK () { return 0x2; }
sub FRESHREPO () { return 0x4; }
sub NOCOMMITCHECK () { return 0x8; }

# Set this variable (locally) at the top of an `eval { }` when
#  - general code within the eval might call fail
#  - these errors are nonfatal and maybe not even errors
# This replaces `dgit: error: ` at the start of the message.
our $failmsg_prefix;

our $debugprefix;
our $debuglevel = 0;

our $negate_harmful_gitattrs =
    "-text -eol -crlf -ident -filter -working-tree-encoding";
    # ^ when updating this, alter the regexp in dgit:is_gitattrs_setup

our $forkcheck_mainprocess;

sub forkcheck_setup () {
    $forkcheck_mainprocess = $$;
}

sub forkcheck_mainprocess () {
    # You must have called forkcheck_setup or setup_sigwarn already
    getppid != $forkcheck_mainprocess;
}

sub setup_sigwarn () {
    # $SIG{__WARN__} affects `warn` but not `-w` (`use warnings`).
    # Ideally we would fatalise all warnings.  However:
    #  1. warnings(3perl) has a long discussion of why this is
    #     a bad idea due to bugs in, well, everything.
    #  2. So maybe we would want to do that only when running the tests,
    #  3. However, because it's a lexical keyword it's difficult to
    #     manipulate at runtime.  We could use the caller's ^H
    #     via caller, but that would take effect only in the main
    #     program (which calls setup_sigwarn, eg dgit.git/dgit),
    #     and not in the modules.
    # This is all swimming too much upstream.
    forkcheck_setup();
    $SIG{__WARN__} = sub { 
	confess $_[0] if forkcheck_mainprocess;
    };
}

sub initdebug ($) { 
    ($debugprefix) = @_;
    open DEBUG, ">/dev/null" or confess "$!";
}

sub enabledebug () {
    open DEBUG, ">&STDERR" or confess "$!";
    DEBUG->autoflush(1);
    $debuglevel ||= 1;
}
    
sub enabledebuglevel ($) {
    my ($newlevel) = @_; # may be undef (eg from env var)
    confess if $debuglevel;
    $newlevel //= 0;
    $newlevel += 0;
    return unless $newlevel;
    $debuglevel = $newlevel;
    enabledebug();
}
    
sub printdebug {
    # Prints a prefix, and @_, to DEBUG.  @_ should normally contain
    # a trailing \n.

    # With no (or only empty) arguments just prints the prefix and
    # leaves the caller to do more with DEBUG.  The caller should make
    # sure then to call printdebug with something ending in "\n" to
    # get the prefix right in subsequent calls.

    return unless $debuglevel >= $printdebug_when_debuglevel;
    our $printdebug_noprefix;
    print DEBUG $debugprefix unless $printdebug_noprefix;
    pop @_ while @_ and !length $_[-1];
    return unless @_;
    print DEBUG @_ or confess "$!";
    $printdebug_noprefix = $_[-1] !~ m{\n$};
}

sub messagequote ($) {
    local ($_) = @_;
    s{\\}{\\\\}g;
    s{\n}{\\n}g;
    s{\x08}{\\b}g;
    s{\t}{\\t}g;
    s{[\000-\037\177]}{ sprintf "\\x%02x", ord $& }ge;
    $_;
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

sub printcmd {
    my $fh = shift @_;
    my $intro = shift @_;
    print $fh $intro." ".(shellquote @_)."\n" or confess "$!";
}

sub debugcmd {
    my $extraprefix = shift @_;
    printcmd(\*DEBUG,$debugprefix.$extraprefix,@_)
	if $debuglevel >= $debugcmd_when_debuglevel;
}

sub dep14_version_mangle ($) {
    my ($v) = @_;
    # DEP-14 patch proposed 2016-11-09  "Version Mangling"
    $v =~ y/~:/_%/;
    $v =~ s/\.(?=\.|$|lock$)/.#/g;
    return $v;
}

sub debiantag_new ($$) { 
    my ($v,$distro) = @_;
    return "archive/$distro/".dep14_version_mangle $v;
}

sub debiantag_maintview ($$) { 
    my ($v,$distro) = @_;
    return "$distro/".dep14_version_mangle $v;
}

sub debiantags ($$) {
    my ($version,$distro) = @_;
    map { $_->($version, $distro) } (\&debiantag_new, \&debiantag_maintview);
}

sub stripepoch ($) {
    my ($vsn) = @_;
    $vsn =~ s/^\d+\://;
    return $vsn;
}

sub upstreamversion ($) {
    my ($vsn) = @_;
    $vsn =~ s/-[^-]+$//;
    return $vsn;
}

sub source_file_leafname ($$$) {
    my ($package,$vsn,$sfx) = @_;
    return "${package}_".(stripepoch $vsn).$sfx
}

sub is_orig_file_of_p_v ($$$) {
    my ($f, $package, $upstreamvsn) = @_;
    my $base = source_file_leafname $package, $upstreamvsn, '';
    return 0 unless $f =~ m/^\Q$base\E\.$orig_f_tail_re$/;
    return 1;
}

sub server_branch ($) { return "$branchprefix/$_[0]"; }
sub server_ref ($) { return "refs/".server_branch($_[0]); }

sub stat_exists ($) {
    my ($f) = @_;
    return 1 if stat $f;
    return 0 if $!==&ENOENT;
    confess "stat $f: $!";
}

sub _us () {
    $::us // ($0 =~ m#[^/]*$#, $&);
}

sub failmsg {
    my $s = "@_";
    $s =~ s/\n\n$/\n/g;
    my $prefix;
    my $prefixnl;
    if (defined $failmsg_prefix) {
	$prefixnl = '';
	$prefix = $failmsg_prefix;
	$s .= "\n";
    } else {
	$prefixnl = "\n";
	$s = f_ "error: %s\n", "$s";
	$prefix = _us().": ";
    }
    $s =~ s/^/$prefix/gm;
    return $prefixnl.$s;
}

sub fail {
    die failmsg @_;
}

sub ensuredir ($) {
    my ($dir) = @_; # does not create parents
    return if mkdir $dir;
    return if $! == EEXIST;
    confess "mkdir $dir: $!";
}

sub ensurepath ($$) {
    my ($firsttocreate, $subdir) = @_; # creates necessary bits of $subidr
    ensuredir $firsttocreate;
    make_path "$firsttocreate/$subdir";
}

sub must_getcwd () {
    my $d = getcwd();
    defined $d or fail f_ "getcwd failed: %s\n", $!;
    return $d;
}

sub executable_on_path ($) {
    my ($program) = @_;
    return 1 if $program =~ m{/};
    my @path = split /:/, ($ENV{PATH} // "/usr/local/bin:/bin:/usr/bin");
    foreach my $pe (@path) {
	my $here = "$pe/$program";
	return $here if stat_exists $here && -x _;
    }
    return undef;
}

our @signames = split / /, $Config{sig_name};

sub waitstatusmsg () {
    if (!$?) {
	return __ "terminated, reporting successful completion";
    } elsif (!($? & 255)) {
	return f_ "failed with error exit status %s", WEXITSTATUS($?);
    } elsif (WIFSIGNALED($?)) {
	my $signum=WTERMSIG($?);
	return f_ "died due to fatal signal %s",
	    ($signames[$signum] // "number $signum").
	    ($? & 128 ? " (core dumped)" : ""); # POSIX(3pm) has no WCOREDUMP
    } else {
	return f_ "failed with unknown wait status %s", $?;
    }
}

sub failedcmd_report_cmd {
    my $intro = shift @_;
    $intro //= __ "failed command";
    { local ($!); printcmd \*STDERR, _us().": $intro:", @_ or confess "$!"; };
}

sub failedcmd_waitstatus {
    if ($? < 0) {
	return f_ "failed to fork/exec: %s", $!;
    } elsif ($?) {
	return f_ "subprocess %s", waitstatusmsg();
    } else {
	return __ "subprocess produced invalid output";
    }
}

sub failedcmd {
    # Expects $!,$? as set by close - see below.
    # To use with system(), set $?=-1 first.
    #
    # Actual behaviour of perl operations:
    #   success              $!==0       $?==0       close of piped open
    #   program failed       $!==0       $? >0       close of piped open
    #   syscall failure      $! >0       $?=-1       close of piped open
    #   failure              $! >0       unchanged   close of something else
    #   success              trashed     $?==0       system
    #   program failed       trashed     $? >0       system
    #   syscall failure      $! >0       unchanged   system
    failedcmd_report_cmd undef, @_;
    fail failedcmd_waitstatus();
}

sub runcmd {
    debugcmd "+",@_;
    $!=0; $?=-1;
    failedcmd @_ if system @_;
}

sub shell_cmd {
    my ($first_shell, @cmd) = @_;
    return qw(sh -ec), $first_shell.'; exec "$@"', 'x', @cmd;
}

# Runs the command in @_, but capturing its stdout and stderr.
# Prints those to our stderr only if the command fails.
sub runcmd_quieten {
    debugcmd "+",@_;
    $!=0; $?=-1;
    my @real_cmd = shell_cmd <<'END', @_;
                        set +e; output=$("$@" 2>&1); rc=$?; set -e
                        if [ $rc = 0 ]; then exit 0; fi
                        printf >&2 "%s\n" "$output"
                        exit $rc
END
    failedcmd @_ if system @real_cmd;
}

sub cmdoutput_errok {
    confess Dumper(\@_)." ?" if grep { !defined } @_;
    local $printdebug_when_debuglevel = $debugcmd_when_debuglevel;
    debugcmd "|",@_;
    open P, "-|", @_ or confess "$_[0] $!";
    my $d;
    $!=0; $?=0;
    { local $/ = undef; $d = <P>; }
    confess "$!" if P->error;
    if (!close P) { printdebug "=>!$?\n"; return undef; }
    chomp $d;
    if ($debuglevel > 0) {
	$d =~ m/^.*/;
	my $dd = $&;
	my $more = (length $' ? '...' : ''); #');
	$dd =~ s{[^\n -~]|\\}{ sprintf "\\x%02x", ord $& }ge;
	printdebug "=> \`$dd'",$more,"\n";
    }
    return $d;
}

sub cmdoutput {
    my $d = cmdoutput_errok @_;
    defined $d or failedcmd @_;
    return $d;
}

sub link_ltarget ($$) {
    my ($old,$new) = @_;
    lstat $old or return undef;
    if (-l _) {
	$old = cmdoutput qw(realpath  --), $old;
    }
    my $r = link $old, $new;
    $r = symlink $old, $new if !$r && $!==EXDEV;
    $r or fail "(sym)link $old $new: $!\n";
}

sub rename_link_xf ($$$) {
    # renames/moves or links/copies $src to $dst,
    # even if $dst is on a different fs
    # (May use the filename "$dst.tmp".);
    # On success, returns true.
    # On failure, returns false and sets
    #    $@ to a reason message
    #    $! to an errno value, or -1 if not known
    # having possibly printed something about mv to stderr.
    # Not safe to use without $keeporig if $dst might be a symlink
    # to $src, as it might delete $src leaving $dst invalid.
    my ($keeporig,$src,$dst) = @_;
    if ($keeporig
	? link   $src, $dst
	: rename $src, $dst) {
	return 1;
    }
    if ($! != EXDEV) {
	$@ = "$!";
	return 0;
    }
    if (!stat $src) {
	$@ = f_ "stat source file: %S", $!;
	return 0;
    }
    my @src_stat = (stat _)[0..1];

    my @dst_stat;
    if (stat $dst) {
	@dst_stat = (stat _)[0..1];
    } elsif ($! == ENOENT) {
    } else {
	$@ = f_ "stat destination file: %S", $!;
	return 0;
    }

    if ("@src_stat" eq "@dst_stat") {
	# (Symlinks to) the same file.  No need for a copy but
	# we may need to delete the original.
	printdebug "rename_link_xf $keeporig $src $dst EXDEV but same\n";
    } else {
	$!=0; $?=0;
	my @cmd = (qw(cp --), $src, "$dst.tmp");
	debugcmd '+',@cmd;
	if (system @cmd) {
	    failedcmd_report_cmd undef, @cmd;
	    $@ = failedcmd_waitstatus();
	    $! = -1;
	    return 0;
	}
	if (!rename "$dst.tmp", $dst) {
	    $@ = f_ "finally install file after cp: %S", $!;
	    return 0;
	}
    }
    if (!$keeporig) {
	if (!unlink $src) {
	    $@ = f_ "delete old file after cp: %S", $!;
	    return 0;
	}
    }
    return 1;
}

sub hashfile ($) {
    my ($fn) = @_;
    my $h = Digest::SHA->new(256);
    $h->addfile($fn);
    return $h->hexdigest();
}

sub git_rev_parse ($;$) {
    my ($ref, $cmd_map) = @_;
    $cmd_map //= sub { @_; };
    return cmdoutput $cmd_map->(qw(git rev-parse), "$ref~0");
}

sub changedir_git_toplevel () {
    my $toplevel = cmdoutput qw(git rev-parse --show-toplevel);
    length $toplevel or fail __ <<END;
not in a git working tree?
(git rev-parse --show-toplevel produced no output)
END
    chdir $toplevel or fail f_ "chdir toplevel %s: %s\n", $toplevel, $!;
}

sub git_cat_file ($;$) {
    my ($objname, $etype) = @_;
    # => ($type, $data) or ('missing', undef)
    # in scalar context, just the data
    # if $etype defined, dies unless type is $etype or in @$etype
    our ($gcf_pid, $gcf_i, $gcf_o);
    local $printdebug_when_debuglevel = $debugcmd_when_debuglevel;
    my $chk = sub {
	my ($gtype, $data) = @_;
	if ($etype) {
	    $etype = [$etype] unless ref $etype;
	    confess "$objname expected @$etype but is $gtype"
		unless grep { $gtype eq $_ } @$etype;
	}
	return ($gtype, $data);
    };
    if (!$gcf_pid) {
	my @cmd = qw(git cat-file --batch);
	debugcmd "GCF|", @cmd;
	$gcf_pid = open2 $gcf_o, $gcf_i, @cmd or confess "$!";
    }
    printdebug "GCF>| $objname\n";
    print $gcf_i $objname, "\n" or confess "$!";
    my $x = <$gcf_o>;
    printdebug "GCF<| ", $x;
    if ($x =~ m/ (missing)$/) { return $chk->($1, undef); }
    my ($type, $size) = $x =~ m/^.* (\w+) (\d+)\n/ or confess "$objname ?";
    my $data;
    (read $gcf_o, $data, $size) == $size or confess "$objname $!";
    $x = <$gcf_o>;
    $x eq "\n" or confess "$objname ($_) $!";
    return $chk->($type, $data);
}

sub git_get_symref (;$) {
    my ($symref) = @_;  $symref //= 'HEAD';
    # => undef if not a symref, otherwise refs/...
    my @cmd = (qw(git symbolic-ref -q HEAD));
    my $branch = cmdoutput_errok @cmd;
    if (!defined $branch) {
	$?==256 or failedcmd @cmd;
    } else {
	chomp $branch;
    }
    return $branch;
}

sub git_for_each_ref ($$;$) {
    my ($pattern,$func,$gitdir) = @_;
    # calls $func->($objid,$objtype,$fullrefname,$reftail);
    # $reftail is RHS of ref after refs/[^/]+/
    # breaks if $pattern matches any ref `refs/blah' where blah has no `/'
    # $pattern may be an array ref to mean multiple patterns
    $pattern = [ $pattern ] unless ref $pattern;
    my @cmd = (qw(git for-each-ref), @$pattern);
    if (defined $gitdir) {
	@cmd = ('sh','-ec','cd "$1"; shift; exec "$@"','x', $gitdir, @cmd);
    }
    open GFER, "-|", @cmd or confess "$!";
    debugcmd "|", @cmd;
    while (<GFER>) {
	chomp or confess "$_ ?";
	printdebug "|> ", $_, "\n";
	m#^(\w+)\s+(\w+)\s+(refs/[^/]+/(\S+))$# or confess "$_ ?";
	$func->($1,$2,$3,$4);
    }
    $!=0; $?=0; close GFER or confess "$pattern $? $!";
}

sub git_get_ref ($) {
    # => '' if no such ref
    my ($refname) = @_;
    local $_ = $refname;
    s{^refs/}{[r]efs/} or confess "$refname $_ ?";
    return cmdoutput qw(git for-each-ref --format=%(objectname)), $_;
}

sub git_for_each_tag_referring ($$) {
    my ($objreferring, $func) = @_;
    # calls $func->($tagobjid,$refobjid,$fullrefname,$tagname);
    printdebug "git_for_each_tag_referring ",
        ($objreferring // 'UNDEF'),"\n";
    git_for_each_ref('refs/tags', sub {
	my ($tagobjid,$objtype,$fullrefname,$tagname) = @_;
	return unless $objtype eq 'tag';
	my $refobjid = git_rev_parse $tagobjid;
	return unless
	    !defined $objreferring # caller wants them all
	    or $tagobjid eq $objreferring
	    or $refobjid eq $objreferring;
	$func->($tagobjid,$refobjid,$fullrefname,$tagname);
    });
}

sub git_check_unmodified () {
    foreach my $cached (qw(0 1)) {
	my @cmd = qw(git diff --quiet);
	push @cmd, qw(--cached) if $cached;
	push @cmd, qw(HEAD);
	debugcmd "+",@cmd;
	$!=0; $?=-1; system @cmd;
	return if !$?;
	if ($?==256) {
	    fail
		$cached
		? __ "git index contains changes (does not match HEAD)"
		: __ "working tree is dirty (does not match HEAD)";
	} else {
	    failedcmd @cmd;
	}
    }
}

sub upstream_commitish_search ($$) {
    my ($upstream_version, $tried) = @_;
    # todo: at some point maybe use git-deborig to do this
    my @found;
    foreach my $tagpfx ('', 'v', 'upstream/') {
	my $tag = $tagpfx.(dep14_version_mangle $upstream_version);
	my $new_upstream = git_get_ref "refs/tags/$tag";
	push @$tried, $tag;
	push @found, [ $tag, $new_upstream ] if $new_upstream;
    }
    return @{ $found[0] } if @found == 1;
    return ();
}

sub resolve_upstream_version ($$) {
    my ($new_upstream, $upstream_version) = @_;

    my $used = $new_upstream;
    my $message = __ 'using specified upstream commitish';
    if (!defined $new_upstream) {
	my @tried;
	($used, $new_upstream) =
	    upstream_commitish_search $upstream_version, \@tried;
	if (!length $new_upstream) {
	    fail f_
		"Could not determine appropriate upstream commitish.\n".
		" (Tried these tags: %s)\n".
		" Check version, and specify upstream commitish explicitly.",
		"@tried";
	}
	$message = f_ 'using upstream from git tag %s', $used;
    } elsif ($new_upstream =~ m{^refs/tags/($versiontag_re)$}s) {
	$message = f_ 'using upstream from git tag %s', $1;
	$used = $1;
    }	
    $new_upstream = git_rev_parse $new_upstream;

    return ($new_upstream, $used, $message);
    # used is a human-readable idea of what we found
}

sub is_fast_fwd ($$) {
    my ($ancestor,$child) = @_;
    my @cmd = (qw(git merge-base), $ancestor, $child);
    my $mb = cmdoutput_errok @cmd;
    if (defined $mb) {
	return git_rev_parse($mb) eq git_rev_parse($ancestor);
    } else {
	$?==256 or failedcmd @cmd;
	return 0;
    }
}

sub git_reflog_action_msg ($) {
    my ($msg) = @_;
    my $rla = $ENV{GIT_REFLOG_ACTION};
    $msg = "$rla: $msg" if length $rla;
    return $msg;
}

sub git_update_ref_cmd {
    # returns  qw(git update-ref), qw(-m), @_
    # except that message may be modified to honour GIT_REFLOG_ACTION
    my $msg = shift @_;
    $msg = git_reflog_action_msg $msg;
    return qw(git update-ref -m), $msg, @_;
}

sub rm_subdir_cached ($) {
    my ($subdir) = @_;
    runcmd qw(git rm --quiet -rf --cached --ignore-unmatch), $subdir;
}

sub read_tree_subdir ($$) {
    my ($subdir, $new_tree_object) = @_;
    # If $new_tree_object is '', the subtree is deleted.
    confess unless defined $new_tree_object;
    rm_subdir_cached $subdir;
    runcmd qw(git read-tree), "--prefix=$subdir/", $new_tree_object
	if length $new_tree_object;
}

sub read_tree_debian ($) {
    my ($treeish) = @_;
    read_tree_subdir 'debian', "$treeish:debian";
    rm_subdir_cached 'debian/patches';
}

sub read_tree_upstream ($;$$) {
    my ($treeish, $keep_patches, $tree_with_debian) = @_;
    # if $tree_with_debian is supplied, will use that for debian/
    # otherwise will save and restore it.  If $tree_with_debian
    # is '' then debian/ is deleted.
    my $debian =
	defined $tree_with_debian ? "$tree_with_debian:debian"
	: cmdoutput qw(git write-tree --prefix=debian/);
    runcmd qw(git read-tree), $treeish;
    read_tree_subdir 'debian', $debian;
    rm_subdir_cached 'debian/patches' unless $keep_patches;
}

sub changedir ($) {
    my ($newdir) = @_;
    printdebug "CD $newdir\n";
    chdir $newdir or confess "chdir: $newdir: $!";
}

sub rmdir_r ($) {
    my ($dir) = @_;
    # Removes the whole subtree $dir (which need not exist), or dies.
    #
    # We used to use File::Path::remove_tree (via ::rmtree) but its
    # error handling and chmod behaviour is very complex and confusing.
    # For example:
    #   - It chdirs, and then tries to chdir back.
    #     With our $SIG{__WARN__} setting to die, this can, in combination
    #     with eval, cause execution to continue in an unexpected cwd!
    #   - Without the `safe` option it chmods things.  We never want that.
    #   - *With* the `safe` option it appears to silently skip things
    #     it would want to chdir.
    #   - The error handling with the errors option is rather janky.

    # Don't fork/exec rm if we don't have to.
    return unless stat_exists $dir;

    # We don't use runcmd because we want to capture errors from rmdir
    # in $@ so that if we eval a rmdir_r, the right things happen.
    # even cmdoutput_errok is too cooked.
    my @cmd = (qw(rm -rf --), $dir);
    debugcmd '+', @cmd;
    my $child = open P, "-|" // confess $!;
    if (!$child) {
	open STDERR, ">& STDOUT" or die $!;
	exec @cmd or die "exec $cmd[0]: $!";
    }
    $!=0; $?=0;
    my $errs;
    { local $/ = undef; $errs = <P>; }
    confess "$!" if P->error;

    return if close P && !stat_exists $dir;

    chomp $errs;
    $errs =~ s{\n}{; }g;
    $errs ||= 'no error messages';

    die f_ "failed to remove directory tree %s: rm -rf: %s; %s\n",
      $dir, waitstatusmsg, $errs;
}

sub git_slurp_config_src ($) {
    my ($src) = @_;
    # returns $r such that $r->{KEY}[] = VALUE
    my @cmd = (qw(git config -z --get-regexp), "--$src", qw(.*));
    debugcmd "|",@cmd;

    local ($debuglevel) = $debuglevel-2;
    local $/="\0";

    my $r = { };
    open GITS, "-|", @cmd or confess "$!";
    while (<GITS>) {
	chomp or confess;
	printdebug "=> ", (messagequote $_), "\n";
	m/\n/ or confess "$_ ?";
	push @{ $r->{$`} }, $'; #';
    }
    $!=0; $?=0;
    close GITS
	or ($!==0 && $?==256)
	or failedcmd @cmd;
    return $r;
}

sub gdr_ffq_prev_branchinfo ($) {
    my ($symref) = @_;
    # => ('status', "message", [$symref, $ffq_prev, $gdrlast])
    # 'status' may be
    #    branch         message is undef
    #    weird-symref   } no $symref,
    #    notbranch      }  no $ffq_prev
    return ('detached', __ 'detached HEAD') unless defined $symref;
    return ('weird-symref', __ 'HEAD symref is not to refs/')
	unless $symref =~ m{^refs/};
    my $ffq_prev = "refs/$ffq_refprefix/$'";
    my $gdrlast = "refs/$gdrlast_refprefix/$'";
    printdebug "ffq_prev_branchinfo branch current $symref\n";
    return ('branch', undef, $symref, $ffq_prev, $gdrlast);
}

sub parsecontrolfh ($$;$) {
    my ($fh, $desc, $allowsigned) = @_;
    our $dpkgcontrolhash_noissigned;
    my $c;
    for (;;) {
	my %opts = ('name' => $desc);
	$opts{allow_pgp}= $allowsigned || !$dpkgcontrolhash_noissigned;
	$c = Dpkg::Control::Hash->new(%opts);
	$c->parse($fh,$desc) or fail f_ "parsing of %s failed", $desc;
	last if $allowsigned;
	last if $dpkgcontrolhash_noissigned;
	my $issigned= $c->get_option('is_pgp_signed');
	if (!defined $issigned) {
	    $dpkgcontrolhash_noissigned= 1;
	    seek $fh, 0,0 or confess "seek $desc: $!";
	} elsif ($issigned) {
	    fail f_
		"control file %s is (already) PGP-signed. ".
		" Note that dgit push needs to modify the .dsc and then".
		" do the signature itself",
		$desc;
	} else {
	    last;
	}
    }
    return $c;
}

sub parsecontrol {
    my ($file, $desc, $allowsigned) = @_;
    my $fh = new IO::Handle;
    open $fh, '<', $file or fail f_ "open %s (%s): %s", $file, $desc, $!;
    my $c = parsecontrolfh($fh,$desc,$allowsigned);
    $fh->error and confess "$!";
    close $fh;
    return $c;
}

sub parsechangelog {
    # parsechangelog            @dpkg_changelog_args
    # parsechangelog \&cmd_map, @dpkg_changelog_args
    my $c = Dpkg::Control::Hash->new(name => 'parsed changelog');
    my $p = new IO::Handle;
    my $cmd_map = sub { @_; };
    $cmd_map = shift @_ if ref $_[0];
    my @cmd = $cmd_map->(qw(dpkg-parsechangelog), @_);
    open $p, '-|', @cmd or confess "$!";
    $c->parse($p);
    $?=0; $!=0; close $p or failedcmd @cmd;
    return $c;
}

sub getfield ($$) {
    my ($dctrl,$field) = @_;
    my $v = $dctrl->{$field};
    return $v if defined $v;
    fail f_ "missing field %s in %s", $field, $dctrl->get_option('name');
}

sub parsechangelog_loop ($$$) {
    my ($clogcmd, $descbase, $fn) = @_;
    # @$clogcmd is qw(dpkg-parsechangelog ...some...options...)
    # calls $fn->($thisstanza, $desc);
    debugcmd "|",@$clogcmd;
    open CLOGS, "-|", @$clogcmd or confess "$!";
    for (;;) {
	my $stanzatext = do { local $/=""; <CLOGS>; };
	printdebug "clogp stanza ".Dumper($stanzatext) if $debuglevel>1;
	last if !defined $stanzatext;

	my $desc = "$descbase, entry no.$.";
	open my $stanzafh, "<", \$stanzatext or confess;
	my $thisstanza = parsecontrolfh $stanzafh, $desc, 1;

	$fn->($thisstanza, $desc);
    }
    confess "$!" if CLOGS->error;
    close CLOGS or $?==SIGPIPE or failedcmd @$clogcmd;
}	

sub make_commit ($$) {
    my ($parents, $message_paras) = @_;
    my $tree = cmdoutput qw(git write-tree);
    my @cmd = (qw(git commit-tree), $tree);
    push @cmd, qw(-p), $_ foreach @$parents;
    push @cmd, qw(-m), $_ foreach @$message_paras;
    return cmdoutput @cmd;
}

sub hash_commit ($) {
    my ($file) = @_;
    return cmdoutput qw(git hash-object -w -t commit), $file;
}

sub hash_commit_text ($) {
    my ($text) = @_;
    my ($out, $in);
    my @cmd = (qw(git hash-object -w -t commit --stdin));
    debugcmd "|",@cmd;
    print Dumper($text) if $debuglevel > 1;
    my $child = open2($out, $in, @cmd) or confess "$!";
    my $h;
    eval {
	print $in $text or confess "$!";
	close $in or confess "$!";
	$h = <$out>;
	$h =~ m/^\w+$/ or confess;
	$h = $&;
	printdebug "=> $h\n";
    };
    close $out;
    waitpid $child, 0 == $child or confess "$child $!";
    $? and failedcmd @cmd;
    return $h;
}

sub reflog_cache_insert ($$$) {
    my ($ref, $cachekey, $value) = @_;
    # you must call this in $maindir
    # you must have called record_maindir

    # When we no longer need to support squeeze, use --create-reflog
    # instead of this:
    my $parent = $ref; $parent =~ s{/[^/]+$}{};
    ensurepath "$maindir_gitcommon/logs", "$parent";
    my $makelogfh = new IO::File "$maindir_gitcommon/logs/$ref", '>>'
      or confess "$!";

    my $oldcache = git_get_ref $ref;

    if ($oldcache eq $value) {
	my $tree = cmdoutput qw(git rev-parse), "$value:";
	# git update-ref doesn't always update, in this case.  *sigh*
	my $authline = (ucfirst _us()).
	    ' <'._us().'@example.com> 1000000000 +0000';
	my $dummy = hash_commit_text <<ENDU.(__ <<END);
tree $tree
parent $value
author $authline
committer $authline

ENDU
Dummy commit - do not use
END
	runcmd qw(git update-ref -m), _us()." - dummy", $ref, $dummy;
    }
    runcmd qw(git update-ref -m), $cachekey, $ref, $value;
}

sub reflog_cache_lookup ($$) {
    my ($ref, $cachekey) = @_;
    # you may call this in $maindir or in a playtree
    # you must have called record_maindir
    my @cmd = (qw(git log -g), '--pretty=format:%H %gs', $ref);
    debugcmd "|(probably)",@cmd;
    my $child = open GC, "-|";  defined $child or confess "$!";
    if (!$child) {
	chdir $maindir or confess "$!";
	if (!stat "$maindir_gitcommon/logs/$ref") {
	    $! == ENOENT or confess "$!";
	    printdebug ">(no reflog)\n";
	    finish 0;
	}
	exec @cmd; die f_ "exec %s: %s\n", $cmd[0], $!;
    }
    while (<GC>) {
	chomp;
	printdebug ">| ", $_, "\n" if $debuglevel > 1;
	next unless m/^(\w+) (\S.*\S)$/ && $2 eq $cachekey;
	close GC;
	return $1;
    }
    confess "$!" if GC->error;
    failedcmd unless close GC;
    return undef;
}

sub tainted_objects_message ($$$) {
    my ($ti, $override_status, $hinted_dedup) = @_;
    # $override_status:
    #           undef, not overriddeable
    #              '', not overridden
    #   $deliberately, overridden

    my $msg = '';

    my $timeshow = defined $ti->{time}
      ? strftime("%Y-%m-%d %H:%M:%S Z", gmtime $ti->{time})
      : "";

    my $infoshow = length $timeshow && length $ti->{package} ?
      f_ "Taint recorded at time %s for package %s", $timeshow, $ti->{package},
	         : length $timeshow && !length $ti->{package} ?
      f_ "Taint recorded at time %s for any package", $timeshow,
	         : !length $timeshow && length $ti->{package} ?
      f_ "Taint recorded for package %s", $ti->{package},
	         : !length $timeshow && !length $ti->{package} ?
      __ "Taint recorded for any package"
                 : confess;

    $msg .= <<END;

History contains tainted $ti->{gitobjtype} $ti->{gitobjid}
$infoshow
Reason: $ti->{comment}
END

    $msg .=
        !defined $override_status ? __ <<END
Uncorrectable error.  If confused, consult administrator.
END
      : !length $override_status ? __ <<END
Could perhaps be forced using --deliberately.  Consult documentation.
END
      : f_ <<END, $override_status;
Forcing due to %s
END

    my $hint = $ti->{hint};
    if (defined $hint and !$hinted_dedup->{$hint}++) {
	$msg .= $hint;
    }

    return $msg;
}

# ========== playground handling ==========

# terminology:
#
#   $maindir      user's git working tree
#   playground    area in .git/ where we can make files, unpack, etc. etc.
#   playtree      git working tree sharing object store with the user's
#                 inside playground, or identical to it
#
# other globals
#
#   $local_git_cfg    hash of arrays of values: git config from $maindir
#
# expected calling pattern
#
#  firstly
#
#    [record_maindir]
#      must be run in directory containing .git
#      assigns to $maindir if not already set
#      also calls git_slurp_config_src to record git config
#        in $local_git_cfg, unless it's already set
#
#    fresh_playground SUBDIR_PATH_COMPONENTS
#      e.g fresh_playground 'dgit/unpack' ('.git/' is implied)
#      default SUBDIR_PATH_COMPONENTS is playground_subdir
#      calls record_maindir
#      sets up a new playground (destroying any old one)
#      returns playground pathname
#      caller may call multiple times with different subdir paths
#       creating different playgrounds
#
#    ensure_a_playground SUBDIR_PATH_COMPONENTS
#      like fresh_playground except:
#      merely ensures the directory exists; does not delete an existing one
#
#  then can use
#
#    changedir playground
#    changedir $maindir
#
#    playtree_setup
#            # ^ call in some (perhaps trivial) subdir of playground
#
#    rmdir_r playground

# ----- maindir -----

our $local_git_cfg;

sub record_maindir () {
    if (!defined $maindir) {
	$maindir = must_getcwd();
	if (!stat "$maindir/.git") {
	    fail f_ "cannot stat %s/.git: %s", $maindir, $!;
	}
	if (-d _) {
	    # we fall back to this in case we have a pre-worktree
	    # git, which may not know git rev-parse --git-common-dir
	    $maindir_gitdir    = "$maindir/.git";
	    $maindir_gitcommon = "$maindir/.git";
	} else {
	    $maindir_gitdir    = cmdoutput qw(git rev-parse --git-dir);
	    $maindir_gitcommon = cmdoutput qw(git rev-parse --git-common-dir);
	}
    }
    $local_git_cfg //= git_slurp_config_src 'local';
}

# ----- playgrounds -----

sub ensure_a_playground_parent ($) {
    my ($spc) = @_;
    record_maindir();
    $spc = "$maindir_gitdir/$spc";
    my $parent = dirname $spc;
    mkdir $parent or $!==EEXIST or fail f_
	"failed to mkdir playground parent %s: %s", $parent, $!;
    return $spc;
}    

sub ensure_a_playground ($) {
    my ($spc) = @_;
    $spc = ensure_a_playground_parent $spc;
    mkdir $spc or $!==EEXIST or fail f_
	"failed to mkdir a playground %s: %s", $spc, $!;
    return $spc;
}    

sub fresh_playground ($) {
    my ($spc) = @_;
    $spc = ensure_a_playground_parent $spc;
    rmdir_r $spc;
    mkdir $spc or fail f_
	"failed to mkdir the playground %s: %s", $spc, $!;
    return $spc;
}

# ----- playtrees -----

sub playtree_setup () {
    # for use in the playtree
    # $maindir must be set, eg by calling record_maindir or fresh_playground
    # this is confusing: we have
    #   .                   playtree, not a worktree, has .git/, our cwd
    #   $maindir            might be a worktree so
    #   $maindir_gitdir     contains our main working "dgit", HEAD, etc.
    #   $maindir_gitcommon  the shared stuff, including .objects

    # we need to invoke git-playtree-setup via git because
    # there may be config options it needs which are only available
    # to us, sensibly, in @git

    # And, we look for it in @INC too.  This is a bit perverse.
    # We do this because in the Debian packages we want to have
    # a copy of this script in each binary package, rather than
    # making yet another .deb or tangling the dependencies.
    # @INC is conveniently available.
    my $newpath = join ':', +(grep { !m/:/ } @INC),
	          '/usr/share/dgit', $ENV{PATH};
    runcmd qw(env), "PATH=$newpath", @git, qw(playtree-setup .);

    ensuredir '.git/info';
    open GA, "> .git/info/attributes" or confess "$!";
    print GA "* $negate_harmful_gitattrs\n" or confess "$!";
    close GA or confess "$!";

    playtree_write_gbp_conf();
}

sub playtree_write_gbp_conf (;$) {
    my ($ignore_new) = @_;
    $ignore_new //= 'false';
    
    open GC, "> .git/gbp.conf" or confess "$!";
    print GC <<"END" or confess $!;
[pq]
ignore-new = $ignore_new
END
    close GC or confess "$!";
}

1;

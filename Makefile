# dgit
# Integration between git and Debian-style archives
#
# Copyright (C)2013-2018 Ian Jackson
# Copyright (C)2019,2024 Sean Whitton
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

INSTALL=install
INSTALL_DIR=$(INSTALL) -d
INSTALL_PROGRAM=$(INSTALL) -m 755
INSTALL_DATA=$(INSTALL) -m 644

POD2MAN = pod2man --release="Debian Project" --date="dgit+tag2upload team"

prefix?=/usr/local

bindir=$(prefix)/bin
mandir=$(prefix)/share/man
perldir=$(prefix)/share/perl5
man1dir=$(mandir)/man1
man5dir=$(mandir)/man5
man7dir=$(mandir)/man7
infraexamplesdir=$(prefix)/share/doc/dgit-infrastructure/examples
infradebiandir=$(prefix)/share/dgit-infrastructure/debian
txtdocdir=$(prefix)/share/doc/dgit
absurddir=$(prefix)/share/dgit/absurd

PROGRAMS=dgit git-playtree-setup mini-git-tag-fsck tag2upload-obtain-origs
MAN1PAGES=dgit.1

MAN7PAGES=dgit.7				\
	dgit-user.7 dgit-nmu-simple.7		\
	dgit-maint-native.7			\
	dgit-maint-merge.7 dgit-maint-gbp.7	\
	dgit-maint-debrebase.7                  \
	dgit-downstream-dsc.7			\
	dgit-sponsorship.7			\
	dgit-maint-bpo.7

TXTDOCS=README.dsc-import
PERLMODULES= \
	Debian/Dgit.pm \
	Debian/Dgit/Core.pm \
	Debian/Dgit/ExitStatus.pm \
	Debian/Dgit/I18n.pm \
	Debian/Dgit/ProtoConn.pm
ABSURDITIES=git

GDR_PROGRAMS=git-debrebase
GDR_PERLMODULES= \
	Debian/Dgit.pm \
	Debian/Dgit/Core.pm \
	Debian/Dgit/GDR.pm \
	Debian/Dgit/ExitStatus.pm \
	Debian/Dgit/I18n.pm
GDR_MAN1PAGES=git-debrebase.1
GDR_MAN5PAGES=git-debrebase.5

GDP_PROGRAMS=git-debpush git-deborig
GDP_PERLMODULES= \
	Debian/Dgit/Core.pm \
	Debian/Dgit/GDP.pm
GDP_MAN1PAGES=git-debpush.1 git-deborig.1
GDP_MAN5PAGES=tag2upload.5

INFRA_PROGRAMS=dgit-repos-server dgit-ssh-dispatch dgit-mirror-ssh-wrap \
	dgit-repos-policy-debian dgit-repos-admin-debian \
	dgit-repos-policy-trusting dgit-mirror-rsync \
	tag2upload-oracled
INFRA_EXAMPLES=get-dm-txt ssh-wrap drs-cron-wrap get-suites
INFRA_DEBIAN=get-dm-txt tag2upload-builder-rebuild \
	tag2upload-oracle-crontab tag2upload-builder-crontab
INFRA_PERLMODULES= \
	Debian/Dgit.pm \
	Debian/Dgit/Core.pm \
	Debian/Dgit/Infra.pm \
	Debian/Dgit/Policy/Debian.pm \
	Debian/Dgit/ProtoConn.pm

MANPAGES=$(MAN1PAGES) $(MAN5PAGES) $(MAN7PAGES) \
	$(GDR_MAN1PAGES) $(GDR_MAN5PAGES) \
	$(GDP_MAN1PAGES) $(GDP_MAN5PAGES)

all:	$(MANPAGES) $(addprefix substituted/,$(PROGRAMS))

substituted/%:	%
	mkdir -p substituted
	perl -pe 's{\bundef\b}{'\''$(absurddir)'\''} if m/###substituted###/' \
		<$< >$@

install:	installdirs all
	$(INSTALL_PROGRAM) $(addprefix substituted/,$(PROGRAMS)) \
		$(DESTDIR)$(bindir)
	$(INSTALL_PROGRAM) $(addprefix absurd/,$(ABSURDITIES)) \
		$(DESTDIR)$(absurddir)
	$(INSTALL_DATA) $(MAN1PAGES) $(DESTDIR)$(man1dir)
	$(INSTALL_DATA) $(MAN7PAGES) $(DESTDIR)$(man7dir)
	$(INSTALL_DATA) $(TXTDOCS) $(DESTDIR)$(txtdocdir)
	set -e; for m in $(PERLMODULES); do \
		$(INSTALL_DATA) $$m $(DESTDIR)$(perldir)/$${m%/*}; \
	done

installdirs:
	$(INSTALL_DIR) $(DESTDIR)$(bindir) \
		$(DESTDIR)$(man1dir) $(DESTDIR)$(man5dir) \
		$(DESTDIR)$(man7dir) \
		$(DESTDIR)$(txtdocdir) $(DESTDIR)$(absurddir) \
		$(addprefix $(DESTDIR)$(perldir)/, $(dir $(PERLMODULES)))

install-gdp:    installdirs-gdp
	$(INSTALL_PROGRAM) $(GDP_PROGRAMS) $(DESTDIR)$(bindir)
	$(INSTALL_DATA) $(GDP_MAN1PAGES) $(DESTDIR)$(man1dir)
	$(INSTALL_DATA) $(GDP_MAN5PAGES) $(DESTDIR)$(man5dir)
	set -e; for m in $(GDP_PERLMODULES); do \
		$(INSTALL_DATA) $$m $(DESTDIR)$(perldir)/$${m%/*}; \
	done

install-gdr:	installdirs-gdr
	$(INSTALL_PROGRAM) $(GDR_PROGRAMS) $(DESTDIR)$(bindir)
	$(INSTALL_DATA) $(GDR_MAN1PAGES) $(DESTDIR)$(man1dir)
	$(INSTALL_DATA) $(GDR_MAN5PAGES) $(DESTDIR)$(man5dir)
	set -e; for m in $(GDR_PERLMODULES); do \
		$(INSTALL_DATA) $$m $(DESTDIR)$(perldir)/$${m%/*}; \
	done

install-infra:	installdirs-infra
	$(INSTALL_PROGRAM) $(addprefix infra/, $(INFRA_PROGRAMS)) \
		$(DESTDIR)$(bindir)
	$(INSTALL_PROGRAM) $(addprefix infra/, $(INFRA_EXAMPLES)) \
		$(DESTDIR)$(infraexamplesdir)
	$(INSTALL_PROGRAM) $(addprefix infra/, $(INFRA_DEBIAN)) \
		$(DESTDIR)$(infradebiandir)
	set -e; for m in $(INFRA_PERLMODULES); do \
		$(INSTALL_DATA) $$m $(DESTDIR)$(perldir)/$${m%/*}; \
	done

installdirs-gdp:
	$(INSTALL_DIR) $(DESTDIR)$(bindir) \
		$(DESTDIR)$(man1dir) $(DESTDIR)$(man5dir) \
		$(addprefix $(DESTDIR)$(perldir)/, $(dir $(GDR_PERLMODULES)))

installdirs-gdr:
	$(INSTALL_DIR) $(DESTDIR)$(bindir) \
		$(DESTDIR)$(man1dir) $(DESTDIR)$(man5dir) \
		$(addprefix $(DESTDIR)$(perldir)/, $(dir $(GDR_PERLMODULES)))

installdirs-infra:
	$(INSTALL_DIR) $(DESTDIR)$(bindir) \
		$(DESTDIR)$(infraexamplesdir) $(DESTDIR)$(infradebiandir) \
		$(addprefix $(DESTDIR)$(perldir)/, $(dir $(INFRA_PERLMODULES)))

list-manpages:
	@echo $(MANPAGES)

i18n i18n-update:
	$(MAKE) -C po update
	$(MAKE) -C po4a update

# When tests/tests/i18n-po4a-uptodate fails, this target will usually fix it.
i18n-commit:
	set -e; x=$$(git status --porcelain); set -x; test "x$$x" = x
	$(MAKE) i18n-update
	git add po4a/*_[0-9].pot
	git clean -xdff po4a/\*.po
	git commit -a -m 'i18n-commit - autogenerated'

check installcheck:

clean distclean mostlyclean maintainer-clean:
	rm -rf tests/tmp substituted
	set -e; for m in $(MANPAGES); do \
		test -e $$m.pod && rm -f $$m; \
	done

dgit%: dgit%.pod
	m="$(notdir $@)"; $(POD2MAN)				\
		--center=dgit					\
		--name="$${m%.[0-9]}"				\
		--section="$${m##*.}"				\
		$^ $@

%: %.pod
	m="$(notdir $@)"; $(POD2MAN)				\
		--center="$${m%.[0-9]}"				\
		--name="$${m%.[0-9]}"				\
		--section="$${m##*.}"				\
		$^ $@

%.view:	%
	man -l $*

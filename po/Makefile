# dgit message translation machinery
#
# Translators: there is no need to look at this file.  It contains
# complicated machinery which you do not need to understand :-).
# See po/README instead.

# Copyright (C)2018 Ian Jackson
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

# ----- metaprogramming (translators, please ignore all this) -----
#
# We present translators with a single file po/messages.pot containing
# all the messages for the translated programs in dgit.deb and
# git-debrebase.deb.  This also includes the messages from the shared
# perl modules.
#
# But when we make the .debs, we want to ship in each .deb the
# messages for that .deb, only (but including the common parts).
#
# So we generate three intermediate .pots,
#   .{dgit,git-debrebase,common}.pot
# and merge them to make messages.pot.
#
# From the translations we generate two .mo files for each output
# language: {dgit,git-debrebase}.mo -- including the common messages.
#
# To avoid dirtying the tree whenever we do `make install',
# we honour SUPPRESS_PO_UPDATE, to be used like this
#   make install prefix=$(prefix) SUPPRESS_PO_UPDATE=1

all: messages.pot mofiles

include ../i18n-common.make

.%.potfiles:
	$S $e; echo ../$*; $f

.common.potfiles:
	$S $e; find ../Debian -name \*.pm; $f

.%.make: .%.potfiles Makefile part.make
	$S $e; \
	 sed 's/~/$*/g' part.make; \
	 sed "s#^#.$*.pot: #" $<; \
	$f

-include .dgit.make
-include .git-debrebase.make
-include .common.make

POFILES := $(wildcard *.po)
LANGS := $(basename $(POFILES))

MOFILES = $(foreach part,$(filter-out common,$(PARTS)), \
	$(addprefix mo/$(part)_, $(POFILES:.po=.mo)))

messages.pot: $(if $(SUPPRESS_PO_UPDATE),,$(POTS))
	$S msgcat --to-code=UTF-8 $^		>.messages.0.tmp
	$S ( ./remove-potcdate <$@ ||: )	>.messages.1.tmp
	$S ./remove-potcdate <.messages.0.tmp	>.messages.2.tmp
	$S cmp -s .messages.[12].tmp || mv -v .messages.0.tmp $@
	@echo 'Updated $@.'

%.mo: %.po
	$S msgfmt -o $@ $<

XGETTEXT_OPTS += -Lperl -k__ -kf_ -ki_
XGETTEXT_OPTS += --from-code=UTF-8
XGETTEXT_OPTS += --package-name=dgit --package-version=ongoing
# The --package-* avoids this error from make check's `msgfmt -c'
#  warning: header field 'Project-Id-Version' still has the initial default value

%.pot:
	$S TZ=UTC xgettext $(XGETTEXT_OPTS) $^ -o $@.tmp && $f

mofiles: $(MOFILES)
	@echo 'Generated mo/*.mo (binary translated messages) OK.'

install: all
	set -e; for file in $(MOFILES); do \
		lang=$${file#*_}; lang=$${lang%.mo}; \
		part=$${file#mo/}; part=$${part%%_*}; \
		d=$(DESTDIR)$(prefix)/share/locale/$$lang/LC_MESSAGES; \
		install -d $$d; \
		install -m 0644 $$file $$d/$$part.mo; \
	done

clean:
	rm -f .*.make .*.potfiles .*.pot .*.tmp
	rm -rf mo

%.po: $(if $(SUPPRESS_PO_UPDATE),,messages.pot)
	@echo -n "Merging messages.pot and $@ "
	$S if test -f $@; then \
		msgmerge --previous $@ messages.pot -o $@.new; \
	else \
		msgcat --lang=$* messages.pot >$@.new; \
	fi
	$S mv -f $@.new $@
	$S msgfmt -o /dev/null --statistics $@

.PRECIOUS: .%.potfiles

pofiles: $(POFILES)

update: pofiles check

check: $(if $(SUPPRESS_PO_UPDATE),,pofiles)
	$S set -e; for file in $(POFILES); do \
		lang=`echo $$file | sed 's/\.po//'`; \
		printf "$$lang: "; \
		msgfmt -o /dev/null -c -v --statistics $$lang.po;\
	done

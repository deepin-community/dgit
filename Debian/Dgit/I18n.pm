# -*- perl -*-

package Debian::Dgit::I18n;

# This module provides
#    __       a function which is an alias for gettext
#    f_       sprintf wrapper that gettexts the format
#    i_       identify function, but marks string for translation
#
# In perl the sub `_' is a `superglobal', which means there
# is only one of it in the whole program and every reference
# is to the same one.  So it's not really usable in modules.
# Hence __.

use Locale::gettext;

BEGIN {
    use Exporter;
    @ISA = qw(Exporter);
    @EXPORT = qw(__ f_ i_);
}


sub __ ($) { gettext @_; }
sub i_ ($) { $_[0]; }
sub f_ ($$;@) { my $f = shift @_; sprintf +(gettext $f), @_; }

1;

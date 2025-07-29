PARTS += ~
POTS += .~.pot

mo/~.pot: .~.pot .common.pot
	$S mkdir -p mo
	$S msgcat $^ $o

mo/~_%.po: %.po mo/~.pot
	$S cp $*.po $@.tmp
	$S msgmerge --quiet --previous $@.tmp mo/~.pot -o $@.tmp
	$S $f

.PRECIOUS: mo/~.pot mo/~_%.po

# (end of part.make)
# dependencies of .~.pot will follow (from sed)

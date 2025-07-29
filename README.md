dgit & git-debrebase
====================

 * `dgit` - git integration with the Debian archive
 * `git-debrebase` - delta queue rebase tool for Debian packaging

These tools are independent and can be used separately, but they work
well together, and they share a source package and a test suite.

dgit
----

dgit allows you to treat the Debian archive as if it were a git
repository.  Conversely, it allows Debian to publish the source of its
packages as git branches, in a format which is directly usable by
ordinary people.

Documentation: https://manpages.debian.org/testing/dgit

git-debrebase
-------------

git-debrebase is a tool for representing in git, and manpulating,
Debian packages based on upstream source code.

Documentation: https://manpages.debian.org/testing/git-debrebase

Contributing
------------

The source is maintained in git (of course).  The principal git
branch can be found at either of these locations:

 * https://salsa.debian.org/dgit-team/dgit
 * https://www.chiark.greenend.org.uk/ucgi/~ianmdlvl/git/dgit.git/

Merge requests on Salsa are welcome; as are code contributions via the
Debian Bug Tracking System.  If you encounter a bug, please report it
via the Debian BTS.

The package is marked up for message and document translation.  
See po/README which has Notes for Translators.

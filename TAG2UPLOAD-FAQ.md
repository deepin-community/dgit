# tag2upload Frequently Asked Questions

<!--##toc##-->
   * [What is tag2upload anyway and how does it work? ](#what-is-tag2upload-anyway-and-how-does-it-work-)
   * [How much effort will I have to put in to adopt tag2upload?](#how-much-effort-will-i-have-to-put-in-to-adopt-tag2upload)
   * [Which git workflows does tag2upload support?  And which not?](#which-git-workflows-does-tag2upload-support--and-which-not)
   * [What is the relationship between tag2upload & dgit?](#what-is-the-relationship-between-tag2upload--dgit)
   * [How does access control work?  What about Debian Maintainer (DM) uploads?](#how-does-access-control-work--what-about-debian-maintainer-dm-uploads)

## What is tag2upload anyway and how does it work? 

tag2upload will make it possible to upload a package to
Debian, by signing and pushing a simple git tag.

The tag contains a tiny amount of human-readable metadata, which
instructs a robot, running on Debian Project infrastructure, to build
and upload a source package.

Most of tag2upload is already implemented and tested.  We just need
some code to invoke the machinery, and then we can deploy it.

The full design document is here:
<https://salsa.debian.org/dgit-team/dgit/-/raw/archive/debian/11.10/TAG2UPLOAD-DESIGN.txt>

Ian gave a talk on tag2upload at the 2023 Cambridge Minidebconf:
<https://wiki.debian.org/DebianEvents/gb/2023/MiniDebConfCambridge/Jackson>

There's a helpful diagram on the last page of the slides:
<https://wiki.debian.org/DebianEvents/gb/2023/MiniDebConfCambridge/Jackson?action=AttachFile&do=get&target=slides.pdf>


## How much effort will I have to put in to adopt tag2upload?

If your existing workflow is based on upstream git, then very little.
Let's suppose you are using git-buildpackage.  You prepare and test
your upload as normal.  When you are ready to tag, dput and push to
salsa, you instead just type `git debpush`.  That's it.

The only other thing is that the first time will require `git debpush
--gbp` to record that you're using git-buildpackage and not, say,
git-dpm.  Thereafter `git debpush` alone will work, for all uploaders.

git-debpush is deliberately very simple.  It is a hundred times
simpler than both dgit and git-buildpackage.  It isn't likely to fail
in ways that aren't easy to understand for anyone experienced with
uploading directly to ftp-master.

The tag format is simple enough that you can create and push tags
manually, using plain `git tag` and `git push`: refer to the
specification in <https://manpages.debian.org/tag2upload>.

## Which git workflows does tag2upload support?  And which not?

 * git-buildpackage workflows and patches-applied workflows all work.

 * Workflows where only `debian/` is committed to the repository only work if
   the upstream source is present in git (in some other branch).

 * Native packages work.

 * The main exceptions are packages in team monorepos, and packages with
   very large assets that can't be checked into git.  These are not
   supported yet.

tag2upload really shines in a fully-git-based workflow, where you do
all of your Debian work in git, in a git branch which is based on
upstream's signed git tags -- and ignore any upstream tarballs.

One of tag2upload's design principles is that git and the source
package must be equivalent.  So if you use upstream *tarballs* as the
base for your work (and as the `.orig`), there must be a
commit/tag/branch in your repository that contains the full upstream
release, including anything which upstream includes in their tarball
releases but doesn't commit to their own VCS repository, such as
autotools output.  Your packaging branch must be based off this full
upstream release (except for the "bare debian/ directory" workflow).
gbp-importorig can be used to create this tarball import.


## What is the relationship between tag2upload & dgit?

dgit is relevant to the server-side implementation, but you do not
need dgit installed, or to learn dgit, to use `git debpush`.  From an
uploader's perspective, dgit is a server-side implementation detail.

 * dgit is the most mature tool that exists for converting arbitrary
   git trees to Debian source packages.  So tag2upload calls out to
   dgit for that purpose.

 * tag2upload is developed in dgit.git because they are tested using
   the same test suite.

 * tag2upload pushes to dgit.debian.org because that git archive has
   the desired append-only properties, and there's no reason to set up
   a separate git hosting service for t2u.

 * The git tag metadata reuses syntax developed for dgit.


## How does access control work?  What about Debian Maintainer (DM) uploads?

tag2upload implements the same access control policy as the Debian
Archive, based on the keyrings and `dm.txt`.  So tag2upload is usable
precisely by uploading Debian Members (uploading DDs), and by Debian
Maintainers (DMs) for their authorised packages.

The access control on the tag2upload server is a reimplementation.

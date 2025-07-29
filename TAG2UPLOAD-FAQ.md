# tag2upload Frequently Asked Questions

<!--##toc##-->
   * [What is tag2upload anyway and how does it work? ](#what-is-tag2upload-anyway-and-how-does-it-work-)
   * [How much effort will I have to put in to adopt tag2upload?](#how-much-effort-will-i-have-to-put-in-to-adopt-tag2upload)
   * [Which git workflows does tag2upload support?  And which not?](#which-git-workflows-does-tag2upload-support--and-which-not)
   * [What is the relationship between tag2upload & dgit?](#what-is-the-relationship-between-tag2upload--dgit)
   * [Why are we having a GR?  Have other avenues been exhausted?](#why-are-we-having-a-gr--have-other-avenues-been-exhausted)
   * [How about including sha256 checksums of the source package contents in the git tag?](#how-about-including-sha256-checksums-of-the-source-package-contents-in-the-git-tag)
   * [How does access control work?  What about Debian Maintainer (DM) uploads?](#how-does-access-control-work--what-about-debian-maintainer-dm-uploads)
   * [Aren't you demanding that ftpmaster volunteers do work they disagree with?](#arent-you-demanding-that-ftpmaster-volunteers-do-work-they-disagree-with)
   * [I'm not happy voting on an unimplemented design proposal](#im-not-happy-voting-on-an-unimplemented-design-proposal)

## What is tag2upload anyway and how does it work? 

As the GR says, tag2upload will make it possible to upload a package to
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

 * Workflows where only `debian/` is committed to the repository mostly work.

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


## Why are we having a GR?  Have other avenues been exhausted?

tag2upload was originally designed, and mostly implemented, four years
ago in 2019.  ftpmaster declined to allow the deployment of
tag2upload, and some ftpmaster delegates requested major design
changes that we felt would defeat the point.

Since then we have been quietly seeking help behind the scenes, with
multiple DPLs and other prominent members of the project who might've
been able to successfully mediate.  Unfortunately these efforts did
not lead to resolution of the impasse.

The specific changes requested were:

 * The tag2upload server should perform only certain trivial git->dsc
   conversions.

   But this would mean that tag2upload wouldn't work for most Git
   workflows Debian package maintainers actually use, including very
   common git-buildpackage workflows.

 * The tag2upload client should locally compute some sort of tree hash
   over the included files, and include it in the Git tag.

   But this would mean that tag2upload requires running
   Debian-specific tools over the Git tree before uploading, which
   defeats a core design goal of tag2upload.

These points are discussed in more detail in the next section.

On debian-vote this June, we had another extensive discussion with
ftpmaster delegates, and it reached exactly the same conclusion as the
discussion in 2019.

(Constitutionally, as this is a delegate override, only a GR is
appropriate, not the TC.)


## How about including sha256 checksums of the source package contents in the git tag?

This is intended to allow dak to establish a chain of trust from a
signature by the uploader to the *contents* of the .dsc.  Our
understanding of ftpmaster's position is that, with this change,
tag2upload would be acceptable to them.  However, this approach
eliminates much of the point of tag2upload:

With our design, the git tag for an upload is *just* a git tag,
containing a small amount of simple metadata.  You can see an example
(from a talk demo), here:
<https://www.chiark.greenend.org.uk/ucgi/~ianmdlvl/git?p=dgit-test-dummy.git;a=tag;h=refs/tags/debian/1.39>

With the proposed modification, this is no longer true.  Making that
list of the sha256sums is very complicated.  Doing so requires
building the source package (or something very like it) locally, on
the tagger's system.

This is a problem because in the general case, reliably producing
source packages from git is complex, depends on the git workflow in
use, and is highly Debian-specific.  The point of tag2upload is to
move the git-to-dsc conversion from the maintainer's laptop to a
central system, which is more convenient, traceable, reliable, and
secure.

If we adopted this suggestion:

 * git-debpush would have to be much, much more complicated -- as
   complicated as dgit -- and opaque.

 * Only git-debpush would be able to generate the tag.  But we want it
   to be possible for other software to generate it.

 * The conversion from git to source package might still be influenced
   by bugs and anomalies on the uploader's system.

**So, this is the core of the disagreement.** With this modification,
it's no longer "just tag to upload" -- and we feel it's no longer
worthwhile.

Further reading:

 * Sven Mueller summarised it well, here:
   <https://lists.debian.org/debian-vote/2024/06/msg00224.html> (start reading at "In essence:").

 * Russ Allbery wrote a more detailed explanation of objections to the
   suggestion:
   <https://lists.debian.org/debian-vote/2024/06/msg00225.html>

 * Ian Jackson described in detail some cases which show why reliably
   producing source packages from git is so complex:
   <https://lists.debian.org/debian-vote/2024/06/msg00460.html>


## How does access control work?  What about Debian Maintainer (DM) uploads?

tag2upload implements the same access control policy as the Debian
Archive, based on the keyrings and `dm.txt`.  So tag2upload is usable
precisely by uploading Debian Members (uploading DDs), and by Debian
Maintainers (DMs) for their authorised packages.

The access control on the tag2upload server is a reimplementation.  As
a future avenue of development, we would like to include a copy of the
maintainer's signed git tag along with the rest of the upload.

We can't do this already because it would cause dak to reject the
upload.  We hope dak will be modified to accept this additional file,
and then to use it to redo tag2upload's authentication and
authorisation checks on the original signed tag.  This modification is
a good idea, but not required for deployment.


## Aren't you demanding that ftpmaster volunteers do work they disagree with?

No.

We hope this GR will decide that archive.debian.org should extend
enough trust to the tag2upload server for the system to work.  Once
that's decided, then there are deployment strategies that do not
involve *any* work by ftpmaster.

The natural deployment strategy would be for ftpmaster to add a new
keyring that allows uploading only source packages, similar to how
there is a keyring for the binary buildds which allows uploading only
binary packages.  So that would be a small amount of work for
ftpmaster.

But, instead, the tag2upload server's signing key could be certified
as a subkey by an existing key which is already authorised for
uploads.  Or the tag2upload robot could be enrolled in the Debian
keyring as a pseudo-DD.  These deployment strategies aren't as good as
first-class support in dak, but they are OK.

Of course there *are* security improvements, which could be made
before or after deployment, which would involve work by both ftpmaster
and the tag2upload team.  We would encourage and cooperate with such
improvements, but they are not essential.


## I'm not happy voting on an unimplemented design proposal

The core of tag2upload -- the automated tag handler and source package
constructor -- is implemented and tested.  You may have seen it
demo'd, for example in Ian's 2023 Cambridge Minidebconf talk.

The bulk of the remaining implementation work is just the surrounding
framework, which we will work on in detail after discussion with DSA.
It doesn't make sense for us and DSA to do all this work if the
resulting system won't be actually enabled.

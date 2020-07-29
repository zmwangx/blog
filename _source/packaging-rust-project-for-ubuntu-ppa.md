---
title: Packaging a Rust project for Ubuntu PPA
author: Zhiming Wang
date: 2020-07-28
...

<small>*The impatient may [jump a few paragraphs](#impatient) of motivations and introduction.*</small>

Rust compilation is known to be extremely slow, and on top of that cargo isn't really meant to be a general purpose binary package manager, at least not for non-Rust developers,<sidenote id="cargo-not-binary-package-manager">This is of course debatable and potentially divisive, and it's not a hill I'm willing to die on. I'll just point to the official POV laid out in [*The Rust Programming Language*, &sect; 14.4](https://doc.rust-lang.org/book/ch14-04-installing-binaries.html) ([Wayback Machine](https://web.archive.org/web/20200728060910/https://doc.rust-lang.org/book/ch14-04-installing-binaries.html)): *"The cargo install command allows you to install and use binary crates locally. This isn’t intended to replace system packages; it’s meant to be a convenient way for Rust developers to install tools that others have shared on crates.io."* One clarification on my stance: I don't consider pip, npm, etc. to fit the bill of a binary package manager either, although they're often used that way.</sidenote> so as the developer of a non-library Rust project, one should strive to ship compiled binaries to users (including oneself) unless users specifically want to compile from source. Not only that, it's preferable that users be able to upgrade to the latest version during routine system administration without having to manually check for and download new releases.

Of course, it's most convenient if one could convince system packagers to do the work, but new and/or obscure projects may not have that luxury. This post dives into taking matters into your own hands, specifically on Ubuntu, where a [PPA](https://launchpad.net/ubuntu/+ppas) is the most streamlined way to ship third party packages to users.

Unfortunately Debian packaging is complex (and IMO archaic), with myriad files and various competing build systems and workflows; on top of that, docs are scattered and workflow-related docs seem scarce. You'll be in for kind of a shock if you're only familiar with more streamlined systems like Homebrew, MacPorts, or even AUR.<sidenote id="ubuntu-workflow">I'll admit I didn't look into the Ubuntu workflow, partly because I have no interest in learning bzr. I do know [packaging docs](https://packaging.ubuntu.com/html/) are't much better, and if you're building a new package you better stick to [Debian's docs](https://www.debian.org/doc/manuals/maint-guide/).</sidenote> For Rust specifically, there's a reasonably fleshed-out [Debian Rust Packaging Policy](https://wiki.debian.org/Teams/RustPackaging/Policy) and a helper tool [`debcargo`](https://salsa.debian.org/rust-team/debcargo) to assist navigation of Debian's complex packaging process. It requires packaging one crate at a time though (check [`debcargo-conf`](https://salsa.debian.org/rust-team/debcargo-conf)<sidenote id="debcargo-multi-packages">There appears to be a [multi-package expert mode](https://salsa.debian.org/rust-team/debcargo-conf/-/blob/556d49a2c33df9e349ee3e638144ac19522eeae4/README.rst#expert-mode-packaging-multiple-packages), but I believe it's only for updates.</sidenote>), so you most likely don't want to do that in your PPA when you have dozens of dependencies, which is terribly inconvient while carrying the risk of conflicting with distro packages. I also found third party binary packaging helpers like [`cargo-deb`](https://github.com/mmstick/cargo-deb), but Ubuntu PPA requires source packages (that is, `.dsc` instead of `.deb`), so binary packaging tools are out of the question.

I won't expand on how to prepare a Debian-specific source tree here. Please check [Debian New Maintainers' Guide](https://www.debian.org/doc/manuals/maint-guide/). If in doubt you can check a finished example in my [debian-metadata](https://github.com/zmwangx/debian-metadata/tree/master/debian) repository. The rest of this post assumes the basic skeleton of the `debian` directory has been set up, probably with `dh_make(8)`.

<a id="impatient"></a>

The most convenient way (that I know of) to construct a self-contained, workable source package is through a combination of the `cargo vendor` and `cargo build --frozen` commands. `cargo vendor` downloads all dependencies into a `vendor` directory, and `cargo build --frozen` avoids touching the network for dependencies. We also need to instruct cargo to look into the `vendor` directory with a `.cargo/config`:

```toml
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
```

The `vendor` directory can be either fully checked into the `debian` directory, or packed up and only expanded during the build process. The former results in a huge number of files; the latter leads to a cleaner source tree but every update causes a new tarball to be committed, which bloats the repo size when tracked in VCS.

Assuming we pack `vendor` into `vendor.tar.xz`, and store the aforementioned `.cargo/config` in `debian/cargo.config`, here's a basic, working `debian/rules`:

```makefile
%:
	dh $@

override_dh_auto_build:
	mkdir -p .cargo
	cp debian/cargo.config .cargo/config
	tar xJf debian/vendor.tar.xz
	cargo build --release --frozen

override_dh_auto_clean:
	cargo clean
	rm -rf .cargo vendor
```

That's the main differentiator of our Rust package. The rest is filling out other files under `debian` following the Debian guide, specifically [required files](https://www.debian.org/doc/manuals/maint-guide/dreq.en.html) and [other files](https://www.debian.org/doc/manuals/maint-guide/dother.en.html).

One important tip which I overlooked and caused a fair bit of grief: remember to create [`debian/source/format`](https://www.debian.org/doc/manuals/maint-guide/dother.en.html#sourcef) with content

    3.0 (quilt)

to mark the package as non-native.

## Workflow tips for targeting multiple distributions

This part is a general discussion of Debian packaging branching strategy, hence not specific to Rust.

The Debian guide basically stops at packaging for a single `unstable` distribution. Of course, when you're packaging for a Ubuntu PPA, you're likely targeting at least the two recent LTS distributions, which are `bionic` and `focal` at the moment. To update to a new upstream version, it also asks you to copy the `debian` directory into a new unpacked upstream source tree, which is plain barbaric in 2020; apparently we want to use a VCS instead. Unfortunately, tracking `debian` in VCS for multiple distributions is not easy: the distribution is hardcoded into the distribution field of `debian/changelog` (see [`dch(1)`](`https://manpages.debian.org/jessie/devscripts/dch.1.en.html`)), so different distributions cannot possibly share the same source tree without a complex git-flow-esque branching model, complete overkill for merging in upstream changes and adding a changelog entry once in a while. To add insult to injury, different distributions can't even share the same package version as far as I can tell: for instance, there can be only one `foo_1.0.0-ubuntu1.dsc`, which can only point to one `foo_1.0.0-ubuntu1.debian.tar.xz`, which can only be for one distribution. Ubuntu seems to mostly sidestep this problem since they largely don't ship new versions on older distributions, and when they have to they seem to just YOLO it (as an example see [`git_2.20.1-2ubuntu1.19.10.3`](http://archive.ubuntu.com/ubuntu/pool/main/g/git/git_2.20.1-2ubuntu1.19.10.3.dsc)).<sidenote id="yolo-versioning">This is just my impression from inspecting the versioning schemes of a number of popular packages. I'm totally open to corrections.</sidenote> You probably want to keep your package up-to-date on multiple distributions, though.

Debian does have a terse introduction to [packaging with git](https://wiki.debian.org/PackagingWithGit) and a suite of tools `gbp-import-dsc`, `gbp-import-orig`, `gbp-buildpackage`, etc. (manual [here](https://honk.sigxcpu.org/projects/git-buildpackage/manual-html/)) to support the git workflow. I recommend reading these docs, but again they barely touch on the aforementioned multi-distribution problems.

After fighting with the tools for a while, I'll briefly document my recommended workflow, using a package `foo` with versions `1.0.0` and `1.1.0` as my example:

- Prepare the first version of your `debian` directory wherever you want (using `dh_make` for skeleton). Use `1.0.0-1` as the package version and `unstable` as distribution. Use `debuild -sa` to generate both source and binary packages,<sidenote id="-sa">[`-sa`](https://manpages.debian.org/buster/dpkg-dev/dpkg-genchanges.1.en.html) forces generation of source changes, `*_source.changes`, which will be important later when uploading changes to Launchpad, but it's not necessary here. Including the flag for consistency.</sidenote> or `debuild -S -sa` to generate only the source package.<sidenote id="-S">[`-S`](https://manpages.debian.org/buster/dpkg-dev/dpkg-buildpackage.1.en.html) is short for `--build=source`.</sidenote> The source package is `foo_1.0.0-1.dsc`.

  Now import the source package into your new packaging repo:

      gbp import-dsc --sign-tags /path/to/foo-1.0.0-1.dsc

  This should create the `upstream` and `master` branches, and the `upstream/1.0.0` and `debian/1.0.0` tags.

  Alternatively you can follow the [advice here](https://honk.sigxcpu.org/projects/git-buildpackage/manual-html/gbp.import.fromscratch.html) and prepare your first version directly in the packaging repo. The workflow should be similar except you'll need to tag the `debian/1.0.0` release yourself.

- Now we branch off into `ubuntu/focal` and `ubuntu/bionic` branches respectively. On each branch, `debian/changelog` needs to be edited to change two things: the package version `1.0.0-1` should become `1.0.0-focal1`, and the distribution `unstable` should become `focal` on the `ubuntu/focal` branch; similarly on the `ubuntu/bionic` branch. The `1.0.0-focal1` and `1.0.0-bionic1` distinction is IMO the most sensible solution to the aforementioned no-same-package-version-accross-distributions problem. Create tags `ubuntu/1.0.0-focal1` and `ubuntu/1.0.0-bionic1`.

- We build `1.0.0-focal1` and `1.0.0-bionic1` on their respective branches, again using `debuild -sa` or `debuild -S -sa`. You might need to run `debuild -- clean` to clean up generated files after a build. When you're done the following build artifacts should be available in the parent directory:

      foo_1.0.0-bionic1.debian.tar.xz
      foo_1.0.0-bionic1.dsc
      foo_1.0.0-bionic1_source.build
      foo_1.0.0-bionic1_source.buildinfo
      foo_1.0.0-bionic1_source.changes
      foo_1.0.0-focal1.debian.tar.xz
      foo_1.0.0-focal1.dsc
      foo_1.0.0-focal1_source.build
      foo_1.0.0-focal1_source.buildinfo
      foo_1.0.0-focal1_source.changes
      foo_1.0.0.orig.tar.gz

- We upload the packages to PPA:

      dput ppa:<user>/<ppa> foo_1.0.0-bionic1_source.changes foo_1.0.0-focal1_source.changes

- When upgrading to a new upstream version `1.1.0`, first we import the upstream tarball:

      gbp import-orig /path/to/foo-1.1.0.tar.gz

  The path can be a URL here. This will create a commit (with the delta from v1.0.0 to v1.1.0) on the `upstream` branch, tag it as `upstream/1.1.0`, and merge it into the `master` branch.

  Next, we update `debian/vendor.tar.xz` as necessary, and create a `debian/1.1.0-1` release.

  Finally, we switch to the `ubuntu/focal` and `ubuntu/bionic` branches respectively, merge in the upstream and vendor tarball changes, and create `ubuntu/1.1.0-focal1` and `ubuntu/1.1.0-bionic1` respectively, like before.

For a well-known PPA following a similar branching model (but forgoes the `master` branch for Debian `unstable`), see [deadsnakes/python3.8](https://github.com/deadsnakes/python3.8) (using the one-commit-per-upstream-release model recommended here) and [deadsnakes/python3.9-nightly](https://github.com/deadsnakes/python3.9-nightly) (using the full upstream history model, due to the nightly nature).

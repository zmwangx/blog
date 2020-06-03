---
title: The macOS LC_COLLATE hunt
title-html: The macOS <code>LC_COLLATE</code> hunt
subtitle: Or, why does sort(1) order differently on macOS and Linux?
subtitle-html: Or, why does <code>sort(1)</code> order differently on macOS and Linux?
author: Zhiming Wang
date: 2020-06-03
...

Today I noticed something interesting while working with a sorted list of package names: `sort(1)` orders them differently on macOS and Linux (Ubuntu 20.04). A very simple example, with locale set explicitly:

```
(macOS) $ LC_ALL=en_US.UTF-8 sort <<<$'python-dev\npython3-dev'
python-dev
python3-dev

(Linux) $ LC_ALL=en_US.UTF-8 sort <<<$'python-dev\npython3-dev'
python3-dev
python-dev
```

What the hell? Same locale, different order (or technically, collation). This is not even a difference between GNU and BSD userland; coreutils `sort` on macOS produces the same output as `/usr/bin/sort`. (Of course, when `LC_ALL=C` is used, the results are the same, matching the macOS result above, since "`-`" as `0x2D` on the ASCII table comes before "`3`" as `0x33`.) Therefore, the locale itself becomes the prime suspect.

## macOS

`LC_COLLATE` for any locale on macOS is very easy to find: just look under `/usr/share/locale/<locale>`. Somewhat surprisingly, `/usr/share/locale/en_US.UTF-8/LC_COLLATE` is a symlink to `../la_LN.US-ASCII/LC_COLLATE`. The `US-ASCII` part is a giveaway for lack of sophistication, while the unfamiliar language code `la` and unfamiliar country code `LN` gave me pause. Turns out `la` is code for Latin and `LN` isn't really code for anything (I guess they invented it for the Latin script influence sphere)? In fact, if we look a little bit closer, most locales' `LC_COLLATE` are symlinked to `la_LN` dot something (mostly dot `US-ASCII`), which isn't very remarkable once we realize it stands for Latin:<sidenote id="coreutils">`realpath` in the following command is part of GNU coreutils. In fact I'll be liberally using coreutils commands in this article. You can `brew install coreutils` (make sure you read the caveats).</sidenote>

```
$ realpath /usr/share/locale/*/LC_COLLATE | sort | uniq -c | sort -nr
    122 /usr/share/locale/la_LN.US-ASCII/LC_COLLATE
     21 /usr/share/locale/la_LN.ISO8859-1/LC_COLLATE
     20 /usr/share/locale/la_LN.ISO8859-15/LC_COLLATE
      5 /usr/share/locale/la_LN.ISO8859-2/LC_COLLATE
      3 /usr/share/locale/de_DE.ISO8859-15/LC_COLLATE
      3 /usr/share/locale/de_DE.ISO8859-1/LC_COLLATE
      2 /usr/share/locale/is_IS.ISO8859-1/LC_COLLATE
      2 /usr/share/locale/cs_CZ.ISO8859-2/LC_COLLATE
      1 /usr/share/locale/uk_UA.KOI8-U/LC_COLLATE
      1 /usr/share/locale/uk_UA.ISO8859-5/LC_COLLATE
      1 /usr/share/locale/sv_SE.ISO8859-15/LC_COLLATE
      1 /usr/share/locale/sv_SE.ISO8859-1/LC_COLLATE
      1 /usr/share/locale/sr_YU.ISO8859-5/LC_COLLATE
      1 /usr/share/locale/sl_SI.ISO8859-2/LC_COLLATE
      1 /usr/share/locale/ru_RU.KOI8-R/LC_COLLATE
      1 /usr/share/locale/ru_RU.ISO8859-5/LC_COLLATE
      1 /usr/share/locale/ru_RU.CP866/LC_COLLATE
      1 /usr/share/locale/ru_RU.CP1251/LC_COLLATE
      1 /usr/share/locale/pl_PL.ISO8859-2/LC_COLLATE
      1 /usr/share/locale/lt_LT.ISO8859-4/LC_COLLATE
      1 /usr/share/locale/lt_LT.ISO8859-13/LC_COLLATE
      1 /usr/share/locale/la_LN.ISO8859-4/LC_COLLATE
      1 /usr/share/locale/kk_KZ.PT154/LC_COLLATE
      1 /usr/share/locale/is_IS.ISO8859-15/LC_COLLATE
      1 /usr/share/locale/hy_AM.ARMSCII-8/LC_COLLATE
      1 /usr/share/locale/hi_IN.ISCII-DEV/LC_COLLATE
      1 /usr/share/locale/et_EE.ISO8859-15/LC_COLLATE
      1 /usr/share/locale/es_ES.ISO8859-15/LC_COLLATE
      1 /usr/share/locale/es_ES.ISO8859-1/LC_COLLATE
      1 /usr/share/locale/el_GR.ISO8859-7/LC_COLLATE
      1 /usr/share/locale/de_DE-A.ISO8859-1/LC_COLLATE
      1 /usr/share/locale/ca_ES.ISO8859-15/LC_COLLATE
      1 /usr/share/locale/ca_ES.ISO8859-1/LC_COLLATE
      1 /usr/share/locale/bg_BG.CP1251/LC_COLLATE
      1 /usr/share/locale/be_BY.ISO8859-5/LC_COLLATE
      1 /usr/share/locale/be_BY.CP1251/LC_COLLATE
      1 /usr/share/locale/be_BY.CP1131/LC_COLLATE
```

Oddly enough though (until we realize it's just lack of sophistication), many of the outliers are in fact Latin script-based languages, while markedly non-Latin ones are lumped together under the Latin arm:

```
$ realpath /usr/share/locale/{zh_CN,ja_JP,ko_KR}.UTF-8/LC_COLLATE
/usr/share/locale/la_LN.US-ASCII/LC_COLLATE
/usr/share/locale/la_LN.US-ASCII/LC_COLLATE
/usr/share/locale/la_LN.US-ASCII/LC_COLLATE
```

Of course, these locale files are compiled binaries, so it's hard to gleen the collation rules from them (with my untrained eyes). We still need to find the source code.

Looking for OS X / macOS source code is always kind of a pain. Fortunately, searching for `la_LN.US-ASCII site:opensource.apple.com` led me to the [adv_cmds](https://opensource.apple.com/source/adv_cmds/) package, or more precisely, an old version of it. This package contains source code for locale-related commands (among other things) `colldef`, `locale`, `localedef`, and `mklocale`, and until [v118](https://opensource.apple.com/source/adv_cmds/adv_cmds-118/) (from Mac OS X 10.5 era) it contained a `usr-share-locale.tproj` directory with locale definitions in source form.<sidenote id="adv_cmds-118">You can download a tarball from [here](https://opensource.apple.com/tarballs/adv_cmds/adv_cmds-118.tar.gz). They sure don't make it easy to find the link.</sidenote> The collation definitions are in `usr-share-locale.tproj/colldef`, and looking at the list `usr-share-locale.tproj/colldef/*.src` we immediately notice the overlap with the resolved list above. In fact, it's a perfect match save for `de_DE-A.ISO8859-1` in the list above which wasn't present in the OS X 10.5 era source package. And here's the entirety of the `la_LN.US-ASCII` ruleset ([link](https://opensource.apple.com/source/adv_cmds/adv_cmds-118/usr-share-locale.tproj/colldef/la_LN.US-ASCII.src)):

```
# ASCII
#
# $FreeBSD: src/share/colldef/la_LN.US-ASCII.src,v 1.2 1999/08/28 00:59:47 peter Exp $
#
order \
	\x00;...;\xff
```

I'm no expert on [locale definitions](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap07.html) (in fact this doesn't seem to follow the standard, and looks more like `colldef`-specific langauge -- see `man 1 colldef`), but the meaning is crystal clear: just compare the byte values one by one, semantics be damned. Same as the POSIX locale (aka C locale). That explains why `LC_COLLATE=en_US.UTF-8` sorts the same as `LC_COLLATE=C`.

Also, the `README` ([link](https://opensource.apple.com/source/adv_cmds/adv_cmds-118/usr-share-locale.tproj/colldef/README)) for context:

```
$FreeBSD: src/share/colldef/README,v 1.2 2002/04/08 09:28:22 ache Exp $

WARNING: For the compatibility sake try to keep collating table backward
compatible with ASCII, i.e.  add other symbols to the existent ASCII order.
```

The content and timestamps place these source files perfectly in the [FreeBSD 5.0.0 tree](https://github.com/freebsd/freebsd/tree/release/5.0.0/share/colldef). It just so happens to be known that OS X's BSD layer was [synchronized with FreeBSD 5](https://arstechnica.com/gadgets/2003/11/macosx-10-3/3/) back in 10.3 Panther, so the story as told by the source files checks out.

However, do recall `usr-share-locale.tproj` has been long gone from the `adv_cmds` package. Have the rules changed? One simple test:

```
$ colldef -o /dev/stdout usr-share-locale.tproj/colldef/la_LN.US-ASCII.src | sha256sum
9ec9b40c837860a43eb3435d7a9cc8235e66a1a72463d11e7f750500cabb5b78  -

$ sha256sum </usr/share/locale/en_US.UTF-8/LC_COLLATE
9ec9b40c837860a43eb3435d7a9cc8235e66a1a72463d11e7f750500cabb5b78  -
```

Nope, one and the same. The mystery has thus been solved: we owe our most unsophiscated collation rules on macOS to twenty-year-old FreeBSD (which itself has moved on). Well, at least this should be fast.

## Linux

On GNU/Linux, locale programs and data are part of glibc. glibc's `localedef` ([link](https://github.com/bminor/glibc/blob/glibc-2.31/locale/programs/localedef.c)) prefers to write all generated locales to a single archive `$complocaledir/locale-archive`, where `$complocaledir` is `/usr/lib/locale` by default, so one usually can't find a standalone `LC_COLLATE` file for a given locale. In fact, on my Ubuntu 20.04 systems the only non-`locale-archive` oddball is `C.UTF-8`.

Debian does ship the locale definitions in source form, though, in `/usr/share/i18n/locales`, since locales are mostly generated from source via the `locale-gen(8)` wrapper (which is just a very short shell script). Looking into the `LC_COLLATE` section of `/usr/share/i18n/locales/en_US`, we can see it copies `iso14651_t1`, which in turn copies `iso14651_t1_common`, a 85612-line monstrosity solely for defining collation rules per [ISO 14651](https://www.iso.org/standard/68309.html) (entitled *Information technology — International string ordering and comparison — Method for comparing character strings and description of the common template tailorable ordering*).

So there you have it, `python3-dev` is sorted before `python-dev` due to ISO 14651.

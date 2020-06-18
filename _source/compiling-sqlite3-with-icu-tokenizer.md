---
title: Compiling SQLite3 with the ICU tokenizer
author: Zhiming Wang
date: 2019-01-03
...

<div class="epigraph">
> SQLite works great as the database engine for most low to medium traffic websites (which is to say, most websites).
>
> <footer><cite>[Appropriate Uses For SQLite](https://www.sqlite.org/whentouse.html)</cite></footer>
</div>

Today I decided to use SQLite full-text search to power the search of Chinese content in a side project (a Flask and SQLite-powered website). Unfortunately, the `simple`, `porter` and `unicode61` tokenizers are basically useless for Chinese text, and `libsqlite3-dev` as packaged by Debian does not come with the `icu` tokenizer. So I had to compile SQLite3 with ICU myself.

The process is actually simple enough. Note the compile options used by the Debian package are as follows:

```sh
$ sqlite3 <<<'PRAGMA compile_options;'
COMPILER=gcc-7.3.0
ENABLE_COLUMN_METADATA
ENABLE_DBSTAT_VTAB
ENABLE_FTS3
ENABLE_FTS3_PARENTHESIS
ENABLE_FTS3_TOKENIZER
ENABLE_FTS4
ENABLE_FTS5
ENABLE_JSON1
ENABLE_LOAD_EXTENSION
ENABLE_PREUPDATE_HOOK
ENABLE_RTREE
ENABLE_SESSION
ENABLE_STMTVTAB
ENABLE_UNKNOWN_SQL_FUNCTION
ENABLE_UNLOCK_NOTIFY
ENABLE_UPDATE_DELETE_LIMIT
HAVE_ISNAN
LIKE_DOESNT_MATCH_BLOBS
MAX_SCHEMA_RETRY=25
MAX_VARIABLE_NUMBER=250000
OMIT_LOOKASIDE
SECURE_DELETE
SOUNDEX
THREADSAFE=1
```

One could also obtain the list of options from `debian/rules` in the source package. I was going to overwrite the Debian package and didn't want to screw up the myriad SQLite3 reverse dependencies, so I was careful to preserve these options. Of course, the option we want to add is `ENABLE_ICU`.

To prepare for the dependencies, we simply need

```sh
$ apt build-dep -y libsqlite3-dev
$ apt install -y libicu-dev pkg-config
```

Next we download SQLite3 source tarball from [the official download page](https://www.sqlite.org/download.html), unpack and configure as follows:

```sh
export CFLAGS="\
-O2 -fno-strict-aliasing \
-DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_COLUMN_METADATA \
-DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS \
-DSQLITE_ENABLE_RTREE=1 -DSQLITE_SOUNDEX=1 \
-DSQLITE_ENABLE_UNLOCK_NOTIFY \
-DSQLITE_OMIT_LOOKASIDE=1 -DSQLITE_ENABLE_DBSTAT_VTAB \
-DSQLITE_ENABLE_UPDATE_DELETE_LIMIT=1 \
-DSQLITE_ENABLE_LOAD_EXTENSION \
-DSQLITE_ENABLE_JSON1 \
-DSQLITE_LIKE_DOESNT_MATCH_BLOBS \
-DSQLITE_THREADSAFE=1 \
-DSQLITE_ENABLE_FTS3_TOKENIZER=1 \
-DSQLITE_MAX_SCHEMA_RETRY=25 \
-DSQLITE_ENABLE_PREUPDATE_HOOK \
-DSQLITE_ENABLE_SESSION \
-DSQLITE_ENABLE_STMTVTAB \
-DSQLITE_MAX_VARIABLE_NUMBER=250000 \
-DSQLITE_ENABLE_ICU"
export LDFLAGS="$(pkg-config --libs icu-i18n)"
./configure --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu
```

Again, this build is configured to overwrite the Debian package; use a different `--prefix` (as well as `--libdir`) to avoid that. What follows is the standard `make` and `make install`.

The moment of truth:

```sql
$ sqlite3 /tmp/test.db
SQLite version 3.26.0 2018-12-01 12:34:55
Enter ".help" for usage hints.
sqlite> CREATE VIRTUAL TABLE text USING fts4(tokenize=icu zh_CN);
sqlite> INSERT INTO text VALUES ('汉语，又称中文、华语、唐话'), ('汉字是汉语的文字书写系统');
sqlite> SELECT * FROM text WHERE text MATCH '汉语';
汉语，又称中文、华语、唐话
汉字是汉语的文字书写系统
sqlite> SELECT * FROM text WHERE text MATCH '文字';
汉字是汉语的文字书写系统
sqlite> .exit
```

On macOS, SQLite3 with ICU tokenizer support can be easily<sidenote id="homebrew-easy">Guess I should say it used to be easy, until options are ruined by [politics](https://github.com/Homebrew/homebrew-core/issues/31510).</sidenote> built with Homebrew; see my PR [Homebrew/homebrew-core#35674](https://github.com/Homebrew/homebrew-core/pull/35674). The command should be

```sh
$ brew install sqlite --with-icu4c --with-fts
```

---

*Update (2020-06-18)*: Here's a snippet you can drop into your `Dockerfile`:

```dockerfile
ARG SQLITE_RELEASE=3320100
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    curl \
    libicu-dev \
    libtool \
    make \
    pkg-config \
    redis-server \
    && mkdir ../sqlite3 && cd ../sqlite3 \
    && curl -O https://www.sqlite.org/2020/sqlite-autoconf-${SQLITE_RELEASE}.tar.gz \
    && tar xf sqlite-autoconf-${SQLITE_RELEASE}.tar.gz \
    && cd sqlite-autoconf-${SQLITE_RELEASE} \
    && CFLAGS="\
    -O2 -fno-strict-aliasing \
    -DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_COLUMN_METADATA \
    -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS \
    -DSQLITE_ENABLE_RTREE=1 -DSQLITE_SOUNDEX=1 \
    -DSQLITE_ENABLE_UNLOCK_NOTIFY \
    -DSQLITE_OMIT_LOOKASIDE=1 -DSQLITE_ENABLE_DBSTAT_VTAB \
    -DSQLITE_ENABLE_UPDATE_DELETE_LIMIT=1 \
    -DSQLITE_ENABLE_LOAD_EXTENSION \
    -DSQLITE_ENABLE_JSON1 \
    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS \
    -DSQLITE_THREADSAFE=1 \
    -DSQLITE_ENABLE_FTS3_TOKENIZER=1 \
    -DSQLITE_MAX_SCHEMA_RETRY=25 \
    -DSQLITE_ENABLE_PREUPDATE_HOOK \
    -DSQLITE_ENABLE_SESSION \
    -DSQLITE_ENABLE_STMTVTAB \
    -DSQLITE_MAX_VARIABLE_NUMBER=250000 \
    -DSQLITE_ENABLE_ICU" \
    LDFLAGS="$(pkg-config --libs icu-i18n)" \
    ./configure --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu \
    && make && make install \
    && apt-get purge -y --auto-remove \
    autoconf \
    automake \
    curl \
    libtool \
    make \
    pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && cd /usr/src/app \
    && rm -rf ../sqlite3
```

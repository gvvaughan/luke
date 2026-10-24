---
layout: default
---
# LUKE

[Luke] is a lightweight, self-bootstrapping build utility for [LuaJIT]
and [Lua] 5.1 through 5.5.  It builds Lua and C modules, scripts and
programs, probing the host system for the headers, functions and
libraries they need, from a `lukefile` written in the same style as a
[LuaRocks] rockspec:

 * one file to copy into your project, with no dependencies but Lua
   ([installation](#1-installation))
 * a [command line](#2-command-line) for building and installing
   everything, or just the parts you name
 * modules, scripts, programs and generated files described in a
   [lukefile](#3-the-lukefile)
 * [variables and templates](#4-variables-and-templates) to keep
   version strings and paths in sync
 * [platform-specific](#5-platforms) settings, and Autotools-style
   [build-time probes](#6-build-time-probes)
 * easy to drive [from a rockspec](#7-rockspecs)
 * [releases](#8-releases) cut with one command, which also publish
   your manual to GitHub Pages
 * a [reference](#9-lukefile-reference) of every lukefile key

Luke grew out of replacing Autotools in [lyaml] and [luaposix], without
needing Perl and M4 on the developer's machine, or carrying a 500k
shell script in the distribution.


## 1. Installation

Copy `build-aux/luke` from the [Luke] repository into your project.
It is a single, minified Lua script with everything it needs, so there
is nothing else to install, and nothing for your users to install
either.

The `luke` rock installs the same file as the `luke` command, so that
you can run it, or copy it into your project, without a clone of the
repository:

    luarocks install luke
    cp "$(luarocks show --rock-dir luke)/bin/luke" build-aux/luke

Luke builds that file from its own sources, with its own `lukefile`.
If you change those sources, run `./luke` in the Luke source tree to
regenerate `build-aux/luke`.


## 2. Command Line

{% highlight bash %}
    build-aux/luke [OPTION]... [VARIABLE=VALUE]... [TARGET]...
{% endhighlight %}

Luke reads `lukefile` from the current directory, and builds every
module, script, program and generated file it describes.  Name one or
more targets to build only those:

{% highlight bash %}
    build-aux/luke posix.time posix.unistd
{% endhighlight %}

A target names every module, script, program and generated file with
that name.  Three targets are special: `all` builds everything, and is
the default; `install` copies everything already built to its
installation directory, except generated files; and `release` cuts a
[release](#8-releases).  With other targets, `install` installs only
those:

{% highlight bash %}
    build-aux/luke
    build-aux/luke PREFIX=/opt/lua install
    build-aux/luke PREFIX=/opt/lua posix.time install
    build-aux/luke release version=1.2
{% endhighlight %}

Each `VARIABLE=VALUE` argument sets a [variable](#4-variables-and-templates),
overriding the same variable in `lukefile`, the environment, or Luke's
defaults.

The options are:

    --help        print help, then exit
    --version     print version number, then exit
    --dry-run     print the commands, without running them
    --file=FILE   use FILE instead of lukefile
    --value=NAME  print the value of variable NAME, then exit
    --quiet       without any output
    --verbose     provide more progress output, such as probe results

Even with `--quiet`, Luke shows any command that fails, along with its
error output.

With `--dry-run`, Luke still runs its probes, so that it prints the
commands that it would run for any target, but it runs none of them,
and fills no templates.


## 3. The lukefile

A `lukefile` is a Lua file that sets a few global variables, much like a
rockspec.  A minimal one for a pure Lua project is:

{% highlight lua %}
    luke_format = 0

    package = 'stack'
    version = '$USER/$gitref'

    modules = {
       {['stack']       = 'lib/stack/init.lua'},
       {['stack.utils'] = 'lib/stack/utils.lua'},
    }
{% endhighlight %}

`package` and `version` name the project, and are available to
templates as `@package@` and `@version@` (see
[Templates](#43-templates)).  `luke_format`, `package`, `version` and a
`modules` table are required.

`luke_format`, like a rockspec's `rockspec_format`, names the syntax
the lukefile is written in.  It is a whole number, which goes up by
one with each incompatible change to the syntax, so each Luke reads
only its own format, which is 0 for now.  For any other format, Luke
stops with a diagnostic before reading the rest of the file, saying
whether it needs a newer or an older Luke, rather than diagnosing
syntax it doesn't know.  A lukefile without one is for Luke 0.4 or
earlier, whose syntax format 0 replaces.

### 3.1. Modules

Like the rockspec `builtin` backend, `modules` maps each module name to
its source, but as a list of pair tables that map each name to its
source.  Luke builds and installs modules in the order written.
Luke diagnoses a module name used as a top-level key of the `modules`
table, or a module name written twice, as a syntax error.

A Lua module is installed beneath `$INST_LUADIR`, and a C module is
compiled to `$objdir/<name>.$LIB_EXTENSION` and then installed
beneath `$INST_LIBDIR`.

A module made from several C sources, or that needs extra compiler
or linker settings, takes a full table in place of a single source
string:

{% highlight lua %}{% raw %}
    modules = {
       {['posix.sys.socket'] = {
          defines   = {{HAVE_NET_IF_H = {checkheader='net/if.h', include='sys/socket.h'}}},
          incdirs   = {'ext/include'},
          libdirs   = {'/opt/local/lib'},
          libraries = {{checksymbol='socket', library='socket'}},
          sources   = {'ext/posix/sys/socket.c'},
       }},
    }
{% endraw %}{% endhighlight %}

Like the rockspec `defines` array, `defines` is a list of macro
definitions, which Luke passes to the compiler in the order written.
Each is a rockspec style string, `'HAVE_FOO'` or `'HAVE_FOO=value'`, or
a table that pairs one macro name with its value, `{HAVE_FOO = value}`.
A value of `1` adds `-DHAVE_FOO`, and any other value adds
`-DHAVE_FOO=<value>`, quoted for the shell.  The value in a table can
also be a [build-time probe](#6-build-time-probes), as can an entry in
`libraries`.  Luke diagnoses a macro defined more than once in the same
list.

### 3.2. Scripts

Like the rockspec `build.install.bin` table, an `install.bin` table maps
the name of each script to install to its source, but as a list, like
`modules`, of tables that each pair one name with its source:

{% highlight lua %}
    install = {
       bin = {
          {specl = 'bin/specl'},
       },
    }
{% endhighlight %}

Luke fills the [template](#43-templates) of a source whose name ends in
`.in`, makes every listed script executable, and `luke install` copies
each to its name beneath `$INST_BINDIR`, all in the order written.  A
source on its own is named for itself, without its directory or any
`.in` suffix.

A top-level `bin` table works the same way, for scripts that are only
for use in the source tree, and are never installed, such as a wrapper
that runs a program with the uninstalled modules:

{% highlight lua %}
    bin = {
       'specl.in',
    }
{% endhighlight %}

### 3.3. Programs

An entry in `install.bin` or `bin` that pairs a name with a table is a
rule for building a program from several `sources`, with the same
`defines`, `incdirs`, `libdirs`, `libraries` and probes as a module.
Without a `command`, Luke compiles and links its C sources:

{% highlight lua %}
    install = {
       bin = {
          {mytool = {
             sources   = {'src/main.c', 'src/util.c'},
             libraries = {'m'},
          }},
       },
    }
{% endhighlight %}

Otherwise, Luke runs `command` after filling the template of any `.in`
source, with `$sources` set to the filled source paths, `$target` to the
program to write, and each `env` variable exported.  This is how Luke
builds its own `build-aux/luke`:

{% highlight lua %}
    bin = {
       {['build-aux/luke'] = {
          command = '$LUA build-aux/smush $sources > $target',
          env     = {LUA_PATH = '$abs_top_srcdir/lib/?.lua;;'},
          sources = {'lib/luke/init.lua', 'lib/luke/version.lua.in'},
       }},
    }
{% endhighlight %}

An installable program is built as `$objdir/<name>`, and an in-tree
program at the path given as its name.  Either way, Luke makes it
executable, and `luke <name>` rebuilds it.  A table with `sources` is
the rules for a program without a name, so write a script or program
named `sources` as `{['./sources'] = ...}`.

### 3.4. Generated Files

A top-level `files` list works like `bin`, for files that are made
during the build, but are neither executable nor installed, such as a
man page made from a script's `--help` output.  Each entry pairs the
path to build with a template, or with a rule with a `command` and its
`sources`.  A template on its own is built at its own path, without the
`.in` suffix.  Luke builds every script in `bin` and `install.bin`
first, so that a rule can run them, and then each file in the order
written:

{% highlight lua %}
    variables = {
       HELP2MAN = {checkprog='HELP2MAN', progs={'help2man', 'true'}},
    }

    files = {
       'doc/index.md.in',
       {['doc/specl.1'] = {
          command = '$HELP2MAN --output=$target --no-info ./specl',
          sources = 'specl.in',
       }},
    }
{% endhighlight %}

`luke release` commits every generated file to the release branch.
Luke runs every rule when it builds, so to build a release without the
tools that made them, find each tool with a `checkprog`
[probe](#6-build-time-probes) that falls back to `true`, as above: a
build without `help2man` then leaves the committed man page alone.

### 3.5. Settings for Every Module

A top-level `defines` list adds its definitions to every C compilation,
before those of each module, which can redefine them, and top-level
`incdirs`, `libdirs` and `libraries` arrays add their directories and
libraries, in addition to the settings of each module:

{% highlight lua %}
    defines = {
       {PACKAGE = '"$package"'},
       {VERSION = '"$version"'},
       'NDEBUG',
    }

    incdirs = {
       'ext/include',
       '$LUA_INCDIR',
    }
{% endhighlight %}

An `external_dependencies` list names libraries that every module
needs, like `modules`, as tables that each pair a name with its
settings.  For each one, in the order written, Luke adds
`$<NAME>_INCDIR` and `$<NAME>_LIBDIR` to the compiler and linker search
paths, defaulting to the `include` and `lib` directories beneath
`$<NAME>_DIR` (`/usr` unless you set it), and links with the library it
finds:

{% highlight lua %}
    external_dependencies = {
       {YAML = {
          library = {checksymbol='yaml_document_initialize', library='yaml'},
       }},
    }
{% endhighlight %}

{% highlight bash %}
    build-aux/luke YAML_DIR=/opt/homebrew
{% endhighlight %}

### 3.6. LDocs

An `ldocs` entry names an [LDoc] configuration file, which may be a
template, and Luke runs it after building every module:

{% highlight lua %}
    ldocs = 'build-aux/config.ld.in'
{% endhighlight %}

{% highlight bash %}
    $LDOC -c build-aux/config.ld .
{% endhighlight %}

If `LDOC` is not set, Luke looks for `ldoc` on your `PATH`, and quietly
skips the documentation if it is not installed.


## 4. Variables and Templates

### 4.1. Variables

Wherever a string in `lukefile` contains `$NAME`, Luke replaces it with
the value of variable `NAME`, looking first on the command line, then
in the lukefile `variables` table, then in Luke's defaults, and finally
in the environment:

{% highlight lua %}
    variables = {
       INST_LUADIR = '$PREFIX/share/lua',
    }
{% endhighlight %}

A variable can also be a [build-time probe](#6-build-time-probes),
such as a `checkprog` that finds a program, which commands then see
as the probe's result.

Use `--value` to see what Luke makes of one:

{% highlight bash %}
    $ build-aux/luke --value=INST_LUADIR
    INST_LUADIR='/usr/local/share/lua/5.4'
{% endhighlight %}

The defaults, most of which LuaRocks passes on the command line when it
runs Luke (see [Rockspecs](#7-rockspecs)), are:

| Variable        | Default                                     |
|-----------------|---------------------------------------------|
| `PREFIX`        | `/usr/local`                                |
| `INST_BINDIR`   | `$PREFIX/bin`                               |
| `INST_LIBDIR`   | `$PREFIX/lib/lua/$LUA_VERSION`              |
| `INST_LUADIR`   | `$PREFIX/share/lua/$LUA_VERSION`            |
| `LUA`           | `lua`                                       |
| `LUA_VERSION`   | the version of the Lua running Luke         |
| `LUA_DIR`       | `/usr`                                      |
| `LUA_BINDIR`    | `$LUA_DIR/bin`                              |
| `LUA_INCDIR`    | `$LUA_DIR/include/lua$LUA_VERSION`          |
| `LUA_LIBDIR`    | `$LUA_DIR/lib`                              |
| `CC`            | the first of `cc`, `gcc` or `clang` found   |
| `CFLAGS`        | `-O2`                                       |
| `LIBFLAG`       | `-shared -fPIC`, or a bundle on macOS       |
| `LIB_EXTENSION` | `so`                                        |
| `OBJ_EXTENSION` | `o`                                         |
| `INSTALL`       | `cp`                                        |
| `MAKEDIRS`      | `mkdir -p`                                  |
| `CHMOD`         | `chmod`                                     |
| `objdir`        | the [platform](#5-platforms) name, such as `linux` |

The compile command also uses `CPPFLAGS`, `LDFLAGS`, `LIBS` and
`PKGFLAGS`, if you set them.

### 4.2. Built-in Values

Luke also sets:

 * `package` and `version`, from `lukefile`;
 * `LUA_VERSION`, the version of the Lua running Luke, which is also a
   variable with that default (`LUAVERSION` is an older name for it);
 * `gitref`, the abbreviated hash of the commit checked out in the
   current directory, or the empty string outside a git working tree;
 * `abs_top_srcdir`, the absolute path of the current directory.

Setting `version = '$USER/$gitref'` makes every unreleased build
identify who built it, and from which commit, while a release can still
pass `version=X.Y` on the command line.

### 4.3. Templates

Wherever `lukefile` names a source file ending in `.in`, Luke copies it
to the same path without the `.in`, replacing each `@NAME@` with the
value of `NAME` from the command line, the lukefile `substitute` table,
`package`, `version` and the built-in values above, or the environment.
This keeps a version string in sync, for example:

{% highlight lua %}
    -- lib/stack/version.lua.in
    return 'stack @version@'
{% endhighlight %}

{% highlight lua %}
    modules = {
       {['stack.version'] = 'lib/stack/version.lua.in'},
    }
{% endhighlight %}


## 5. Platforms

Any table in `lukefile` can contain a `platforms` table with settings
for particular platforms.  Luke uses the settings for the most specific
platform it is running on, or else the remaining settings in the
`platforms` table as defaults:

{% highlight lua %}
    defines = {
       'NDEBUG',
       platforms = {
          linux  = {'_DEFAULT_SOURCE'},
          macosx = {'_DARWIN_C_SOURCE'},
          '_POSIX_C_SOURCE=200809L',
       },
    }
{% endhighlight %}

The list entries of each platform table that applies follow those of
the list itself, least specific first, so on macOS the list above is
`NDEBUG`, then `_DARWIN_C_SOURCE`.  A setting for a more specific
platform replaces the same setting for a less specific one, or for no
platform, and a macro that a more specific platform defines again is
redefined where it was first defined.  Luke diagnoses errors in the
`defines` table for all platforms, not just the one being built.

Luke recognizes these platforms, from the output of `uname -s`, most
specific first:

| `uname -s`   | Platforms                       |
|--------------|---------------------------------|
| `AIX`        | `aix`, `unix`                   |
| `Darwin`     | `macosx`, `bsd`, `unix`         |
| `FreeBSD`    | `freebsd`, `bsd`, `unix`        |
| `NetBSD`     | `netbsd`, `bsd`, `unix`         |
| `OpenBSD`    | `openbsd`, `bsd`, `unix`        |
| `Linux`      | `linux`, `unix`                 |
| `SunOS`      | `solaris`, `unix`               |
| `Haiku`      | `haiku`, `unix`                 |
| `CYGWIN*`    | `cygwin`, `unix`                |
| `MSYS*`      | `msys`, `cygwin`, `unix`        |
| `MINGW*`     | `mingw32`, `win32`, `windows`   |
| `Windows*`   | `win32`, `windows`              |
| `QNX`, `procnto*` | `qnx`                      |

Anything else is treated as `unix`.


## 6. Build-Time Probes

Wherever a value in `defines`, `libraries` or `variables` can go, you
can put a probe, a table that Luke runs to compute the value on the build
machine.  Whatever order you write them in, Luke always runs the kinds
of probe in this order, and probes of the same kind in the order they
are written:

1. **checkprog**: `{checkprog='SH', progs={'dash', 'ash', 'sh'}}`
   finds the first of `progs` on your `PATH`, and returns its path.

2. **checkheader**: `{checkheader='net/if.h', include='sys/socket.h'}`
   returns `1` if a short C program that includes the header compiles,
   otherwise `0`.  An optional `include` names another header that must
   be included first, or `includes` an array of them.

3. **checkdecl**: `{checkdecl='fdatasync', include='unistd.h'}` returns
   `1` if the headers named by `include` (or `includes`) declare the
   function, or define a macro of that name, otherwise `0`.

4. **checksymbol**: `{checksymbol='crypt', library='crypt'}` returns
   the `library` if linking with it is necessary to resolve the symbol,
   or nothing if the symbol resolves without it.  A `libraries` array
   tries several libraries in turn.  An optional `include` (or
   `includes`) names headers to include, and an `ifdef` key marks the
   symbol as unsupported when the named macro is not defined.

5. **checkfunc**: `{checkfunc='crypt'}` returns `1` if the function is
   available, otherwise `0`.

6. **checkmember**: `{checkmember='struct tm.tm_gmtoff', include='time.h'}`
   returns `1` if the structure has the member, otherwise `0`.  An
   optional `include` (or `includes`) names the headers that define the
   structure.

Because of that ordering, this module:

{% highlight lua %}
    {['crypt'] = {
       defines = {
          {HAVE_CRYPT   = {checkfunc='crypt'}},
          {HAVE_CRYPT_H = {checkheader='crypt.h'}},
       },
       libraries = {
          {checksymbol='crypt', library='crypt'},
       },
       sources = 'crypt.c',
    }},
{% endhighlight %}

...might build like this with `--verbose`:

    checking for C compiler... cc
    checking whether cc works... yes
    checking for crypt.h... no
    checking for library containing crypt... none required
    checking for crypt... yes
    cc -O2 -shared -fPIC -DHAVE_CRYPT_H=0 -DHAVE_CRYPT crypt.c -o linux/crypt.so

...given `crypt.c` was written with:

{% highlight c %}
    #if HAVE_CRYPT_H
    #  include <crypt.h>
    #endif

    #if defined HAVE_CRYPT
    static int Pcrypt(lua_State *L)
    {
        ...
        return pushresult(crypt(str, salt));
    }
    #endif
{% endhighlight %}


## 7. Rockspecs

To build with Luke from a rockspec, use the `command` backend, and pass
along the settings LuaRocks has chosen.  [luaposix] does it like this:

{% highlight lua %}
    build = {
       type = 'command',
       build_command = '$(LUA) build-aux/luke'
          .. ' package="' .. package .. '"'
          .. ' version="' .. _MODREV .. '"'
          .. ' PREFIX="$(PREFIX)"'
          .. ' LUA="$(LUA)"'
          .. ' LUA_INCDIR="$(LUA_INCDIR)"'
          .. ' CC="$(CC)"'
          .. ' LD="$(LD)"'
          .. ' CFLAGS="$(CFLAGS)"'
          .. ' LIBFLAG="$(LIBFLAG)"'
          .. ' LIB_EXTENSION="$(LIB_EXTENSION)"'
          .. ' OBJ_EXTENSION="$(OBJ_EXTENSION)"'
          .. ' INST_LIBDIR="$(LIBDIR)"'
          .. ' INST_LUADIR="$(LUADIR)"'
          ,
       install_command = '$(LUA) build-aux/luke install --quiet'
          .. ' INST_LIBDIR="$(LIBDIR)"'
          .. ' INST_LUADIR="$(LUADIR)"'
          ,
    }
{% endhighlight %}

A release commits its LDocs (see [Releases](#8-releases)), so its
rockspec need not build them again, which would fail with an `ldoc`
that doesn't work with the Lua it is installed for.  Setting `LDOC` to
`true` on the command line skips them, and `build_dependencies`, from
rockspec format 3.0, gives development builds an `ldoc` to run:

{% highlight lua %}
    if _MODREV == 'dev' then
       build_dependencies = {'ldoc'}
    else
       build.build_command = build.build_command .. ' LDOC=true'
    end
{% endhighlight %}

For now, that repeats some of the `lukefile` in the rockspec.  One day,
Luke may read the extra syntax it needs directly from your rockspec,
so that a separate `lukefile` is no longer necessary.


## 8. Releases

`luke release version=X.Y` cuts release X.Y (or X or X.Y.Z) in your git
working tree, as set out in the lukefile `release` table.  Luke's own
is:

{% highlight lua %}
    release = {
       news         = 'NEWS.md',
       rockspec     = 'luke-dev-1.rockspec',
       replacements = {
          {['README.md'] = {
             {['?branch=master'] = '?branch=release-v@version@'},
          }},
       },
       ['gh-pages'] = {
          {['index.md'] = 'doc/luke.md'},
          '_config.yml.in',
       },
    }
{% endhighlight %}

Every key is optional, and Luke skips the steps for any that are
missing.  `release` cannot be combined with other targets, and Luke
pushes nothing: it prints the commands to publish the release when it
is done.  If a step fails, Luke prints the commands that undo what the
release has done so far instead, so that its checks pass again.  With
`--dry-run`, Luke still makes its checks, but then only prints the
commands it would run and the files it would write.

### 8.1. Checks

Luke checks, before changing anything, that:

 * the working tree is clean, and a branch is checked out, such as
   `master`, `main` or a maintenance branch, and is up to date with
   origin, which Luke fetches;
 * there is no `release-vX.Y` branch or `vX.Y` tag yet (for a rock other
   than the `package`, `release-NAME-vX.Y` and `NAME-vX.Y`);
 * the first `##` header in `news` is a placeholder for the next
   release, with `?.?` in place of its version, and has news under it;
 * `news` has no release X.Y yet;
 * `rockspec` is a development rockspec, named like `luke-dev-1.rockspec`,
   whose first line sets `_MODREV`:

{% highlight lua %}
    local _MODREV, _SPECREV = 'dev', '-1'
{% endhighlight %}

 * with `check_dependencies = true`, LuaRocks (`LUAROCKS`, or else
   `luarocks`) has every dependency of `rockspec` installed for the Lua
   that runs Luke; Luke lists any that are missing, and installs none;
 * each file in `replacements` exists, and has each text it replaces,
   after the replacements written before it (see
   [Replacements](#84-replacements));
 * each branch that the release copies files to, such as `gh-pages`, is
   on origin, and has no commits that origin lacks, as Luke sets it to
   origin's before publishing, which creates it in a fresh clone and
   fast-forwards it when it is behind; is not checked out in another
   worktree, as Luke updates it in a worktree of its own; and each
   template copied there from the same path is in the release or on
   that branch (see [Publishing to Branches](#83-publishing-to-branches)).

`--verbose` shows each check as Luke makes it.

### 8.2. Steps

Then Luke:

1. adds a header for X.Y, with today's date, between the placeholder
   in `news` and the news under it, and commits that to the branch
   checked out:

        ## Noteworthy changes in release ?.? (????-??-??) [?]


        ## Noteworthy changes in release 1.2 (2026-10-13) [stable]

2. checks out a new `release-vX.Y` branch, removes the placeholder
   from `news` there, and makes the `replacements`;
3. builds everything with `version=X.Y`;
4. writes the release rockspec, such as `luke-X.Y-1.rockspec`, with
   `_MODREV` set to X.Y, in place of `rockspec`;
5. commits every path in the `add` list, every module filled from a
   [template](#43-templates), every [generated
   file](#34-generated-files) and the release rockspec, even if git
   ignores them, so that the release can be used, or its files copied
   by hand, without building anything; removes each line of a
   `.gitignore` that ignores them, so that the release branch ignores
   nothing it tracks; and tags the commit `vX.Y`, with an announcement
   of the release as the tag message: the `description.summary` and
   `description.homepage` from `rockspec`, the release's news from
   `news`, and how to install it with LuaRocks, as far as the release
   table has each of them;
6. copies files to each branch that the release table names, such as
   `gh-pages`, and commits them;
7. checks out that branch again, and prints the commands to publish the
   release, which for `master` are:

        git push origin master release-v1.2 v1.2 gh-pages
        gh release create v1.2 --verify-tag --latest --title '[ANN] luke v1.2 released' --notes-from-tag
        git checkout release-v1.2
        luarocks upload luke-1.2-1.rockspec
        git checkout master

   The `gh` command, which makes the tag the latest GitHub release and
   its message the release notes, only appears when Luke finds `gh` on
   the `PATH`, or `GH` names it; `GH=true` leaves it out.

### 8.3. Publishing to Branches

Any other key in the `release` table names a branch to copy release
files to, such as `gh-pages` for GitHub Pages.  Its table is a list,
like `modules`, which Luke copies in the order written.  Each entry is
a pair mapping a path on that branch to the file or directory in the
release that replaces it.  A path on its own stands for the same path
in both, and is copied only if the release has it.
For example, [Specl] publishes its manual and API documentation like
this:

{% highlight lua %}
    ['gh-pages'] = {
       {api          = 'doc/api/'},
       {['index.md'] = 'doc/specl.md'},
       '_config.yml.in',
    }
{% endhighlight %}

A path ending in `.in` is a [template](#43-templates), which Luke fills
into the same path without the `.in`, with `@version@` set to X.Y.  A
template copied from the same path is filled from the copy on the
branch when the release has none, so a template such as
`_config.yml.in` can live on `gh-pages` alone:

{% highlight yaml %}
    release-no:   @version@
{% endhighlight %}

Each copy first removes what the branch has at that path, apart from
its templates, so that a file the release no longer has goes too, and
then copies the file, or the contents of the directory, into place.
The root of the branch is `.`, so [LYAML] publishes its [LDoc] output
there, keeping only the templates already on `gh-pages`:

{% highlight lua %}
    ['gh-pages'] = {
       {['.'] = 'doc/'},
    }
{% endhighlight %}

A branch table can also have a `command`, which Luke runs on that
branch after copying everything, before committing, such as to remove
files that a copied directory should not publish.  [luaposix] keeps the
sources of its examples off `gh-pages`, publishing only their LDoc
pages, like this:

{% highlight lua %}
    ['gh-pages'] = {
       {['.'] = 'doc/'},
       command = 'rm -f examples/*.lua',
    }
{% endhighlight %}

### 8.4. Replacements

A `replacements` list edits files on the release branch alone, such as
README badges that show the status of `master`, which should show the
release branch instead.  Like `modules`, it is a list of tables that
each pair a file with its own list of `{text = replacement}` pairs:

{% highlight lua %}
    replacements = {
       {['README.md'] = {
          {['?branch=master'] = '?branch=release-v@version@'},
       }},
    }
{% endhighlight %}

Luke replaces every occurrence of each text, as written rather than as
a Lua pattern, in the order written, so that a later text can match
what an earlier replacement wrote.  A replacement is a
[template](#43-templates), with `@version@` set to X.Y.  The release
commits the edited files with everything else, and the branch checked
out keeps them as they were.

### 8.5. Releasing More Than One Rock

A repository can release more than one rock, in either of two ways.

To release them together, at one version, with one tag, list their
development rockspecs in `rockspec`:

{% highlight lua %}
    release = {
       news     = 'NEWS.md',
       rockspec = {'mylib-dev-1.rockspec', 'mylib-extra-dev-1.rockspec'},
    }
{% endhighlight %}

Luke checks, writes and commits each, and prints a `luarocks upload` for
each.  The rockspec whose name starts with the lukefile `package` gives
the `description` of the announcement, or else the first does, and the
announcement says how to install every rock.

To release them separately, each with versions of its own, make each
development rockspec the key of a table of the keys above, other than
`rockspec`, or write its name alone when it has none, and write nothing
else in `release`.  Luke's own is:

{% highlight lua %}
    release = {
       'luarocks-build-luke-dev-1.rockspec',
       ['luke-dev-1.rockspec'] = {
          news         = 'NEWS.md',
          replacements = {
             {['README.md'] = {
                {['?branch=master'] = '?branch=release-v@version@'},
             }},
          },
          ['gh-pages'] = {
             {['index.md'] = 'doc/luke.md'},
             '_config.yml.in',
          },
       },
    }
{% endhighlight %}

`luke release version=X.Y` releases the rock that the lukefile `package`
names, as `luke-dev-1.rockspec` is of `luke`, and `luke release
rock=luarocks-build-luke version=X.Y` another, by the rules in its table
alone.  Luke stops if there is no such rock.

So that the releases of one repository do not meet, the tag and the branch
of every rock but the `package` name it: `luarocks-build-luke-vX.Y` and
`release-luarocks-build-luke-vX.Y`, where the `package` has `vX.Y` and
`release-vX.Y`.  The source of the release rockspec of such a rock must say
the same, as the archive that GitHub makes of a tag has a directory named
for it:

{% highlight lua %}
    source = {
       url = 'https://github.com/gvvaughan/luke/archive/' .. package .. '-v' .. _MODREV .. '.zip',
       dir = 'luke-' .. package .. '-v' .. _MODREV,
    }
{% endhighlight %}


## 9. Lukefile Reference

Every key that Luke understands, with the value it takes, where a list
can also be a single string, and where it is explained.  Any of them,
and any table they contain, can have a [`platforms`](#5-platforms)
table.  Luke ignores other keys, so a lukefile can hold settings for
other tools.

Luke normalizes every path it takes, dropping `.` and empty components
and any trailing `/`, so `./doc/api/` and `doc/api` are the same path,
and `./` is `.`, the directory itself.  It leaves `..` alone.

| Key                     | Value                                                        | Explained in |
|-------------------------|--------------------------------------------------------------|--------------|
| `luke_format`           | the lukefile format, a whole number                          | [3](#3-the-lukefile) |
| `package`               | the project name                                             | [3](#3-the-lukefile) |
| `version`               | the project version                                          | [3](#3-the-lukefile), [4.2](#42-built-in-values) |
| `modules`               | `{name = source}` entries, where a source can also be a list of sources or a table of rules | [3.1](#31-modules) |
| `install`               | a table with `bin`                                           | [3.2](#32-scripts) |
| `install.bin`           | `{name = source or rules}` entries, or sources on their own  | [3.2](#32-scripts), [3.3](#33-programs) |
| `bin`                   | like `install.bin`, but never installed                      | [3.2](#32-scripts), [3.3](#33-programs) |
| `files`                 | `{path = source or rules}` entries, or templates on their own | [3.4](#34-generated-files) |
| `defines`               | `'NAME[=value]'` or `{NAME = value}` entries, in order       | [3.5](#35-settings-for-every-module), [6](#6-build-time-probes) |
| `incdirs`               | a list of header directories                                 | [3.5](#35-settings-for-every-module) |
| `libdirs`               | a list of library directories                                | [3.5](#35-settings-for-every-module) |
| `libraries`             | a list of libraries or probes                                | [3.5](#35-settings-for-every-module), [6](#6-build-time-probes) |
| `external_dependencies` | `{NAME = {library = ...}}` entries, in order                 | [3.5](#35-settings-for-every-module) |
| `ldocs`                 | an LDoc configuration file                                   | [3.6](#36-ldocs) |
| `variables`             | variable names, each mapped to a value                       | [4.1](#41-variables) |
| `substitute`            | template names, each mapped to a value                       | [4.3](#43-templates) |
| `release`               | a table with `news`, `rockspec`, `check_dependencies`, `add`, `replacements` and branches, or one for each rock | [8](#8-releases) |
| `release.news`          | the NEWS file                                                | [8.1](#81-checks), [8.2](#82-steps) |
| `release.rockspec`      | the development rockspec, or a list of them to release together | [8.1](#81-checks), [8.2](#82-steps) |
| `release.check_dependencies` | `true` to check that LuaRocks has the rockspec's dependencies | [8.1](#81-checks) |
| `release.replacements`  | {% raw %}`{path = {{text = replacement}, ...}}`{% endraw %} entries, in order     | [8.4](#84-replacements) |
| `release.add`           | a list of paths to commit to the release                     | [8.2](#82-steps) |
| `release[NAME-dev-1.rockspec]` | a table of the keys above but `rockspec`, or a bare name, for a rock released on its own | [8.5](#85-releasing-more-than-one-rock) |
| `release[branch]`       | `{path = source}` entries, or paths on their own, in order   | [8.3](#83-publishing-to-branches) |


## 10. Bugs and Contributions

Please report bugs and make suggestions as [GitHub issues][issues], and
check that they are not already fixed on [master][luke] first.  Pull
requests are especially welcome.


[issues]:   https://github.com/gvvaughan/luke/issues
[ldoc]:     https://github.com/lunarmodules/LDoc
[lua]:      https://www.lua.org
[luajit]:   https://luajit.org
[luaposix]: https://github.com/luaposix/luaposix
[luarocks]: https://luarocks.org
[specl]:    https://github.com/gvvaughan/specl
[luke]:     https://github.com/gvvaughan/luke
[lyaml]:    https://github.com/gvvaughan/lyaml

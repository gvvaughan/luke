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
 * modules, scripts and programs described in a [lukefile](#3-the-lukefile)
 * [variables and templates](#4-variables-and-templates) to keep
   version strings and paths in sync
 * [platform-specific](#5-platforms) settings, and Autotools-style
   [build-time probes](#6-build-time-probes)
 * easy to drive [from a rockspec](#7-rockspecs)

Luke grew out of replacing Autotools in [lyaml] and [luaposix], without
needing Perl and M4 on the developer's machine, or carrying a 500k
shell script in the distribution.


## 1. Installation

Copy `build-aux/luke` from the [Luke] repository into your project.
It is a single, minified Lua script with everything it needs, so there
is nothing else to install, and nothing for your users to install
either.

Luke builds that file from its own sources, with its own `lukefile`.
If you change those sources, run `./luke` in the Luke source tree to
regenerate `build-aux/luke`.


## 2. Command Line

{% highlight bash %}
    build-aux/luke [OPTION]... [VARIABLE=VALUE]... [TARGET]...
{% endhighlight %}

Luke reads `lukefile` from the current directory, and builds every
module, script and program it describes.  Name one or more targets to
build only those:

{% highlight bash %}
    build-aux/luke posix.time posix.unistd
{% endhighlight %}

A target names every module, script and program with that name.  Two
targets are special: `all` builds everything, and is the default; and
`install` copies everything already built to its installation
directory.  With other targets, `install` installs only those:

{% highlight bash %}
    build-aux/luke
    build-aux/luke PREFIX=/opt/lua install
    build-aux/luke PREFIX=/opt/lua posix.time install
{% endhighlight %}

Each `VARIABLE=VALUE` argument sets a [variable](#4-variables-and-templates),
overriding the same variable in `lukefile`, the environment, or Luke's
defaults.

The options are:

    --help        print help, then exit
    --version     print version number, then exit
    --file=FILE   use FILE instead of lukefile
    --value=NAME  print the value of variable NAME, then exit
    --quiet       without any output
    --verbose     provide more progress output, such as probe results

Even with `--quiet`, Luke shows any command that fails, along with its
error output.


## 3. The lukefile

A `lukefile` is a Lua file that sets a few global variables, much like a
rockspec.  A minimal one for a pure Lua project is:

{% highlight lua %}
    package = 'stack'
    version = '$USER/$gitref'

    modules = {
       ['stack']       = 'lib/stack/init.lua',
       ['stack.utils'] = 'lib/stack/utils.lua',
    }
{% endhighlight %}

`package` and `version` name the project, and are available to
templates as `@package@` and `@version@` (see
[Templates](#43-templates)).  A `modules` table is required.

### 3.1. Modules

Like the rockspec `builtin` backend, `modules` maps each module name to
its source.  A Lua module is installed beneath `$INST_LUADIR`, and a C
module is compiled to `$objdir/<name>.$LIB_EXTENSION` and installed
beneath `$INST_LIBDIR`.

A module made from several C sources, or that needs extra compiler or
linker settings, takes a table:

{% highlight lua %}
    modules = {
       ['posix.sys.socket'] = {
          defines   = {HAVE_NET_IF_H = {checkheader='net/if.h', include='sys/socket.h'}},
          incdirs   = {'ext/include'},
          libdirs   = {'/opt/local/lib'},
          libraries = {{checksymbol='socket', library='socket'}},
          sources   = {'ext/posix/sys/socket.c'},
       },
    }
{% endhighlight %}

Unlike the rockspec array of strings syntax (`"HAVE_FOO=1"`), `defines`
is always a table (`{HAVE_FOO=1}`).  A value of `1` adds `-DHAVE_FOO`,
and any other value adds `-DHAVE_FOO=<value>`.  Values can also be
[build-time probes](#6-build-time-probes), as can `libraries`.

### 3.2. Scripts

Like the rockspec `build.install.bin` table, an `install.bin` table maps
the name of each script to install to its source:

{% highlight lua %}
    install = {
       bin = {
          specl = 'bin/specl',
       },
    }
{% endhighlight %}

Luke fills the [template](#43-templates) of a source whose name ends in
`.in`, makes every listed script executable, and `luke install` copies
each to its name beneath `$INST_BINDIR`.  An array entry is named for
its source, without any `.in` suffix.

A top-level `bin` table works the same way, for scripts that are only
for use in the source tree, and are never installed, such as a wrapper
that runs a program with the uninstalled modules:

{% highlight lua %}
    bin = {
       specl = 'specl.in',
    }
{% endhighlight %}

### 3.3. Programs

A table entry in `install.bin` or `bin` is a rule for building a program
from several `sources`, with the same `defines`, `incdirs`, `libdirs`,
`libraries` and probes as a module.  Without a `command`, Luke compiles
and links its C sources:

{% highlight lua %}
    install = {
       bin = {
          mytool = {
             sources   = {'src/main.c', 'src/util.c'},
             libraries = {'m'},
          },
       },
    }
{% endhighlight %}

Otherwise, Luke runs `command` after filling the template of any `.in`
source, with `$sources` set to the filled source paths, `$target` to the
program to write, and each `env` variable exported.  This is how Luke
builds its own `build-aux/luke`:

{% highlight lua %}
    bin = {
       ['build-aux/luke'] = {
          command = '$LUA build-aux/smush $sources > $target',
          env     = {LUA_PATH = '$abs_top_srcdir/lib/?.lua;;'},
          sources = {'lib/luke/init.lua', 'lib/luke/version.lua.in'},
       },
    }
{% endhighlight %}

An installable program is built as `$objdir/<name>`, and an in-tree
program at the path given as its name.  Either way, Luke makes it
executable, and `luke <name>` rebuilds it.

### 3.4. Settings for Every Module

A top-level `defines` table adds its definitions to every C compilation,
and a top-level `incdirs` array adds its directories, in addition to the
settings of each module:

{% highlight lua %}
    defines = {
       PACKAGE = '"$package"',
       VERSION = '"$version"',
       NDEBUG  = 1,
    }

    incdirs = {
       'ext/include',
       '$LUA_INCDIR',
    }
{% endhighlight %}

An `external_dependencies` table names libraries that every module
needs.  For each one, Luke adds `$<NAME>_INCDIR` and `$<NAME>_LIBDIR`
to the compiler and linker search paths, defaulting to the `include`
and `lib` directories beneath `$<NAME>_DIR` (`/usr` unless you set it),
and links with the library it finds:

{% highlight lua %}
    external_dependencies = {
       YAML = {
          library = {checksymbol='yaml_document_initialize', library='yaml'},
       },
    }
{% endhighlight %}

{% highlight bash %}
    build-aux/luke YAML_DIR=/opt/homebrew
{% endhighlight %}

### 3.5. LDocs

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
in `lukefile`, then in Luke's defaults, and finally in the environment.
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
| `INST_LIBDIR`   | `$PREFIX/lib/lua/$LUAVERSION`               |
| `INST_LUADIR`   | `$PREFIX/share/lua/$LUAVERSION`             |
| `LUA`           | `lua`                                       |
| `LUAVERSION`    | the version of the Lua running Luke         |
| `LUA_DIR`       | `/usr`                                      |
| `LUA_BINDIR`    | `$LUA_DIR/bin`                              |
| `LUA_INCDIR`    | `$LUA_DIR/include/lua$LUAVERSION`           |
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
 * `gitref`, the abbreviated hash of the commit checked out in the
   current directory, or the empty string outside a git working tree;
 * `abs_top_srcdir`, the absolute path of the current directory.

Setting `version = '$USER/$gitref'` makes every unreleased build
identify who built it, and from which commit, while a release can still
pass `version=X.Y` on the command line.

### 4.3. Templates

Wherever `lukefile` names a source file ending in `.in`, Luke copies it
to the same path without the `.in`, replacing each `@NAME@` with the
value of `NAME` from the command line, `package`, `version` and the
built-in values above, or the environment.  This keeps a version string
in sync, for example:

{% highlight lua %}
    -- lib/stack/version.lua.in
    return 'stack @version@'
{% endhighlight %}

{% highlight lua %}
    modules = {
       ['stack.version'] = 'lib/stack/version.lua.in',
    }
{% endhighlight %}


## 5. Platforms

Any table in `lukefile` can contain a `platforms` table with settings
for particular platforms.  Luke uses the settings for the most specific
platform it is running on, or else the remaining settings in the
`platforms` table as defaults:

{% highlight lua %}
    defines = {
       NDEBUG    = 1,
       platforms = {
          linux  = {_DEFAULT_SOURCE  = 1},
          macosx = {_DARWIN_C_SOURCE = 1},
          _POSIX_C_SOURCE = '200809L',
       },
    }
{% endhighlight %}

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

Wherever a value in `defines` or `libraries` can go, you can put a
probe, a table that Luke runs to compute the value on the build
machine.  Whatever order you write them in, Luke always runs probes in
this order:

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
    ['crypt'] = {
       defines = {
          HAVE_CRYPT   = {checkfunc='crypt'},
          HAVE_CRYPT_H = {checkheader='crypt.h'},
       },
       libraries = {
          {checksymbol='crypt', library='crypt'},
       },
       sources = 'crypt.c',
    },
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

For now, that repeats some of the `lukefile` in the rockspec.  One day,
Luke may read the extra syntax it needs directly from your rockspec,
so that a separate `lukefile` is no longer necessary.


## 8. Bugs and Contributions

Please report bugs and make suggestions as [GitHub issues][issues], and
check that they are not already fixed on [master][luke] first.  Pull
requests are especially welcome.


[issues]:   https://github.com/gvvaughan/luke/issues
[ldoc]:     https://github.com/lunarmodules/LDoc
[lua]:      https://www.lua.org
[luajit]:   https://luajit.org
[luaposix]: https://github.com/luaposix/luaposix
[luarocks]: https://luarocks.org
[luke]:     https://github.com/gvvaughan/luke
[lyaml]:    https://github.com/gvvaughan/lyaml

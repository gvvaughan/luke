# Use the source, Luke!

[![License](http://img.shields.io/:license-mit-blue.svg)](http://mit-license.org)
[![workflow status](https://github.com/gvvaughan/luke/actions/workflows/spec.yml/badge.svg?branch=master)](https://github.com/gvvaughan/luke/actions)
[![codecov.io](https://codecov.io/gh/gvvaughan/luke/branch/master/graph/badge.svg)](https://codecov.io/gh/gvvaughan/luke)

A lightweight, self-bootstrapping build utility for LuaJIT, [Lua][]
5.1, 5.2, 5.3 and 5.4.

Luke is released under the [MIT license][mit] (the same license as Lua
itself).  There is no warranty.

[lua]: http://www.lua.org/ "The Lua Project"
[mit]: http://mit-license.org "MIT License"


## Installation

To avoid unnecessary dependencies, simply copy `build-aux/luke`
directly into your project.

Note that this is an uglified version of the formatted sources
combined into a single file for ease of use and minimal size.  If
you edit the sources locally, run `make` to regenerate
`build-aux/luke` with your changes.


## Use

Add a `lukefile` to your C or Lua project, with the proper settings
to build your project.  You can either run it from your shell
(The VARIABLES you need to pass will depend on the content of your
project's `lukefile`):

    build-aux/luke [VARIABLE=VALUE]... [TARGET]...

...or arrange for it to be executed by your rockspec or `Makefile`.

`TARGET` can be any module table key in `lukefile`, or one of the
special keys, `all` to build all modules, or `install` to copy all
built modules to `$PREFIX`.  If no `TARGET` is given, `all` is implied.


## Documentation

Luke was originally an experiment to find a powerful enough syntax
to add to a [LuaRocks][] rockspec file for probing the host system
features at build-time well enough to replace Autotools in [lyaml][]
and [luaposix][], without relying on having Perl and M4 installed on
the developer system, or carrying a 500k shell-script in the
distribution (the entire uncompressed content of lyaml including specs,
documentation, and a copy of luke is well below 400k).

For now, that involves some duplication between the rockspec and the
`lukefile` content, but now that I've found a pleasant way to express
system probing and compiler/linker invocations from luke, I'll likely
rewrite this code as a patch for [LuaRocks][] or as a plug-in, so that
`lukefile` will no longer be necessary -- the additional syntaxes will
be supported directly in your rockspec file.

The `VALUE` for all `VARIABLE=VALUE` pairs on the luke command line are
substituted in the `lukefile` wherever `$VARIABLE` is seen, otherwise
`$VARIABLE` will be looked up in the process environment.

### .in files

In any place that a file path is allowed in `lukefile`, if that path
has an extension of `.in`, Luke will copy that file to a new location
without the `.in` suffix, and substitute any `@VARIABLE@` strings with
the associated `VALUE` if defined on the command line or in the caller's
environment.  This is useful for keeping a version string in sync, for
example.

### Syntax Extensions

- **defines** (table): A `defines` table at the top-level will add
  `-D<key>=<value>` to every module compilation.  This is in addition to
  the `defines` tables allowed in the `modules` table by the rockspec
  `builtin` backend, and supports the same platform overrides syntax.
  Note that unlike the rockspec array of strings syntax
  (`"ROCKSPEC_DEFINE=1"`), Luke requires a table in all cases
  (`{LUKE_DEFINE=1}`).

- **incdirs** (array of strings): An `incdirs` array at the top-level will
  add `-I<string>` to every module compilation.  This is in addition to
  the `incdirs` arrays allowed in the  `modules` table by the rockspec
  `builtin` backend.

- **ldocs** (string): Path to an [LDocs][] `config.ld` file, which Luke
  will process with:

      ldocs -c config.ld .

### Build-Time Probes

No matter what order these are declared in your `lukefile`, the probes
are always executed in the following order:

1. **checkprog** (table): `{checkprog='SH', progs={'dash', 'ash', 'sh'}}`
   Search the caller's PATH for the earliest of `progs` and return the
   matching path.

2. **checkheader** (table): `{checkheader='net/if.h', include='sys/socket.h'}`
   Return `1` if a short C program that includes the named header
   compiles successfully, otherwise `0`. An optional `include` can name
   another header that must be included first, or `includes` with an
   array of prerequisite headers is allowed.

3. **checkdecl** (table): `{checkdecl='fdatasync', include='unistd.h'}`
   Return `1` if any of the headers named by the `include` (or
   `includes`) key have a declaration (or CPP macro) for the function
   given with the `checkdecl` key, otherwise `0`. 
   
4. **checksymbol** (table): `{checksymbol='crypt', library='crypt'}`
   Return the value of the `library` key if linking with that library is
   necessary to resolve the named symbol, otherwise nothing is returned
   if the symbol can be resolved without 'library'.  Instead of `library`,
   multiple libraries can be tried in turn if passed as an array in a
   `libraries` key. An optional `include` (or `includes`) can name a
   header that must be included in a C program that has symbol resolved.
   And finally, an `ifdef` key will mark the symbol as unsupported if
   the named macro is undefined.

5. **checkfunc** (table): `{checkfunc='crypt'}`
   Return `1` if the named function is available, `0` otherwise.

6. **checkmember** (table): `{checkmember='struct tm.tm_gmtoff', include='time.h'}`
   Return `1` if the struct and member are available, `0` otherwise.  An
   optional `include` (or `includes`) key should name any headers that
   must be included for the compiler to have a definition os the named
   struct.

Due to the strict reordering of probes, this modules entry:

    ['crypt'] = {
       defines = {
          HAVE_CRYPT = {checkfunc='crypt'},
          HAVE_CRYPT_H = {checkheader='crypt.h'},
       },
       libraries = {
          {checksymbol='crypt', library='crypt'},
       },
       sources = 'crypt.c',
    },

...when executed, may behave as follows on your build machine:

    checking for cc... yes
    checking whether cc works... yes
    checking for crypt.h... no
    checking for library containing crypt... none required
    checking for crypt... yes
    cc -O2 -fPIC -DHAVE_CRYPT_H=0 -DHAVE_CRYPT crypt.c -o linux/crypt.so

...given `crypt.c` was written with:

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

[ldocs]: https://github.com/lunarmodules/LDoc "Lua documentation generator"
[luaposix]: https://github.com/luaposix/luaposix "Lua bindings for POSIX"
[luarocks]: https://github.com/luarocks/luarocks "Lua package manager"
[lyaml]: https://github.com/gvvaughan/lyaml "LibYAML binding for Lua"


## Bugs reports and code contributions

Please make bug reports and suggestions as [GitHub issues][issues].
Pull requests are especially appreciated.

But first, please check that you issue has not already been reported by
someone else, and that it is not already fixed on [master][github] in
preparation for the next release (See Installation section above for how
to temporarily install master with [LuaRocks][]).

There is no strict coding style, but please bear in mind the following
points when proposing changes:

0. Follow existing code. There are a lot of useful patterns and
   avoided traps there.

1. 8-character indentation using TABs in C sources; 3-character
   indentation using SPACEs in Lua sources.

2. Simple strings are easiest to type using single-quote delimiters
   saving double-quotes for where a string contains apostrophes.

3. Save horizontal space by only using SPACEs where the parser requires
   them.

4. Use vertical space to separate out compound statements to help the
   coverage reports discover untested lines.

5. Prefer explicit string function calls over object methods, to mitigate
   issues with monkey-patching in caller environment. 

[github]: http://github.com/gvvaughan/luke
[issues]: http://github.com/gvvaughan/luke/issues

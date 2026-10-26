# Use the source, Luke!

[![License](http://img.shields.io/:license-mit-blue.svg)](http://mit-license.org)
[![workflow status](https://github.com/gvvaughan/luke/actions/workflows/spec.yml/badge.svg?branch=release-v0.7)](https://github.com/gvvaughan/luke/actions)
[![codecov.io](https://codecov.io/gh/gvvaughan/luke/graph/badge.svg?branch=release-v0.7)](https://codecov.io/gh/gvvaughan/luke?branch=release-v0.7)

[Luke][] is a lightweight, self-bootstrapping build utility for
[LuaJIT][] and [Lua][] 5.1, 5.2, 5.3, 5.4 and 5.5.  It builds Lua and C
modules, scripts and programs, probing the host system for the headers,
functions and libraries they need, from a `lukefile` written in the same
style as a [LuaRocks][] rockspec.

Luke is released under the [MIT license][mit] (the same license as Lua
itself).  There is no warranty.


## Installation

[LuaRocks][] builds a rock from its rockspec with Luke when the rockspec
says `build = {type = 'luke'}`, by installing the `luarocks-build-luke`
build backend for the build, so there is nothing for you to install.

To use the `luke` command, such as `luke release`, install it:

    luarocks install luke

To avoid unnecessary dependencies, you can instead copy `build-aux/luke`
directly into your project, from the rock, which installs the same file,
or from the release branch of a release:

    cp "$(luarocks show --rock-dir luke)/bin/luke" build-aux/luke

Note that this is an uglified version of the formatted sources
combined into a single file for ease of use and minimal size.


## Building from a clone

LuaRocks builds Luke too, with the `luarocks-build-luke` backend, which it
installs.  To build `luke` in a clone, which regenerates `build-aux/luke`,
`doc/luke.1` and `lib/luke/version.lua`, without installing it:

    luarocks make --no-install luke-dev-1.rockspec

`build-aux/luke` is not tracked, except in a release, so a clone does not
have one until it is built, and when you edit the sources, run that
command again to regenerate it.  LuaRocks installs the `std.normalize` and
`std.functional` rocks that Luke bundles into it, to build it.

To run Luke from the sources of the clone, once that has made
`lib/luke/version.lua`, use the `./luke` wrapper.  To run the specs, after
`luarocks test --prepare` installs their dependencies, once:

    luarocks test

To build with changes that you have made to the backend, install it from
the clone first, and again whenever you change it, because LuaRocks takes
a `-dev` backend that is installed already for any version, even one that
is too old:

    luarocks make luarocks-build-luke-dev-1.rockspec


## Documentation

Luke includes [comprehensive documentation][github.io], which is
written in [doc/luke.md][manual].


## Bug reports and code contributions

Please make bug reports and suggestions as [GitHub issues][issues].
Pull requests are especially appreciated.

But first, please check that your issue has not already been reported
by someone else, and that it is not already fixed on [master][github]
in preparation for the next release.

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


[github]:    https://github.com/gvvaughan/luke
[github.io]: https://gvvaughan.github.io/luke
[issues]:    https://github.com/gvvaughan/luke/issues
[lua]:       https://www.lua.org "The Lua Project"
[luajit]:    https://luajit.org
[luarocks]:  https://luarocks.org "Lua package manager"
[luke]:      https://github.com/gvvaughan/luke
[manual]:    doc/luke.md
[mit]:       http://mit-license.org "MIT License"

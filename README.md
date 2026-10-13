# Use the source, Luke!

[![License](http://img.shields.io/:license-mit-blue.svg)](http://mit-license.org)
[![workflow status](https://github.com/gvvaughan/luke/actions/workflows/spec.yml/badge.svg?branch=master)](https://github.com/gvvaughan/luke/actions)
[![codecov.io](https://codecov.io/gh/gvvaughan/luke/branch/master/graph/badge.svg)](https://codecov.io/gh/gvvaughan/luke)

[Luke][] is a lightweight, self-bootstrapping build utility for
[LuaJIT][] and [Lua][] 5.1, 5.2, 5.3, 5.4 and 5.5.  It builds Lua and C
modules, scripts and programs, probing the host system for the headers,
functions and libraries they need, from a `lukefile` written in the same
style as a [LuaRocks][] rockspec.

Luke is released under the [MIT license][mit] (the same license as Lua
itself).  There is no warranty.


## Installation

To avoid unnecessary dependencies, simply copy `build-aux/luke`
directly into your project.

Note that this is an uglified version of the formatted sources
combined into a single file for ease of use and minimal size.  If
you edit the sources locally, run `./luke` to regenerate
`build-aux/luke` with your changes.


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

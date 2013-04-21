Luke
====

- *Use the Source, Luke!*

Luke is a build tool. It works a bit like traditional UNIX Make, but
without the pain of filesystem timestamps and the reliance on embedded
TABs in the recipe file.

Luke is based on the tiny Lua scripting language, with all the power and
flexibility that brings, and which enables Luke to run in a very bare
environment: An ANSI C compiler and a Bourne compatible shell is all
that's required by Luke to bootstrap itself, and start building your
sources from a `Blueprint` file.

Luke differs from Make primarily in that:

 * All dependencies in Luke are explicit - Make will attempt to determine
   what needs to be done to build a file based on a set of rules that
   tell it how to transform file types... this works well until you need
   to have *different* rules apply to two files of the same type... which
   then causes Make to quickly become unmanageable. Luke avoids this by
   requiring all rules to be explicit. This is much less work than it
   sounds.
 * Luke determines whether a target needs to be rebuilt based on md5sums
   of any compiler settings plus the files it depends on. If the md5sums
   change, the target is rebuilt.  Make compares the timestamps of file
   dependencies, and if any is newer than expected everything that
   depends on it is rebuilt... this works well until you have some of
   your files on an NFS server with an out of sync clock, or a large
   build where one leaf node of the dependency graph changes and then
   timestamp ripples can cause practically everything to be rebuilt even
   though nearly all the rebuilt files will be identical. Md5sums do not
   have that side-effect.

Luke also tries to solve some of the same problems as the GNU Build
System (Autoconf, Automake, Libtool), but without the pain of creeping
file droppings and managing *huge* generated shell scripts in source
control and distribution tarballs.

Luke differs from the GNU Build System in that:

 * Luke does not require dozens of shell utility programs on the build
   host - just an ANSI C compiler and a Bourne Shell with echo to self-
   bootstrap, or else only the ANSI C compiler and a text file editor
   to manually bootstrap. Once the driver is compiled (automatically or
   by hand), there are NO dependencies at all. Luke is entirely self
   contained, even the runtime is present, unlike the GNU Build
   System which needs awk, sed, make, Bourne shell and several others
   on the build host, plus Perl, Automake, Autoconf, Libtool and many
   more on the development system.

Luke is compatible with the GNU Build System in that:

 * A distribution that builds with Luke supports the familiar pattern:
   `./configure; make; make install' on the build host. This requires
   an installed Make of course, but there's no such requirement unless
   the `make; make install' pattern is important to you.

Luke supports:

 * Automatic dependency checking for C and C++ files
 * Explicit dependency graphs
 * Arbitrarily complex rules (because you can embed chunks of Lua script
   in your Blueprint to do anything you like)
 * Can handle multiple directories at the same time (no more recursive
   makefiles!)
 * Easy cross-compilation (object files are stored in Luke's own object
   file cache, not in your build tree)
 * Easy deployment (all of Luke's core code consists of exactly *one*
   file, which can be run on any platform --- no installation or
   compilation needed after bootstrap!)
 * Object oriented design (making it very easy to create your own rules
   by specialising one of the existing ones)

Here is an example Blueprint that will build a simple C program:

---start---
include "c.luke"       -- load the C rules

default = cprogram {   -- build a C program
  cfile "main.c",      -- by compiling C sources into object files
  cfile "utils.c",
  cfile "aux.c",
	
  install = luke.install ("myprogram") -- and installing
}
---end---

If this is saved as 'Blueprint' in the current directory, it can be
invoked by simply doing:

  ./luke
  
...and it will build.


CONTENTS
========

As a Luke user, you might want to look at the following directories in
the distribution:

 * share/luke: contains the standard plugins.
 * share/examples: contains some example Blueprints.
 * share/examples/source: source code used by the example Blueprints.
  
If you wish to modify Luke itself, you'll also need to know about these
directories:

 * src: contains the Luke source code itself.
 * src/lua: contains the Lua interpreter source code.
 * build-aux: contains some utilities used as part of the build process.
 * tests: the unit tests that are run during the build process.

-- Use the source, Luke!
-- Copyright (C) 2014-2026 Gary V. Vaughan

local _MODREV, _SPECREV = 'dev', '-1'

rockspec_format = '3.0'
package = 'luke'
version = _MODREV .. _SPECREV

description = {
   summary = 'Use the source, Luke!',
   detailed = [[
      A lightweight, self-bootstrapping build utility for LuaJIT and
      Lua 5.1 through 5.5.
   ]],
   homepage = 'https://github.com/gvvaughan/luke',
   license = 'MIT',
}

dependencies = {
   'lua >= 5.1, < 5.6',
}

source = {
   url = 'https://github.com/gvvaughan/luke/archive/v' .. _MODREV .. '.zip',
   dir = 'luke-' .. _MODREV,
}

if _MODREV == 'dev' then
   source = {
      url = 'git+https://github.com/gvvaughan/luke.git',
   }
end

build = {
   type = 'builtin',

   -- A release commits build-aux/luke and its man page to install.
   install = {
      bin = {luke = 'build-aux/luke'},
   },

   -- A release commits its man page to install.
   copy_directories = {'doc'},
}

if _MODREV == 'dev' then
   -- The rock installs only build-aux/luke as the `luke` command.
   local bundled = {
      'lib/luke/_base.lua',
      'lib/luke/cli.lua',
      'lib/luke/compile.lua',
      'lib/luke/configure.lua',
      'lib/luke/ctest.lua',
      'lib/luke/environment.lua',
      'lib/luke/init.lua',
      'lib/luke/lukefile.lua',
      'lib/luke/platforms.lua',
      'lib/luke/prepare.lua',
      'lib/luke/release.lua',
      'lib/luke/schema.lua',
      'lib/luke/version.lua.in',
      'lib/type/path.lua',
      'std.functional._base',
      'std.functional.init',
      'std.normalize',
      'std.normalize._core',
      'std.prototype._base',
      'std.prototype.container',
      'std.prototype.contextmanager',
      'std.prototype.object',
      'std.prototype.orderedmap',
      'std.prototype.set',
   }

   build.type = 'luke'

   -- Luke is one file with these bundled in, so a development build needs
   -- them only to build it.
   build_dependencies = {
      'luarocks-build-luke >= 0.3.1',
      'smush >= 0.1',
      'std.functional >= 2.1',
      'std.normalize >= 4.1',
      'std.prototype >= 2.1',
   }

   -- A build without help2man keeps the man page that a release commits.
   build.variables = {
      HELP2MAN = {checkprog = 'HELP2MAN', progs = {'help2man', 'true'}},
      SMUSH    = {checkprog = 'SMUSH', progs = {'smush'}},
   }

   build.bin = {
      {['build-aux/luke'] = {
         -- smush, from its rock, finds std.normalize and std.functional on
         -- LUA_PATH, as `luarocks path` sets it, or else on the default path.
         command = 'LUA_PATH="$abs_top_srcdir/lib/?.lua;$abs_top_srcdir/lib/?/init.lua;$LUA_PATH;;"' ..
                   ' $SMUSH --main=luke $sources > $target',
         sources = bundled,
      }},
   }

   -- Document build-aux/luke.
   build.files = {
      {['doc/luke.1'] = {
         command = '$HELP2MAN --output=$target --no-info --name="Use the source, Luke!" "$LUA build-aux/luke"',
         sources = 'build-aux/luke',
      }},
   }

   -- Stamp a development build with who made it, and from which commit.
   build.version = '$USER/$gitref'
   build.copy_directories = nil
end

test_dependencies = {
   'ansicolors',
   'luacov',
   'specl >= 17',
}

test = {
   type = 'command',
   command = 'specl -vfreport --coverage spec/*_spec.yaml',
}

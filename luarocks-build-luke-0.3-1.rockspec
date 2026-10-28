-- Use the source, Luke!
-- Copyright (C) 2014-2026 Gary V. Vaughan

local _MODREV, _SPECREV = '0.3', '-1'

rockspec_format = '3.0'
package = 'luarocks-build-luke'
version = _MODREV .. _SPECREV

description = {
   summary = 'LuaRocks build backend for luke',
   detailed = [[
      Build a rock from the recipe in the `build` table of its rockspec,
      with `build.type = 'luke'`.  The backend is one file that needs
      nothing else installed.
   ]],
   homepage = 'https://github.com/gvvaughan/luke',
   license = 'MIT',
}

dependencies = {
   'lua >= 5.1, < 5.6',
}

source = {
   url = 'https://github.com/gvvaughan/luke/archive/' .. package .. '-v' .. _MODREV .. '.zip',
   dir = 'luke-' .. package .. '-v' .. _MODREV,
}

if _MODREV == 'dev' then
   source = {
      url = 'git+https://github.com/gvvaughan/luke.git',
   }
end

build = {
   type = 'builtin',

   -- A release commits build-aux/luarocks-build-luke.lua to install.
   install = {
      lua = {['luarocks.build.luke'] = 'build-aux/luarocks-build-luke.lua'},
   },
}

if _MODREV == 'dev' then
   -- The backend is one file that smush, from its rock, bundles from this
   -- source tree.
   local bundled = {
      'lib/luarocks/build/luke.lua',
      'lib/luke/_base.lua',
      'lib/luke/bundled.lua',
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
      'lib/luke/rockspec.lua',
      'lib/luke/schema.lua',
      'lib/luke/version.lua.in',
      'lib/type/path.lua',
      -- From their rocks, found on the Lua path.
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

   -- The backend is one file with these bundled in, so a development build
   -- needs them only to build it.
   build_dependencies = {
      'luarocks-build-luke >= 0.2',
      'smush >= 0.1',
      'std.functional >= 2.1',
      'std.normalize >= 4.1',
      'std.prototype >= 2',
   }

   build.variables = {
      SMUSH = {checkprog = 'SMUSH', progs = {'smush'}},
   }

   -- luarocks.path, luarocks.core.cfg, luarocks.core.vers and luarocks.manif
   -- are referenced from luarocks-build-luke.lua, but provided by LuaRocks
   -- itself, and `package` is the host's, to ask whether LuaRocks is running.
   build.files = {
      {['build-aux/luarocks-build-luke.lua'] = {
         command = 'LUA_PATH="$abs_top_srcdir/lib/?.lua;$abs_top_srcdir/lib/?/init.lua;$LUA_PATH;;"' ..
                   ' $SMUSH --module=luarocks.build.luke --external=package --external=luarocks.path' ..
                   ' --external=luarocks.core.cfg --external=luarocks.core.vers --external=luarocks.manif' ..
                   ' $sources > $target',
         sources = bundled,
      }},
   }

   -- Stamp a development build with who made it, and from which commit.
   build.version = '$USER/$gitref'
end

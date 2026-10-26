local _MODREV, _SPECREV = 'dev', '-1'

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

-- Luke is one file with these bundled in, so installing it needs them
-- only to build it.
build_dependencies = {
   'smush',
   'std.functional >= 2',
   'std.normalize >= 4',
   'std.prototype >= 2',
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

-- The backend is one file that smush, from its rock, bundles from this source
-- tree.
local sources = {
   'lib/luarocks/build/luke.lua',
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
   'lib/luke/rockspec.lua',
   'lib/luke/schema.lua',
   'lib/type/path.lua',
   'luke.version=lib/luke/luarocks-build-luke-version.lua',
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

local smushed = ''
for i = 1, #sources do
   smushed = smushed .. ' ' .. sources[i]
end

build = {
   type = 'command',

   -- luarocks.path is referenced from luarocks-build-luke.lua, but provided
   -- by LuaRocks itself.
   build_command =
      "sed 's/@version@/" .. _MODREV .. "/' lib/luke/version.lua.in > lib/luke/luarocks-build-luke-version.lua && " ..
      'LUA_PATH="$PWD/lib/?.lua;$PWD/lib/?/init.lua;$LUA_PATH;;" smush' ..
      ' --module=luarocks.build.luke --external=luarocks.path' .. smushed ..
      ' > build-aux/luarocks-build-luke.lua',

   install = {
      lua = {['luarocks.build.luke'] = 'build-aux/luarocks-build-luke.lua'},
   },
}

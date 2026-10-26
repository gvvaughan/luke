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

-- Luke is one file with these bundled in, so installing it needs them
-- only to build it.
build_dependencies = {
   'luarocks-build-luke >= 0.2',
   'smush',
   'std.functional >= 2',
   'std.normalize >= 4',
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

-- The rock installs only build-aux/luke, the single file that projects
-- copy, as the `luke` command: smush bundles it from this source tree,
-- and the std.normalize and std.functional that it finds on the Lua path.
local bundled = {
   'lib/luke/_base.lua',
   'lib/luke/cli.lua',
   'lib/luke/compile.lua',
   'lib/luke/configure.lua',
   'lib/luke/environment.lua',
   'lib/luke/functional.lua',
   'lib/luke/init.lua',
   'lib/luke/lukefile.lua',
   'lib/luke/platforms.lua',
   'lib/luke/prepare.lua',
   'lib/luke/release.lua',
   'lib/luke/schema.lua',
   'lib/luke/version.lua.in',
   'lib/type/context-manager.lua',
   'lib/type/dict.lua',
   'lib/type/path.lua',
   'std.functional._base',
   'std.functional.init',
   'std.normalize',
   'std.normalize._core',
}

build = {
   type = 'luke',

   -- A build without help2man keeps the man page that a release commits.
   variables = {
      HELP2MAN = {checkprog = 'HELP2MAN', progs = {'help2man', 'true'}},
      SMUSH    = {checkprog = 'SMUSH', progs = {'smush'}},
   },

   bin = {
      {['build-aux/luke'] = {
         -- smush, from its rock, finds std.normalize and std.functional on
         -- LUA_PATH, as `luarocks path` sets it, or else on the default path.
         command = 'LUA_PATH="$abs_top_srcdir/lib/?.lua;$abs_top_srcdir/lib/?/init.lua;$LUA_PATH;;"' ..
                   ' $SMUSH --main=luke $sources > $target',
         sources = bundled,
      }},
   },

   -- Document build-aux/luke.
   files = {
      {['doc/luke.1'] = {
         command = '$HELP2MAN --output=$target --no-info --name="Use the source, Luke!" "$LUA build-aux/luke"',
         sources = 'build-aux/luke',
      }},
   },

   install = {
      bin = {luke = 'build-aux/luke'},
   },
}

if _MODREV == 'dev' then
   -- Stamp a development build with who made it, and from which commit.
   build.version = '$USER/$gitref'
end

test_dependencies = {
   'ansicolors',
   'luacov',
   'specl >= 16.1',
}

test = {
   type = 'command',
   command = 'specl -vfreport --coverage spec/*_spec.yaml',
}

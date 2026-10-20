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

-- Luke builds itself, running in strict mode from this source tree.
-- The rock installs only build-aux/luke, the single file that projects
-- copy, as the `luke` command.
build = {
   type = 'command',
   build_command = '$(LUA) ./luke package="' .. package .. '" LUA="$(LUA)"',
   install = {
      bin = {luke = 'build-aux/luke'},
   },
}

if _MODREV ~= 'dev' then
   -- A release tarball has no git to stamp $USER/$gitref from, so
   -- stamp build-aux/luke with the release version, as the release did.
   build.build_command = build.build_command .. ' version="' .. _MODREV .. '"'
end

test_dependencies = {
   'ansicolors',
   'luacov',
   'specl >= 16',
}

test = {
   type = 'command',
   command = 'specl -vfreport --coverage spec/*_spec.yaml',
}

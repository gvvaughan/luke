local _MODREV, _SPECREV = 'git', '-1'

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
   url = 'git+https://github.com/gvvaughan/luke.git',
}

-- Luke builds itself, running in strict mode from this source tree.
-- Projects copy build-aux/luke rather than installing a luke rock, so
-- this rockspec only drives the specs, and installs nothing.
build = {
   type = 'command',
   build_command = '$(LUA) ./luke package="' .. package .. '" version="' .. _MODREV .. '"',
}

test_dependencies = {
   'ansicolors',
   'luacov',
   'specl >= 15',
}

test = {
   type = 'command',
   command = 'specl -vfreport --coverage spec/*_spec.yaml',
}

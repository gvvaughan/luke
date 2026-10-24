--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

--[[--
 LuaRocks build backend for luke, so that a rockspec with a `build.type`
 of `luke` builds from the recipe that its `build` table holds.

 @module luarocks.build.luke
]]

local luke = {}

-- *rockspec*, with the directories that LuaRocks stages the rock in as
-- they are now.  LuaRocks sets those variables when it loads the rockspec,
-- and then packing a binary rock changes to a temporary tree, so only
-- ask LuaRocks, if it is running, and never trust the variables.
local function staged(rockspec)
   local path = package.loaded['luarocks.path']
   if path == nil then
      return rockspec
   end
   local r, variables = {}, {}
   for k, v in next, rockspec do
      r[k] = v
   end
   for k, v in next, rockspec.variables do
      variables[k] = v
   end
   local name, version = rockspec.package, rockspec.version
   variables.BINDIR = path.bin_dir(name, version)
   variables.LIBDIR = path.lib_dir(name, version)
   variables.LUADIR = path.lua_dir(name, version)
   r.variables = variables
   return r
end

--- Build and install the rock that *rockspec* describes.
-- @tparam table rockspec the rockspec, as LuaRocks loaded it
-- @tparam boolean no_install whether LuaRocks asked only for a build
-- @treturn boolean `true`, or else `nil` and a message
function luke.run(rockspec, no_install)
   local status, err = require 'luke._base'.protected(function()
      return require 'luke'.make(require 'luke.rockspec'.fromrockspec(staged(rockspec), no_install))
   end)
   if status == nil then
      return nil, err
   end
   if status ~= 0 then
      return nil, 'luke failed'
   end
   return true
end

return luke

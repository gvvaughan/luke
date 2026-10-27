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

-- The Lua path that smush finds modules in: the `LUA_PATH` of the
-- environment, where it has a `;;`, and else the one of this Lua.
local function luapath()
   local path = os.getenv 'LUA_PATH'
   if path == nil then
      return package.path
   end
   return (string.gsub(path, ';;', ';' .. package.path .. ';', 1))
end

-- The rock that has the file that *path* finds for a module, as a function
-- of the module name, with its version and the file, if a tree of
-- LuaRocks has the file, and else nothing: a file that no rock has, such as
-- one of a checkout on the path, is the developer's choice.
local function provider(path)
   local cfg = require 'luarocks.core.cfg'
   local luapath = require 'luarocks.path'
   local manif = require 'luarocks.manif'
   local searchpath = require 'std.normalize'.package.searchpath
   return function(name)
      local file = searchpath(name, path)
      if file == nil then
         return nil
      end
      for _, tree in ipairs(cfg.rocks_trees) do
         local deployed = luapath.deploy_lua_dir(tree) .. '/'
         if string.sub(file, 1, #deployed) == deployed then
            -- LuaRocks names a module by its file, so `std.normalize` is
            -- `std.normalize.init` to it.
            local kind, item = manif.get_provided_item('lua', string.sub(file, #deployed + 1))
            local rock, version = manif.get_current_provider(kind, item, tree)
            return rock, version, file
         end
      end
   end
end

-- An error message if a module that a rule of *rockspec* bundles from the
-- Lua path comes from a rock older than the build dependency on it, else
-- nothing.  That is only a rule that has a module name among its sources,
-- and only when LuaRocks is running to say which rock has the file.
local function outdated(rockspec)
   local bundled = require 'luke.bundled'
   local build = rockspec.build or {}
   local names = bundled.modules(build.bin)
   for _, name in ipairs(bundled.modules(build.files)) do
      names[#names + 1] = name
   end
   if #names == 0 or package.loaded['luarocks.path'] == nil then
      return nil
   end
   local vers = require 'luarocks.core.vers'
   local queries = (rockspec.build_dependencies or {}).queries or {}
   local messages = bundled.outdated(names, provider(luapath()), function(rock, version)
      for _, query in ipairs(queries) do
         if query.name == rock then
            local ok = vers.match_constraints(vers.parse_version(version), query.constraints)
            return ok, tostring(query)
         end
      end
   end)
   if #messages > 0 then
      return table.concat(messages, '\n')
   end
end

--- Build and install the rock that *rockspec* describes.
-- @tparam table rockspec the rockspec, as LuaRocks loaded it
-- @tparam boolean no_install whether LuaRocks asked only for a build
-- @treturn boolean `true`, or else `nil` and a message
function luke.run(rockspec, no_install)
   local old = outdated(rockspec)
   if old ~= nil then
      return nil, old
   end
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

--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

--[[--
 The LuaRocks front end of luke: the recipe and the request that a
 rockspec gives, for luke to make.

 The recipe is the `build` table of the rockspec, as LuaRocks gives it
 to a build backend, with its platform overrides already applied, and
 what LuaRocks keeps for itself taken out.  It has the same keys as a
 lukefile, in the same shapes, so luke normalizes it as it does a
 lukefile.  The request is made of the variables that LuaRocks passes.
]]

local _ENV = require 'luke.normalize' {
   'luke.functional',
   'luke.lukefile',
   'luke.prepare',
}


-- The keys of a rockspec's `build` table that are LuaRocks's, not luke's.
local LUAROCKS = {'copy_directories', 'install', 'type'}


-- The variables of LuaRocks that luke has by the same name.
local SAME = {
   'CC', 'CFLAGS', 'LIBFLAG', 'LIB_EXTENSION', 'LUA', 'LUA_DIR',
   'LUA_INCDIR', 'LUA_LIBDIR', 'LUA_VERSION', 'OBJ_EXTENSION',
}


-- Where luke installs, and the directories that LuaRocks makes the rock
-- in, for it to install from.
local INSTALLS = {
   INST_BINDIR = 'BINDIR',
   INST_LIBDIR = 'LIBDIR',
   INST_LUADIR = 'LUADIR',
}


-- The variables that LuaRocks makes for each of its `external_dependencies`
-- *name*s, which luke has by the same names.
local function dependency_variables(name)
   return list(name .. '_BINDIR', name .. '_DIR', name .. '_INCDIR', name .. '_LIBDIR')
end


-- The version of a rock, without the revision of its rockspec.
local function modrev(version)
   return (gsub(version, '%-%d+$', ''))
end


-- The pair of `build.external_dependencies` that *pair* is, with the
-- library that LuaRocks looks for filled in, where a probe leaves it
-- out, as it need only say what LuaRocks cannot, such as a symbol to
-- check for.  *native* is the `external_dependencies` of the rockspec.
local function with_library(native)
   return function(pair)
      local name, dependency = destructure(pair)
      local probe = type(dependency) == 'table' and dependency.library
      return choose(type(probe) == 'table' and probe.library == nil and native[name] ~= nil, function()
         return {[name] = merged(dependency, {
            library = merged(probe, {library = native[name].library}),
         })}
      end, pair)
   end
end


-- The recipe of *rockspec*, as luke normalizes it.
local function recipe_of(rockspec)
   local build = rockspec.build
   return normalize(merged(
      except(build, bind(contains, {LUAROCKS})),
      {
         luke_format = 0,
         package     = rockspec.package,
         -- A `build.version` is the version that a lukefile would say, such as
         -- `$USER/$gitref`, for a development build.
         version     = build.version or modrev(rockspec.version),
         -- The list that map makes has an `n` field, which is not an entry.
         external_dependencies = choose(build.external_dependencies, function(dependencies)
            return except(map(dependencies, with_library(rockspec.external_dependencies or {})), 'n')
         end),
      }
   ))
end


-- The settings that luke is passed, from the *variables* of LuaRocks
-- and the names of the rockspec's *externals*.
local function settings_of(variables, externals)
   return merged(
      tabulate(flatten(list(SAME, flatmap(sorted(externals), dependency_variables))), function(name)
         return name, variables[name]
      end),
      tabulate(sorted(keys(INSTALLS)), function(name)
         return name, variables[INSTALLS[name]]
      end)
   )
end


return {
   -- The recipe and the request that *rockspec* gives luke to make, which
   -- is to build, and unless LuaRocks asked for only a build, *no_install*,
   -- to install.
   fromrockspec = function(rockspec, no_install)
      return recipe_of(rockspec), mkrequest {
         clidefs = settings_of(rockspec.variables, keys(rockspec.external_dependencies or {})),
         source  = rockspec.package .. '-' .. rockspec.version .. '.rockspec',
         targets = choose(no_install, list('all'), list('all', 'install')),
      }
   end,
}

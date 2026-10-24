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

--- Build and install the rock that *rockspec* describes.
-- @tparam table rockspec the rockspec, as LuaRocks loaded it
-- @tparam boolean no_install whether LuaRocks asked only for a build
-- @treturn boolean `true`, or else `nil` and a message
function luke.run(rockspec, no_install)
   local status, err = require 'luke._base'.protected(function()
      return require 'luke'.make(require 'luke.rockspec'.fromrockspec(rockspec, no_install))
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

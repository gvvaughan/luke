--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {}

local mt; mt = {
   __index = {
   },

   __len = function(self)
      return self.n
   end,
}

return setmetatable({
   new = function(...)
      local r = setmetatable(pack(...), mt)
   end,
}, {
   __call = function(self, ...)
      return self.new(...)
   end,
})

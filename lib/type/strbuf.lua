--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _std = require 'std.functional.init'

local _ENV = require 'std.normalize' {
   'table.concat',
   map = _std.map,
}

local function __concat(self, x)
   self.n = self.n + 1
   self[self.n] = x
   return self
end

local mt = {
   __concat = __concat,

   __index = {
      concat = __concat,
   },

   __len = function(self)
      return self.n
   end,

   __tostring = function(self)
      return concat(map(self, tostring))
   end,
}

return setmetatable({
   new = function(...)
      return setmetatable(pack(...), mt)
   end,
}, {
   __call = function(self, ...)
      return self.new(...)
   end,
})

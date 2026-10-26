--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _std = require 'std.functional.init'

local _ENV = require 'std.normalize' {
   'string.sub',
   merged = _std.merged,
}

local mt; mt = {
   __call = function(self, x)
      return self[x]
   end,

   __concat = function(a, b)
      local r = merged(a)
      for k in next, b do
         r[k] = true
      end
      return setmetatable(r, mt)
   end,
}

return setmetatable({
   new = function(s)
      local r = {}
      for i = 1, #s do
         r[sub(s, i, i)] = true
      end
      return setmetatable(r, mt)
   end,
}, {
   __call = function(self, ...)
      return self.new(...)
   end,
})

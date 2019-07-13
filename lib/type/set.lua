--[[
 Use the source, Luke!
 Copyright (C) 2014-2019 Gary V. Vaughan
]]

local _ENV = require 'std.normalize' {}

return setmetatable({
   Set = function(...)
      local r, argu = {}, list(...)
      for i = 1, argu.n do
         r[argu[i]] = true
      end
      return r
   end,
}, {
   __call = function(self, ...)
      return self.Set(...)
   end,
}

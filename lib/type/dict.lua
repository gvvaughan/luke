--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _functional = require 'luke.functional'

local _ENV = require 'std.normalize' {
   append = _functional.append,
   destructure = next,
}

return {
   OrderedDict = function(...)
      local r, argu = {}, pack(...)
      for i = 1, argu.n do
         local k, v = destructure(argu[i])
         append(r, k)
         r[k] = v
      end
      return r
   end,
}

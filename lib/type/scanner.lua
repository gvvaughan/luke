--[[
 Use the source, Luke!
 Copyright (C) 2014-2022 Gary V. Vaughan
]]

local _ENV = require 'std.normalize' {}

local methods = {
   eof = function(self)
      return self.i >= self.n
   end,

   advance = function(self, o)
      o = int(o) or 1
      while o > 0 do
         self.i, o = self.i + 1, o - 1
         if sub(self.s, self.i, self.i) == '\n' then
            self.l = self.l + 1
         end
      end
      return self:peek()
   end,

   lookahead = function(self, s)
      return sub(self.s, self.i, self.i + len(s) -1) == s
   end,

   peek = function(self, o)
      return self[self.i + (int(o) or 0)]
   end,
}

local mt = {
   __index = function(self, name)
      local i = int(name)
      if i then
         return sub(str(self), i, i)
      end
      return methods[name]
   end,

   __len = function(self)
      return self.n
   end,

   __tostring = function(self)
      return self.s
   end,
}

return setmetatable({
   new = function(s)
      return setmetatable({s=s, i=1, l=1, n=len(s)}, mt)
   end,
}, {
   __call = function(self, ...)
      return self.new(...)
   end,
})

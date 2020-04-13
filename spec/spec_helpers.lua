--[[
 Use the source, Luke!
 Copyright (C) 2014-2019 Gary V. Vaughan
]]

int = math.tointeger or function(x)
   local i = tonumber(x)
   if i and math.ceil(i) - i == 0.0 then
      return i
   end
end

list = table.pack or function(...) return {n=select('#', ...), ...} end

nop = function() end

pack = list

set = function(...)
   local r, argu = {}, pack(...)
   for i = 1, argu.n do
      r[argu[i]] = true
   end
   return r
end

sorted = function(x)
   local r = {}
   for k, v in next, x do
      r[k] = v
   end
   table.sort(r, function(a, b)
      if int(a) then
         return int(b) == nil or a < b
      else
         return int(b) == nil and tostring(a) < tostring(b)
      end
   end)
   return r
end


unpack = table.unpack or unpack

--[[
 Use the source, Luke!
 Copyright (C) 2014-2020 Gary V. Vaughan
]]

local assert = require 'luassert'
local say = require 'say'

local function contains(state, arguments)
  local expected = arguments[1]
  local items = arguments[2]
  for _, item in next, items do
    if item == expected then
      return true
    end
  end
  return false
end

say:set_namespace("en")
say:set("assertion.contains.positive", "Expected item %s in:\n%s")
say:set("assertion.contains.negative", "Expected item %s to not be in:\n%s")
assert:register("assertion", "contains", contains, "assertion.contains.positive", "assertion.contains.negative")


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

--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

-- Load modules from this source tree, ahead of any installed copies.
-- Specl reloads this file for every example, so only prepend once.
local LIBPATH = './lib/?.lua;./lib/?/init.lua;'
if package.path:sub(1, #LIBPATH) ~= LIBPATH then
   package.path = LIBPATH .. package.path
end

require 'luke.strict':enforce()


-- Load a fresh copy of *modname*, bypassing the module cache, so that
-- it copies the current fields of every module it imports.
function reload(modname)
   local filename = assert(package.searchpath(modname, package.path))
   -- Run it in the environment of the example, so that its `require` is
   -- the example's too, and leaves no module behind for the next one.
   local chunk
   if _VERSION == 'Lua 5.1' then
      chunk = assert(loadfile(filename))
      setfenv(chunk, getfenv(1))
   else
      chunk = assert(loadfile(filename, 't', _ENV))
   end
   return chunk(modname)
end


-- Set `t[k] = v` until the next call to `restore`.
-- Specl runs this file again for every example, so keep the record of
-- replacements somewhere that every copy of these functions shares.
local registry = debug.getregistry()
registry['luke.spec.replaced'] = registry['luke.spec.replaced'] or {}
local replaced = registry['luke.spec.replaced']

function replace(t, k, v)
   replaced[#replaced + 1] = {t, k, t[k]}
   t[k] = v
end

function restore()
   for i = #replaced, 1, -1 do
      local t, k, v = unpack(replaced[i])
      t[k] = v
      replaced[i] = nil
   end
end


-- Call *fn* with *...* in-process, in an environment where it loads
-- every luke module afresh in strict mode, and return a specl Process
-- with its exit status and output.
function capture(fn, ...)
   return require 'specl.inprocess'.capture(function(fn, ...)
      require 'luke.strict':enforce()
      setfenv(fn, getfenv(1))
      return fn(...)
   end, {fn, ...})
end


-- A callable that appends its first argument to itself on every call,
-- and returns the results of passing all its arguments to *fn*, if any.
function Stub(fn)
   return setmetatable({}, {
      __index = {
         clear = function(self)
            for i = #self, 1, -1 do
               self[i] = nil
            end
         end,
      },
      __call = function(self, ...)
         self[#self + 1] = (...)
         if fn ~= nil then
            return fn(...)
         end
      end,
   })
end


list = table.pack or function(...)
   return {n=select('#', ...), ...}
end

pack = list

set = function(...)
   local r, argu = {}, pack(...)
   for i = 1, argu.n do
      r[argu[i]] = true
   end
   return r
end

unpack = table.unpack or unpack


-- Ordered tables, which luke reads as lists of one-pair tables, and keeps
-- in an OrderedMap.
OrderedMap = require 'std.prototype.orderedmap'.prototype

-- *x*, with every OrderedMap in it, however deep, as the list of tables of
-- one pair each that it was written as, so that what luke made of a list
-- can be compared with that list.
function plain(x)
   if type(x) ~= 'table' then
      return x
   end
   local r = {}
   if (getmetatable(x) or {})._keys ~= nil then
      for k, v in require 'std.prototype.orderedmap'.elems(x) do
         r[#r + 1] = {[k] = plain(v)}
      end
   else
      for k, v in next, x do
         r[k] = plain(v)
      end
   end
   return r
end

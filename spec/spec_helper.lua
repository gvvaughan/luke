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
   return assert(loadfile(filename))(modname)
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


-- Until the next call to `restore`, make luke.normalize's `exit` raise
-- 'exit STATUS', and collect its `print`, `stdout` and `stderr` output
-- into the returned table.  Reload modules after calling this, so that
-- they see the replacements.
function mock_io()
   local normalize = require 'luke.normalize'
   local output = {stdout = '', stderr = ''}

   local function writer(stream)
      return {
         write = function(self, ...)
            output[stream] = output[stream] .. table.concat {...}
            return self
         end,
      }
   end

   replace(normalize, 'exit', function(status)
      error('exit ' .. tostring(status), 0)
   end)
   replace(normalize, 'print', function(...)
      output.stdout = output.stdout .. table.concat({...}, '\t') .. '\n'
   end)
   replace(normalize, 'stdout', writer 'stdout')
   replace(normalize, 'stderr', writer 'stderr')

   -- Other modules import fatal and diagnose from luke._base, so give
   -- them versions that see the replacements too.
   local base, fresh = require 'luke._base', reload 'luke._base'
   replace(base, 'diagnose', fresh.diagnose)
   replace(base, 'fatal', fresh.fatal)
   return output
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

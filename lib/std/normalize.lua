--[[
 Normalized Lua API for Lua 5.1, 5.2 & 5.3
 Copyright (C) 2011-2017 Gary V. Vaughan
 Copyright (C) 2002-2014 Reuben Thomas <rrt@sc3d.org>
]]
--[[--
 Normalize API differences between supported Lua implementations.

 Respecting the values set in the `std.debug_init` module and the
 `_G._DEBUG` variable, inject deterministic identically behaving
 cross-implementation low-level functions into the callers environment.

 Writing Lua libraries that target several Lua implementations can be a
 frustrating exercise in working around lots of small differences in APIs
 and semantics they share (or rename, or omit).   _normalize_ provides the
 means to simply access deterministic implementations of those APIs that
 have the the same semantics across all supported host Lua
 implementations.   Each function is as thin and fast an implementation as
 is possible within that host Lua environment, evaluating to the Lua C
 implementation with no overhead where host semantics allow.

 The core of this module is to transparently set the environment up with
 a single API (as opposed to requiring caching functions from a module
 table into module locals):

      local _ENV = require 'std.normalize' {
         'package',
         'std.prototype',
         strict = 'std.strict',
      }

 It is not yet complete, and in contrast to the kepler project
 lua-compat libraries, neither does it attempt to provide you with as
 nearly compatible an API as is possible relative to some specific Lua
 implementation - rather it provides a variation of the "lowest common
 denominator" that can be implemented relatively efficiently in the
 supported Lua implementations, all in pure Lua.

 At the moment, only the functionality used by stdlib is implemented.

 @module std.normalize
]]


local ceil         = math.ceil
local concat       = table.concat
local getmetatable = getmetatable
local loadstring   = loadstring
local next         = next
local pack         = table.pack or function(...) return {n=select('#', ...), ...} end
local remove       = table.remove
local setfenv      = setfenv
local sort         = table.sort
local tointeger    = math.tointeger
local tonumber     = tonumber
local tostring     = tostring
local type         = type
local unpack       = table.unpack or unpack


local function copy(iterable)
   local r = {}
   for k, v in next, iterable or {} do
      r[k] = v
   end
   return r
end


local int = (function(f)
   if f == nil then
      -- No host tointeger implementation, use our own.
      return function(x)
         if type(x) == 'number' and ceil(x) - x == 0.0 then
            return x
         end
      end

   elseif f '1' ~= nil then
      -- Don't perform implicit string-to-number conversion!
      return function(x)
         if type(x) == 'number' then
            return tointeger(x)
         end
      end
   end

   -- Host tointeger is good!
   return f
end)(tointeger)


local function iscallable(x)
   return type(x) == 'function' and x or (getmetatable(x) or {}).__call
end


local function getmetamethod(x, n)
   return iscallable((getmetatable (x) or {})[tostring(n)])
end


local function rawlen(x)
   if type(x) ~= 'table' then
      return #x
   end

   local n = #x
   for i = 1, n do
      if x[i] == nil then
         return i - 1
      end
   end
   return n
end


local function len(x)
   local m = getmetamethod(x, '__len')
   return m and m(x) or rawlen(x)
end


if setfenv then

   local _loadstring = loadstring
   loadstring = function(s, filename, env)
      chunk, err = _loadstring(s, filename)
      if chunk ~= nil and env ~= nil then
         setfenv(chunk, env)
      end
      return chunk, err
   end

else

   loadstring = function(s, filename, env)
      return load(s, filename, "t", env)
   end

   setfenv = function() end

end


local function keysort(a, b)
   if int(a) then
      return int(b) == nil or a < b
   else
      return int(b) == nil and tostring(a) < tostring(b)
   end
end


local function str(x, roots)
   roots = roots or {}

   local function stop_roots(x)
      return roots[x] or str(x, copy(roots))
   end

   if type(x) ~= 'table' or getmetamethod(x, '__tostring') then
      return tostring(x)

   else
      local buf = {'{'}
      roots[x] = tostring(x)

      local n, keys = 1, {}
      for k in next, x do
         keys[n], n = k, n + 1
      end
      sort(keys, keysort)

      local kp
      for _, k in next, keys do
         if kp ~= nil and k ~= nil then
            buf[#buf + 1] = type(kp) == 'number' and k ~= kp + 1 and '; ' or ', '
         end
         if k == 1 or type(k) == 'number' and k - 1 == kp then
            buf[#buf + 1] = stop_roots(x[k])
         else
            buf[#buf + 1] = stop_roots(k) .. '=' .. stop_roots(x[k])
         end
         kp = k
      end
      buf[#buf + 1] = '}'

      return concat(buf)
   end
end


return setmetatable({
   append = function(seq, v)
      local n = (int(seq.n) or len(seq)) + 1
      seq.n, seq[n] = n, v
      return seq
   end,

   arg           = arg,
   assert        = assert,
   char          = string.char,
   close         = io.close,
   concat        = concat,
   copy          = copy,
   exit          = os.exit,
   format        = string.format,
   getenv        = os.getenv,
   getmetatable  = getmetatable,
   getmetamethod = getmetamethod,
   gmatch        = string.gmatch,
   gsub          = string.gsub,
   int           = int,
   iscallable    = iscallable,
   len           = len,
   lines         = io.lines,
   list          = pack,
   loadstring    = loadstring,
   match         = string.match,

   maxn = function(iterable)
      local n = 0
      for k, v in next, iterable or {} do
         local i = int(k)
         if i and i > n then
            n = i
         end
      end
      return n
   end,

   merge = function(r, ...)
      local argu = pack(...)
      for i = 1, argu.n do
         for k, v in next, argu[i] or {} do
            r[k] = r[k] or v
         end
      end
      return r
   end,

   next          = next,
   open          = io.open,
   pack          = pack,
   pcall         = pcall,

   pop = function(seq)
      if int(seq.n) then
         seq.n = seq.n - 1
      end
      return remove(seq)
   end,

   popen         = io.popen,
   print         = print,
   rawget        = rawget,
   rawset        = rawset,
   rep           = string.rep,
   rm            = os.remove,
   select        = select,
   setmetatable  = setmetatable,
   sort          = sort,
   stderr        = io.stderr,
   stdout        = io.stdout,
   str           = str,
   sub           = string.sub,
   tmpname       = os.tmpname,
   tonumber      = tonumber,
   type          = type,

   unpack = function(seq, i, j)
      return unpack(seq, int(i) or 1, int(j) or int(seq.n) or len(seq))
   end,

   write         = io.write,
}, {
   --- Metamethods
   -- @section metamethods

   --- Normalize caller's lexical environment.
   --
   -- Using 'std.strict' when available and selected, otherwise a (Lua 5.1
   -- compatible) function to set the given environment.
   --
   -- With an empty table argument, the core (not-table) normalize
   -- functions are loaded into the callers environment.   For consistent
   -- behaviour between supported host Lua implementations, the result
   -- must always be assigned back to `_ENV`.   Additional core modules
   -- must be named to be loaded at all (i.e. no 'debug' table unless it
   -- is explicitly listed in the argument table).
   --
   -- Additionally, external modules are loaded using `require`, with `.`
   -- separators in the module name translated to nested tables in the
   -- module environment. For example 'std.prototype' in the usage below
   -- is equivalent to:
   --
   --       local std = {prototype=require 'std.prototype'}
   --
   -- And finally, you can assign a loaded module to a specific symbol
   -- with `key=value` syntax.   For example 'std.strict' in the usage
   -- below is equivalent to:
   --
   --       local strict = require 'std.strict'
   -- @function __call
   -- @tparam table env environment table
   -- @tparam[opt=1] int level stack level for `setfenv`, 1 means set
   --    caller's environment
   -- @treturn table *env* with this module's functions merge id.   Assign
   --    back to `_ENV`
   -- @usage
   --    local _ENV = require 'std.normalize' {
   --       'string',
   --       'std.prototype',
   --       strict = 'std.strict',
   --    }
   __call = function(self, env, level)
      local userenv, level = copy(self), level or 1
      for name, value in next, env do
         if int(name) and type(value) == 'string' then
            for k, v in next, require(value) do
               userenv[k] = userenv[k] or v
            end
         else
            userenv[name] = value
         end
      end
      setfenv(level + 1, userenv)
      return userenv
   end,
})

--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke.functional',
}


-- Platform with 'uname -s' output that matches a key in this dict will get all
-- platforms subtables that match the associated list of generic platform names.
local CANON = {
   ['AIX']       = list('aix', 'unix'),
   ['FreeBSD']   = list('freebsd', 'bsd', 'unix'),
   ['OpenBSD']   = list('openbsd', 'bsd', 'unix'),
   ['NetBSD']    = list('netbsd', 'bsd', 'unix'),
   ['Darwin']    = list('macosx', 'bsd', 'unix'),
   ['Linux']     = list('linux', 'unix'),
   ['SunOS']     = list('solaris', 'unix'),
   ['^CYGWIN']   = list('cygwin', 'unix'),
   ['^MSYS']     = list('msys', 'cygwin', 'unix'),
   ['^Windows']  = list('win32', 'windows'),
   ['^MINGW']    = list('mingw32', 'win32', 'windows'),
   ['^procnto']  = list('qnx'),
   ['QNX']       = list('qnx'),
   ['Haiku']     = list('haiku', 'unix'),
}


-- The set of all available generic platform names.
local ALLPLATFORMS = foldl(values(CANON), function(acc, platforms)
   each(platforms, function(v)
      acc[v] = true
   end)
end)


local function match_uname(canon, uname, x)
   return match(uname, x) and canon[x]
end


local function toplatforms(canon, uname)
   local literalkeys, patternkeys = partition(keys(canon), function(k)
      return sub(k, 1, 1) ~= '^'
   end)
   return (pluck(literalkeys, canon) or {})[uname]
      or dropuntil(patternkeys, bind(match_uname, {canon, uname}))
      or list('unix')
end


-- The generic platform names associated with the host's uname.
local supported = toplatforms(CANON, popen('uname -s'):read '*l')


-- Default predicate for `filter_arguments`, using generic platforms collected
-- from `CANON` above.
local function isplatform(x)
   return ALLPLATFORMS[x] ~= nil
end


-- The tables in *platforms* for each of the *supported* platforms, most
-- specific first, or else a table of its other elements as defaults.
local function selected(platforms, supported, isplatform)
   local matches = map(filter(supported, bind(get, {platforms})), bind(get, {platforms}))
   return choose(isempty(matches), function()
      return {pluck(reject(keys(platforms), isplatform), platforms)}
   end, function()
      return matches
   end)
end


-- The tables that apply to dict *t* on the *supported* platforms, least
-- specific first: *t* itself without its `platforms`, then its table
-- there for each supported platform, or else its defaults.
local function layers(t, using, predicate)
   local supported, isplatform = using or supported, predicate or isplatform
   local own = pluck(reject(keys(t), 'platforms'), t) or {}
   return {own, unpack(reversed(selected(t.platforms or {}, supported, isplatform)))}
end


-- Recursively narrow any dict with elements named `platforms`, putting
-- only sub-elements that match one of the listed platforms.  If there
-- are no matching sub-elements, then all non-platform sub-elements are
-- kept instead.  The list entries of each match follow those of the
-- dict, least specific first, while any other element of a match takes
-- precedence over the same element of a less specific match, or of the
-- dict itself.  An element named in *opaque* is left alone, for its
-- normalizer to narrow.
local function filter_platforms(t, using, predicate, opaque)
   local supported, isplatform, opaque = using or supported, predicate or isplatform, opaque or {}
   local function narrow(v, k)
      return choose(opaque[k] or not istable(v), function()
         return v
      end, function()
         return filter_platforms(v, supported, isplatform, opaque)
      end)
   end

   -- A platform table may have platforms of its own.
   local tables = map(layers(t, supported, isplatform), function(layer)
      return layer.platforms and narrow(layer) or layer
   end)
   local r = foldl(tables, {}, function(r, layer)
      each(layer, function(v)
         r[len(r) + 1] = narrow(v)
      end)
   end)
   return foldl(reversed(tables), r, function(r, layer)
      each(filter(keys(layer), function(k)
         return not islistkey(layer, k) and r[k] == nil
      end), function(k)
         r[k] = narrow(layer[k], k)
      end)
   end)
end


return {
   filter_platforms = filter_platforms,
   isplatform = isplatform,
   layers = layers,
   platforms = supported,
   toplatforms = toplatforms,
}

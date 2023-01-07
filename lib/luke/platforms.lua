--[[
 Use the source, Luke!
 Copyright (C) 2014-2023 Gary V. Vaughan
]]

local _ENV = require 'std.normalize' {
   'std.functional',
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
local ALLPLATFORMS = reduce(values(CANON), function(acc, platforms)
   map(platforms, function(v)
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
      or dropuntil(map(patternkeys, bind(match_uname, {canon, uname})))
      or list('unix')
end


-- The generic platform names associated with the host's uname.
local supported = toplatforms(CANON, popen('uname -s'):read '*l')


-- Default predicate for `filter_arguments`, using generic platforms collected
-- from `CANON` above.
local function isplatform(x)
   return ALLPLATFORMS[x] ~= nil
end


-- Recursively narrow any dict with elements named `platform`, putting only
-- sub-elements that match one of the listed platforms.  If there are no
-- matching sub-elements, then all non-platform sub-elements are kept instead.
local function filter_platforms(t, using, predicate)
   local r, supported, isplatform = {}, using or supported, predicate or isplatform
   for k, v in next, t do
      if k == 'platforms' then
         local matches = filter(supported, bind(get, {v}))
         local default = except(keys(v), isplatform)
         merge(r, hoist(matches, v) or pluck(default, v))
      elseif istable(v) then
         r[k] = filter_platforms(v, supported)
      else
         r[k] = r[k] or v
      end
   end
   return r
end


return {
   filter_platforms = filter_platforms,
   platforms = supported,
   toplatforms = toplatforms,
}

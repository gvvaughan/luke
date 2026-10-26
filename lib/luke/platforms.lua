--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _functional = require 'luke.functional'
local _std = require 'std.functional.init'

local _ENV = require 'std.normalize' {
   'io.popen',
   'string.match',
   'string.sub',
   get = _functional.get,
   islistkey = _functional.islistkey,
   istable = _functional.istable,
   keys = _functional.keys,
   set = _functional.set,
   any = _std.any,
   bind = _std.bind,
   default = _std.default,
   each = _std.each,
   either = _std.either,
   except = _std.except,
   filter = _std.filter,
   firstof = _std.firstof,
   flatten = _std.flatten,
   foldl = _std.foldl,
   isempty = _std.isempty,
   map = _std.map,
   reject = _std.reject,
   reversed = _std.reversed,
   values = _std.values,
}


-- Platform with 'uname -s' output that matches a key in this dict will get all
-- platforms subtables that match the associated list of generic platform names.
local CANON = {
   ['AIX']       = pack('aix', 'unix'),
   ['FreeBSD']   = pack('freebsd', 'bsd', 'unix'),
   ['OpenBSD']   = pack('openbsd', 'bsd', 'unix'),
   ['NetBSD']    = pack('netbsd', 'bsd', 'unix'),
   ['Darwin']    = pack('macosx', 'bsd', 'unix'),
   ['Linux']     = pack('linux', 'unix'),
   ['SunOS']     = pack('solaris', 'unix'),
   ['^CYGWIN']   = pack('cygwin', 'unix'),
   ['^MSYS']     = pack('msys', 'cygwin', 'unix'),
   ['^Windows']  = pack('win32', 'windows'),
   ['^MINGW']    = pack('mingw32', 'win32', 'windows'),
   ['^procnto']  = pack('qnx'),
   ['QNX']       = pack('qnx'),
   ['Haiku']     = pack('haiku', 'unix'),
}


-- The set of all available generic platform names.
local ALLPLATFORMS = set(flatten(values(CANON)))


-- The platforms of *uname* in *canon*, by its exact name.
local function by_name(canon, uname)
   return canon[uname]
end


local function ispatternkey(k)
   return sub(k, 1, 1) == '^'
end


-- The platforms of *uname* in *canon*, by the first '^pattern' key that
-- it matches.
local function by_pattern(canon, uname)
   return firstof(filter(keys(canon), ispatternkey), function(k)
      return match(uname, k) and canon[k]
   end)
end


-- Anything else is a Unix.
local function by_default()
   return pack('unix')
end


local toplatforms = any(by_name, by_pattern, by_default)


-- The generic platform names associated with the host's uname.
local supported = toplatforms(CANON, popen('uname -s'):read '*l')


-- Default predicate for `filter_arguments`, using generic platforms collected
-- from `CANON` above.
local function isplatform(x)
   return ALLPLATFORMS[x] ~= nil
end


-- The tables in *platforms* for each of the *supported* platforms, most
-- specific first, or else a table of its other elements as defaults, if
-- it has any.
local function selected(platforms, supported, isplatform)
   local matches = reject(map(supported, bind(get, {platforms})), nil)
   local defaults = reject({except(platforms, isplatform)}, isempty)
   return either(matches, defaults)
end


-- The tables that apply to dict *t* on the *supported* platforms, least
-- specific first: *t* itself without its `platforms`, then its table
-- there for each supported platform, or else its defaults.
local function layers(t, using, predicate)
   local supported, isplatform = default(using, supported), default(predicate, isplatform)
   local own = except(t, 'platforms')
   return {own, unpack(reversed(selected(t.platforms or {}, supported, isplatform)))}
end


-- Add the list entries of *layer* to the end of *r*, narrowed.
local function append_entries(r, layer, narrow)
   each(layer, function(v)
      r[len(r) + 1] = narrow(v)
   end)
end


-- Set the other elements of *layer* in *r*, narrowed, in place of the
-- same elements of any earlier layer.
local function overlay_fields(r, layer, narrow)
   each(reject(keys(layer), bind(islistkey, {layer})), function(k)
      r[k] = narrow(layer[k], k)
   end)
end


-- Recursively narrow any dict with elements named `platforms`, putting
-- only sub-elements that match one of the listed platforms.  If there
-- are no matching sub-elements, then all non-platform sub-elements are
-- kept instead.  The list entries of each match follow those of the
-- dict, least specific first, while any other element of a match takes
-- precedence over the same element of a less specific match, or of the
-- dict itself.  An element named in *opaque* is left alone, for its
-- normalizer to narrow.  Everything is given, so that there is no need to
-- pass over what is not.
local function narrow_for(t, supported, isplatform, opaque)
   local function narrow(v, k)
      if opaque[k] or not istable(v) then
         return v
      end
      return narrow_for(v, supported, isplatform, opaque)
   end

   -- A platform table may have platforms of its own.
   local tables = map(layers(t, supported, isplatform), function(layer)
      if layer.platforms then
         return narrow(layer)
      end
      return layer
   end)

   return foldl(tables, {}, function(r, layer)
      append_entries(r, layer, narrow)
      overlay_fields(r, layer, narrow)
   end)
end


-- *t* narrowed for the *using* platforms, that are those of this system
-- by default, as *predicate*, by default for the platforms that luke
-- knows, says which keys name them, and leaving alone any element named
-- in *opaque*.
local function filter_platforms(t, using, predicate, opaque)
   return narrow_for(t, default(using, supported), default(predicate, isplatform), default(opaque, {}))
end


-- *t* narrowed for this system, leaving alone any element named in the
-- set *opaque*.
local function narrow_platforms(t, opaque)
   return narrow_for(t, supported, isplatform, opaque)
end


return {
   filter_platforms = filter_platforms,
   isplatform = isplatform,
   layers = layers,
   narrow_platforms = narrow_platforms,
   platforms = supported,
   toplatforms = toplatforms,
}

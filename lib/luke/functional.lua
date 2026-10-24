--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

-- What luke needs that std.functional does not have: the functions of
-- std.functional.init, and these.

local _ENV = require 'luke.normalize' {
   'std.functional.init',
   sf = require 'std.functional.init',
   destructure = next,
   isfile = function(x) return io.type(x) == 'file' end,
}


-- Call *fn* with the arguments.
local function call(fn, ...)
   return fn(...)
end


-- Call *fn* with the items of the list *argu*, even trailing nils.
local function apply(fn, argu)
   return fn(unpack(argu))
end


-- Call a branch if it is callable, otherwise return it as it is.
local function force(branch, ...)
   if iscallable(branch) then
      return branch(...)
   end
   return branch
end


local function keys(t)
   local r, n = {}, 0
   for k in next, t do
      n = n + 1
      r[n] = k
   end
   r.n = n
   return r
end


-- The set of the items of *seq*, as a table with each of them a key
-- for `true`.
local function set(seq)
   local r = {}
   each(seq, function(v)
      r[v] = true
   end)
   return r
end


local extras = {
   apply = apply,

   call = call,

   destructure = destructure,

   force = force,

   get = function(dict, key)
      return (dict or {})[key]
   end,

   isfile = isfile,

   -- Whether *k* indexes a list entry of *t*, rather than naming a field.
   islistkey = function(t, k)
      return type(k) == 'number' and int(k) == k and k >= 1 and k <= len(t)
   end,

   isnonzero = function(x)
      return x ~= 0
   end,

   isstring = function(x)
      return type(x) == 'string'
   end,

   istable = function(x)
      return type(x) == 'table'
   end,

   keys = keys,

   -- The value paired with *key* in the list of one-pair tables *om*.
   ordered_get = function(om, key)
      local r
      each(om or {}, function(pair)
         if pair[key] ~= nil then
            r = pair[key]
         end
      end)
      return r
   end,

   -- The key of each pair in the list of one-pair tables *om*, in order.
   ordered_keys = function(om)
      return foldl(om or {}, list(), function(r, pair)
         return append(r, (destructure(pair)))
      end)
   end,

   -- A copy of the list of one-pair tables *om*, with *fn* applied to
   -- the value of each pair.
   ordered_mapvalues = function(om, fn)
      return foldl(om or {}, {}, function(r, pair)
         local k, v = destructure(pair)
         r[#r + 1] = {[k] = fn(v)}
      end)
   end,

   -- Merge the lists of one-pair tables *...*, skipping nils, into a new
   -- list of pairs in the order each key first appears, each with the
   -- value of the last pair for that key.
   ordered_merge = function(...)
      local at = {}
      return foldl(compact(list(...)), {}, function(r, pairs)
         foldl(pairs, r, function(r, pair)
            local k, v = destructure(pair)
            at[k] = at[k] or #r + 1
            r[at[k]] = {[k] = v}
         end)
      end)
   end,

   -- The pairs in the list of one-pair tables *om* whose keys are in
   -- *keylist*, in the order of *om*.
   ordered_pluck = function(om, keylist)
      local wanted = set(keylist)
      return reject(om or {}, function(pair)
         return not wanted[(destructure(pair))]
      end)
   end,

   set = set,

   -- The keys of *iterable* in a deterministic order: numbers, such as
   -- the indices of list entries, in numeric order, then strings, then
   -- any others by their string form.
   sorted_keys = function(iterable)
      local rank = {number = 1, string = 2}
      local r = keys(iterable or {})
      sort(r, function(a, b)
         local ra, rb = rank[type(a)] or 3, rank[type(b)] or 3
         return ra < rb or ra == rb and (ra < 3 and a < b or ra == 3 and str(a) < str(b))
      end)
      return r
   end,
}


return merged(sf, extras)

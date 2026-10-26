--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

-- What luke needs that std.functional and std.normalize do not have:
-- lists that keep their length in `n`, sets, and the lists of one-pair
-- tables that keep the order of a lukefile's tables.

local _std = require 'std.functional.init'

local _ENV = require 'std.normalize' {
   int = 'math.tointeger',
   destructure = next,
   compact = _std.compact,
   each = _std.each,
   foldl = _std.foldl,
   reject = _std.reject,
}


-- Add *v* to the end of the list *seq*, which keeps its length in `n`.
local function append(seq, v)
   local n = (int(seq.n) or len(seq)) + 1
   seq.n, seq[n] = n, v
   return seq
end


-- Remove and return the last item of the list *seq*, which keeps its
-- length in `n`.
local function pop(seq)
   local n = seq.n or len(seq)
   local r = seq[n]
   seq[n] = nil
   if int(seq.n) and seq.n > 0 then
      seq.n = seq.n - 1
   end
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


return {
   append = append,

   pop = pop,

   set = set,

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
      return foldl(om or {}, pack(), function(r, pair)
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
      return foldl(compact(pack(...)), {}, function(r, pairs)
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
}

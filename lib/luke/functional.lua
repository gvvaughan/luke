--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

-- What luke needs that std.functional does not have: the functions of
-- std.functional.init, and these.

local sf = require 'std.functional.init'

local _ENV = require 'std.normalize' {
   'string.gmatch',
   'table.sort',
   host_format = 'string.format',
   int = 'math.tointeger',
   compact = sf.compact,
   each = sf.each,
   foldl = sf.foldl,
   merged = sf.merged,
   reject = sf.reject,
   destructure = next,
   isfile = function(x) return io.type(x) == 'file' end,
}


-- Call *fn* with the arguments.
local function call(fn, ...)
   return fn(...)
end


-- Call *fn* with the items of the list *argu*, even trailing nils.
local function apply(fn, argu)
   return fn(unpack(argu, 1, argu.n or len(argu)))
end


-- Call a branch if it is callable, otherwise return it as it is.
local function force(branch, ...)
   if iscallable(branch) then
      return branch(...)
   end
   return branch
end


-- Lua 5.1 formats only strings and numbers with `%s`, so convert every
-- other `%s` argument with tostring first, as later Luas do.  This
-- is a gap in std.normalize, whose string.format is the host's.
local format = (function(f)
   if pcall(f, '%s', nil) then
      return f
   end

   return function(fmt, ...)
      local argu, i = pack(...), 0
      for conversion in gmatch(fmt, '%%[-+ #0]*%d*%.?%d*([%a%%])') do
         if conversion ~= '%' then
            i = i + 1
            if conversion == 's' then
               argu[i] = tostring(argu[i])
            end
         end
      end
      return f(fmt, unpack(argu, 1, argu.n))
   end
end)(host_format)


-- Add *v* to the end of the list *seq*, which keeps its length in `n`.
local function append(seq, v)
   local n = (int(seq.n) or len(seq)) + 1
   seq.n, seq[n] = n, v
   return seq
end


-- Load the chunk *s*, to run in the environment *env*.
local function loadenv(s, chunkname, env)
   local chunk, err = load(s, chunkname)
   if chunk ~= nil then
      setfenv(chunk, env)
   end
   return chunk, err
end


-- The largest integer key of *iterable*.
local function maxn(iterable)
   local n = 0
   for k in next, iterable or {} do
      local i = int(k)
      if i and i > n then
         n = i
      end
   end
   return n
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
   append = append,

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

   format = format,

   keys = keys,

   loadenv = loadenv,

   maxn = maxn,

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

   pop = pop,

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

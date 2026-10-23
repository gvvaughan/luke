--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   destructure = next,
   error = error,
   isfile = function(x) return io.type(x) == 'file' end,
   wrap = coroutine.wrap,
   yield = coroutine.yield,
}


local function apply(fn, argu)
   assert(fn ~= nil, 'cannot apply nil-valued function')
   if iscallable(fn) then
      return fn(unpack(argu))
   end
   return fn
end


local function call(fn, ...)
   assert(fn ~= nil, 'cannot call nil-valued function')
   if iscallable(fn) then
      return fn(...)
   end
   return fn
end


-- *consequent* if *test* is truthy, otherwise *alternative*, where
-- either may be falsy, unlike in `test and consequent or alternative`.
-- Like `cond`, a callable leg is called with *test* only when it is
-- chosen, so pass side effects as functions.
local function choose(test, consequent, alternative)
   local leg = alternative
   if test then
      leg = consequent
   end
   if leg ~= nil then
      return call(leg, test)
   end
end


-- Call *visit* with all the results of each item of *seq*, until it
-- returns something truthy, and then return true.  The items of a table
-- are its values from 1 to its `n` field or length, so holes are
-- visited; those of an iterator function end with its first nil result.
local function walk(seq, visit)
   if type(seq) == 'function' then
      local function loop(...)
         if ... ~= nil then
            if visit(...) then
               return true
            end
            return loop(seq())
         end
      end
      return loop(seq())
   end
   for i = 1, int(seq.n) or len(seq) do
      if visit(seq[i]) then
         return true
      end
   end
end


local function id(...)
   return ...
end


-- *x*, unless it is nil, then *d*.  Only nil is missing, so false is a
-- value, and so is an empty table.
local function default(x, d)
   if x == nil then
      return d
   end
   return x
end


-- The first of *...*, even if it is nil, or else *d* if there is none.
local function given(d, ...)
   if select('#', ...) == 0 then
      return d
   end
   return (...)
end


local function isnonnil(x)
   return x ~= nil
end


-- Only a function is a predicate, anything else is a value to compare
-- with, as `==`.  Not `choose`, which would call a function-valued *x*
-- rather than return it.
local function topredicate(x)
   if type(x) == 'function' then
      return x
   end
   return function(y)
      return y == x
   end
end


-- A function to list the items of *seq* that pass a predicate, or those
-- that fail it.
local function keeper(passes)
   return function(seq, predicate)
      predicate = topredicate(predicate)
      local r = list()
      walk(seq, function(...)
         if choose(predicate(...), passes, not passes) then
            append(r, (...))
         end
      end)
      return r
   end
end

local filter, reject = keeper(true), keeper(false)


-- Call *fn* with every result of each item of *seq*, for its effects.
local function each(seq, fn)
   walk(seq, function(...)
      fn(...)
   end)
end


-- An iterator function over the flat sequence of what *t* holds, in
-- order: it goes into the tables among its elements, and gives what
-- they hold instead.
local function flatiter(t)
   local function visit(x)
      if type(x) == 'table' then
         walk(x, visit)
      else
         yield(x)
      end
   end
   return wrap(function() visit(t) end)
end


local function flatten(...)
   local r = list()
   each(flatiter(reject(list(...), nil)), function(v)
      append(r, v)
   end)
   return r
end


local function keys(iterable)
   local r = list()
   for k in next, iterable or {} do
      append(r, k)
   end
   return r
end


local function foldl(seq, acc, fn)
   if fn == nil then
      acc, fn = {}, acc
   end
   walk(seq, function(...)
      local r = fn(acc, ...)
      if r ~= nil then
         acc = r
      end
   end)
   return acc
end


-- The first result of calling *fn* with each item of *seq* that passes
-- *predicate*, without calling it for later items.  The predicate is
-- called with all the results.  If it is left out, *fn* is passed in its
-- place, and anything truthy passes; but nil is a value, which is
-- compared with the results.
local function firstof(seq, predicate, fn)
   if fn == nil then
      predicate, fn = id, predicate
   end
   predicate = topredicate(predicate)
   local found
   local function test(...)
      if predicate(...) then
         found = ...
         return true
      end
   end
   walk(seq, function(...) return test(fn(...)) end)
   return found
end


-- *x* after calling *fn* with it, and then with each result, until the
-- result is what it was called with.  It is an error if that has not
-- happened after *limit* calls, which is 1000 if left out.
local function converge(x, limit, fn)
   if fn == nil then
      limit, fn = 1000, limit
   end
   for _ = 1, limit do
      local r = fn(x)
      if r == x then
         return x
      end
      x = r
   end
   error(format('no convergence after %d calls', limit), 2)
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


-- Whether *x* is a table with no elements, counting a `list` with
-- only its `n = 0` field as empty.
local function isempty(x)
   if type(x) ~= 'table' then
      return false
   end
   local k = next(x)
   return k == nil or (k == 'n' and x.n == 0 and next(x, k) == nil)
end


-- *x*, unless it is nil or an empty table, in which case *default*.
-- Unlike `x or default`, an empty table counts as nothing, and false
-- is a value like any other.
local function either(x, d)
   if x == nil or isempty(x) then
      return d
   end
   return x
end


-- The position of the first item of *seq* that passes *predicate*,
-- which is anything truthy if it is left out, and nil, if it is given,
-- is compared with the items.
local function indexof(seq, ...)
   local predicate = topredicate(given(id, ...))
   local i, found = 0, nil
   walk(seq, function(...)
      i = i + 1
      if predicate(...) then
         found = i
         return true
      end
   end)
   return found
end


-- The items of the lists that *fn* returns for each item of *seq*, or
-- nil for none, in a list.
local function flatmap(seq, fn)
   local r = list()
   walk(seq, function(...)
      local items = fn(...)
      if items ~= nil then
         each(items, function(item)
            append(r, item)
         end)
      end
   end)
   return r
end


-- A sorted copy of *seq*, as a list, that keeps the order of items that
-- *cmp*, by default `<`, orders neither before the other.
local function sorted(seq, cmp)
   cmp = default(cmp, function(a, b)
      return a < b
   end)
   local decorated = {}
   walk(seq, function(v)
      decorated[#decorated + 1] = {v, #decorated + 1}
   end)
   sort(decorated, function(a, b)
      if cmp(a[1], b[1]) then
         return true
      elseif cmp(b[1], a[1]) then
         return false
      end
      return a[2] < b[2]
   end)
   local r = list()
   for i = 1, #decorated do
      append(r, decorated[i][1])
   end
   return r
end


return {
   -- A function that calls each of *...* with its arguments, lazily,
   -- until one returns something that is not nil, and returns all its
   -- results, or those of the last if none do.
   any = function(...)
      local fns = list(...)
      return function(...)
         local r = list()
         for i = 1, fns.n do
            r = list(fns[i](...))
            if r[1] ~= nil then
               break
            end
         end
         return unpack(r, 1, r.n)
      end
   end,

   apply = apply,

   bind = function(fn, bound)
      local n = bound.n or maxn(bound)

      return function (...)
         local argu, unbound = copy(bound), list(...)

         local i = 1
         for j = 1, unbound.n do
            while argu[i] ~= nil do
               i = i + 1
            end
            argu[i], i = unbound[j], i + 1
         end
         argu.n = max(n, i - 1)

         return apply(fn, argu)
      end
   end,

   call = call,

   -- The branch for *s* as a key, or for the first `{pattern, branch}`
   -- pair in the array part of *branches* whose pattern matches the
   -- string *s*, anchored, or else `branches.default`.  A callable
   -- branch is called with *s*, or the captures of the pattern.
   case = function(s, branches)
      if branches[s] ~= nil then
         return call(branches[s], s)
      end
      if type(s) == 'string' then
         for i = 1, len(branches) do
            local pattern, branch = unpack(branches[i], 1, 2)
            local captures = list(match(s, '^' .. pattern .. '$'))
            if captures[1] ~= nil then
               return apply(branch, captures)
            end
         end
      end
      local default = branches.default
      if iscallable(default) then
         return call(default, s)
      end
      return default
   end,

   choose = choose,

   -- The branch of the first `{test, branch}` clause in *...* whose
   -- test is truthy, called with the test if it is callable.
   cond = function(...)
      local clauses = list(...)
      for i = 1, clauses.n do
         local expr, consequence = unpack(clauses[i], 1, 2)
         if expr then
            return call(consequence, expr)
         end
      end
   end,

   contains = function(seq, predicate)
      return walk(seq, topredicate(predicate)) == true
   end,

   converge = converge,

   default = default,

   destructure = destructure,

   each = each,

   either = either,

   -- A copy of *t* without the keys that match *predicate*, a function
   -- to call with a key, or else a key to compare with.
   except = function(t, predicate)
      predicate = topredicate(predicate)
      local r = {}
      for k, v in next, t do
         if not predicate(k) then
            r[k] = v
         end
      end
      return r
   end,

   filter = filter,

   firstof = firstof,

   flatmap = flatmap,

   flatten = flatten,

   foldl = foldl,

   get = function(dict, key)
      return (dict or {})[key]
   end,

   hoist = function(keylist, dict)
      local r = {}
      each(keylist, function(key)
         merge(r, dict[key])
      end)
      return either(r, nil)
   end,

   id = id,

   indexof = indexof,

   isempty = isempty,

   isfile = isfile,

   isfunction = function(x)
      return type(x) == 'function'
   end,

   -- Whether *k* indexes a list entry of *t*, rather than naming a field.
   islistkey = function(t, k)
      return type(k) == 'number' and int(k) == k and k >= 1 and k <= len(t)
   end,

   isnil = function(x)
      return x == nil
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

   map = function(seq, block)
      local r = list()
      walk(seq, function(...)
         append(r, (block(...)))
      end)
      return r
   end,

   -- *iterable* with the result of calling *block* with each value,
   -- which can be false, and leaves out a key for nil.
   mapvalues = function(iterable, block)
      local r = {}
      for k, v in next, iterable or {} do
         r[k] = block(v)
      end
      return r
   end,

   nop = function() end,

   -- The value paired with *key* in the list of one-pair tables *om*.
   ordered_get = function(om, key)
      return foldl(om or {}, nil, function(_, pair)
         return pair[key]
      end)
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
      return foldl(reject(list(...), nil), {}, function(r, pairs)
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

   partition = function(seq, predicate)
      predicate = topredicate(predicate)
      local r, s = list(), list()
      walk(seq, function(...)
         append(choose(predicate(...), r, s), (...))
      end)
      return r, s
   end,

   -- A table of just the entries of *t* for the keys in *keylist*.
   pluck = function(t, keylist)
      local r = {}
      each(keylist, function(key)
         r[key] = t[key]
      end)
      return r
   end,

   reject = reject,

   -- A copy of *seq* in reverse order.
   reversed = function(seq)
      local items, n = {}, 0
      walk(seq, function(v)
         n = n + 1
         items[n] = v
      end)
      local r = {n = n}
      for i = 1, n do
         r[n - i + 1] = items[i]
      end
      return r
   end,

   set = set,

   -- Whether any item of *seq* passes *predicate*, which is anything
   -- truthy if it is left out, and nil, if it is given, is compared with
   -- the items.
   some = function(seq, ...)
      return walk(seq, topredicate(given(id, ...))) == true
   end,

   sorted = sorted,

   -- The keys of *iterable* in a deterministic order: numbers, such as
   -- the indices of list entries, in numeric order, then strings, then
   -- any others by their string form.
   sorted_keys = function(iterable)
      local rank = {number = 1, string = 2}
      local r = keys(iterable)
      sort(r, function(a, b)
         local ra, rb = rank[type(a)] or 3, rank[type(b)] or 3
         return ra < rb or ra == rb and (ra < 3 and a < b or ra == 3 and str(a) < str(b))
      end)
      return r
   end,

   values = function(iterable)
      local r = list()
      for _, v in next, iterable or {} do
         append(r, v)
      end
      return r
   end,
}

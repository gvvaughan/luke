local _ENV = require 'std.normalize' {
   destructure = next,
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


local function wrapnonnil(iterator)
   return function(...)
      local r = list(iterator(...))
      if r[1] ~= nil then
         return r
      end
   end
end


local function each(seq)
   if type(seq) == 'function' then
      return wrapnonnil(seq)
   end
   local i, n = 0, int(seq.n) or len(seq)
   return function()
      if i < n then
         i = i + 1
         return list(seq[i])
      end
   end
end


local function eq(x)
   return function(y)
      return x == y
   end
end


local function isnonnil(x)
   return x ~= nil
end


local function mkpredicate(x)
   return type(x) == 'function' and x or eq(x)
end


local function except(seq, predicate)
   predicate = mkpredicate(predicate)
   local r = {}
   for valu in each(seq) do
      if not predicate(unpack(valu)) then
         r[#r + 1] = unpack(valu)
      end
   end
   return r
end


local function visit(x)
   if type(x) == 'table' then
      for valu in each(x) do
         visit(unpack(valu))
      end
   else
      yield(x)
   end
end


local function flatten(...)
   local r = {}
   for v in wrap(visit), except(list(...), nil) do
      r[#r + 1] = v
   end
   return r
end


return {
   any = function(seq)
      for valu in each(seq) do
         if unpack(valu) then
            return true
         end
      end
      return false
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
         bound.n = n >= i and n or i - 1

         return apply(fn, argu)
      end
   end,

   call = call,

   case = function(s, branches)
      if branches[s] ~= nil then
         return call(branches[s], s)
      end
      local DEFAULT = 1
      for pattern, fn in next, branches do
         if pattern ~= DEFAULT then
            local argu = list(match(s, '^' .. pattern .. '$'))
            if argu[1] ~= nil then
               return apply(fn, argu)
            end
         end
      end
      local default = branches[DEFAULT]
      if iscallable(default) then
         return call(default, s)
      end
      return default
   end,

   cond = function(...)
      for clauseu in each(list(...)) do
         local expr, consequence = destructure(unpack(clauseu))
         if expr then
            return call(consequence, expr)
         end
      end
   end,

   contains = function(seq, predicate)
      if type(predicate) ~= 'function' then
         predicate = eq(predicate)
      end
      for valu in each(seq) do
         if predicate(unpack(valu)) then
            return true
         end
      end
   end,

   destructure = destructure,

   dropuntil = function(seq, predicate, block)
      if block == nil then
         predicate, block = isnonnil, predicate
      end
      if block ~= nil then
         for valu in each(seq) do
            local r = list(block(unpack(valu)))
            if predicate(unpack(r)) then
               return unpack(r)
            end
         end
      else
         for r in each(seq) do
            if predicate(unpack(r)) then
               return unpack(r)
            end
         end
      end
   end,

   except = except,

   filter = function(seq, predicate)
      predicate = mkpredicate(predicate)
      local r = {}
      for valu in each(seq) do
         if predicate(unpack(valu)) then
            r[#r + 1] = unpack(valu)
         end
      end
      return r
   end,

   flatten = flatten,

   foldkeys = function(keymap, dict, combinator)
      local r = {}
      for k, v in next, dict or {} do
         local key = keymap[k]
         if key then
            r[key] = combinator(v, dict[key])
         else
            r[k] = r[k] or v
         end
      end
      return r
   end,

   get = function(dict, key)
      return (dict or {})[key]
   end,

   hoist = function(keylist, dict)
      local r = {}
      for keyu in each(keylist) do
         merge(r, dict[unpack(keyu)])
      end
      return next(r) and r or nil
   end,

   id = function(...)
      return ...
   end,

   isempty = function(x)
      return type(x) == 'table' and not next(x)
   end,

   isfile = isfile,

   isfunction = function(x)
      return type(x) == 'function'
   end,

   isnil = function(x)
      return x == nil
   end,

   isstring = function(x)
      return type(x) == 'string'
   end,

   istable = function(x)
      return type(x) == 'table'
   end,

   isnonzero = function(x)
      return x ~= 0
   end,

   keys = function(iterable)
      local r = list()
      for k in next, iterable or {} do
         append(r, k)
      end
      return r
   end,

   map = function(seq, block)
      local r = list()
      for valu in each(seq) do
         append(r, block(unpack(valu)))
      end
      return r
   end,

   mapvalues = function(iterable, block)
      local r = {}
      for k, v in next, iterable or {} do
         r[k] = block(v) or v
      end
      return r
   end,

   nop = function() end,

   partition = function(seq, block)
      local r, s = list(), list()
      for valu in each(seq) do
         append(block(unpack(valu)) and r or s, unpack(valu))
      end
      return r, s
   end,

   pluck = function(keylist, dict)
      local r = {}
      for keyu in each(keylist) do
         local key = unpack(keyu)
         r[key] = dict[key]
      end
      return next(r) and r or nil
   end,

   reduce = function(seq, acc, block)
      if block == nil then
         acc, block = {}, acc
      end
      for valu in each(seq) do
         acc = block(acc, unpack(valu)) or acc
      end
      return acc
   end,

   values = function(iterable)
      local r = list()
      for _, v in next, iterable or {} do
         append(r, v)
      end
      return r
   end,

   zip_with = function(iterable, block)
      local r = list()
      for k, v in next, iterable or {} do
         append(r, block(k, v))
      end
      return r
   end,
}

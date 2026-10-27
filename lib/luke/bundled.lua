--[[
 Use the source, Luke!
 Copyright (C) 2026 Gary V. Vaughan
]]

--[[--
 The modules that a rock bundles from other rocks.

 A rule with a module name among its `sources`, such as `std.normalize`,
 which smush bundles from the Lua path, builds with the file that the path
 finds, from whichever rock installed it.  LuaRocks checks that each build
 dependency is installed somewhere, which does not say that the rock that
 the Lua path finds the module in is the one that it checked, so look at
 that one.  A rule with only files of the rock among its `sources`, and a
 rock with no rule that has a module name, have nothing to look at.

 @module luke.bundled
]]

local _ENV = require 'std.normalize' {
   'string.format',
   'string.match',
   'table.concat',
   'table.sort',
}


-- Whether *source* is the name of a module to find in the Lua path, and not
-- the path of a file of the rock, which has a `/` or ends in `.lua` or `.in`,
-- or NAME=PATH, or ALIAS::MODULE.
local function isname(source)
   return type(source) == 'string' and
      match(source, '^[%w_][%w_.]*$') ~= nil and
      match(source, '%.lua$') == nil and
      match(source, '%.in$') == nil
end


-- The names of the modules that the `sources` of *rules*, the entries of a
-- `bin` or `files` table, take from the Lua path, sorted, with each once.
local function modules(rules)
   local names, seen = {}, {}
   for i = 1, #(rules or {}) do
      local rule = rules[i]
      if type(rule) == 'table' then
         for _, spec in next, rule do
            local sources = type(spec) == 'table' and spec.sources or {}
            if type(sources) == 'string' then
               sources = {sources}
            end
            for j = 1, #sources do
               local name = sources[j]
               if isname(name) and not seen[name] then
                  seen[name] = true
                  names[#names + 1] = name
               end
            end
         end
      end
   end
   sort(names)
   return names
end


-- A message for each rock that provides some of *names* but does not
-- satisfy the build dependency on it.  *provider* gives the rock, its
-- version and the file that the Lua path finds for a module name, or
-- else nothing, and *satisfies* whether that version is wanted, as `false`
-- and what is, if it is not, or else `true`, or nothing for a rock that no
-- build dependency names.
local function outdated(names, provider, satisfies)
   local messages, reported = {}, {}
   for i = 1, #names do
      local rock, version, file = provider(names[i])
      if rock ~= nil and not reported[rock] then
         local ok, wanted = satisfies(rock, version)
         if ok == false then
            reported[rock] = true
            messages[#messages + 1] = format(
               "%s %s provides %s (%s), which does not satisfy the build dependency %s",
               rock, version, names[i], file, wanted)
         end
      end
   end
   return messages
end


-- The rocks that provide some of *names*, as a sorted list of `rock version`,
-- with each rock once, found by *provider* as for `outdated`.  A module
-- that no rock has, such as one in a checkout on the Lua path, gives none.
local function rocks(names, provider)
   local list, seen = {}, {}
   for i = 1, #names do
      local rock, version = provider(names[i])
      if rock ~= nil and not seen[rock] then
         seen[rock] = true
         list[#list + 1] = rock .. ' ' .. version
      end
   end
   sort(list)
   return list
end


-- The items of *list*, quoted and separated by commas, to fill the
-- braces of a Lua table in a template.
local function listing(list)
   local items = {}
   for i = 1, #list do
      items[i] = format('%q', list[i])
   end
   return concat(items, ', ')
end


return {
   isname   = isname,
   listing  = listing,
   modules  = modules,
   outdated = outdated,
   rocks    = rocks,
}

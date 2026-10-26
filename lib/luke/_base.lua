--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _functional = require 'luke.functional'

local _ENV = require 'std.normalize' {
   'io.stderr',
   'io.stdout',
   'os.exit',
   format = _functional.format,
}

-- The message *...*, formatted if it has more than the format.
local function message(...)
   if select('#', ...) > 1 then
      return format(...)
   end
   return (...)
end


local M = {}


-- What to do with the message of a fatal error: the command line writes
-- it, and exits.  `protected` replaces this while it runs a function.
function M.failure(msg)
   stdout:flush()
   stderr:write('luke: fatal: ' .. msg .. '\n')
   exit(1)
end


local function fatal(...)
   M.failure(message(...))
end


M.fatal = fatal


M.message = message


-- Like assert, give back *predicate* when it holds.  Fail through M.fatal,
-- so that a caller that replaces fatal sees it called.
function M.diagnose(predicate, ...)
   if not predicate then
      M.fatal(...)
   end
   return predicate
end


-- The marker of an error that `protected` raises for a fatal one.
local FATAL = {}


-- Call *fn* with *...* and give back its results, or, for a fatal error
-- that it raises, nil and the message, instead of exiting the process.
-- Any other error is raised as it is.
function M.protected(fn, ...)
   local outer = M.failure
   M.failure = function(msg)
      error(setmetatable({message = msg}, FATAL), 0)
   end
   local r = pack(pcall(fn, ...))
   M.failure = outer
   if r[1] then
      return unpack(r, 2, r.n)
   end
   if getmetatable(r[2]) == FATAL then
      return nil, r[2].message
   end
   error(r[2], 0)
end


return M

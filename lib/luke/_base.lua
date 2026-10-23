--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {}

-- The message *...*, formatted if it has more than the format.
local function message(...)
   if select('#', ...) > 1 then
      return format(...)
   end
   return (...)
end


local function fatal(...)
   stdout:flush()
   stderr:write('luke: fatal: ' .. message(...) .. '\n')
   exit(1)
end


local M = {}


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


return M

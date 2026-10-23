--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {}

local function fatal(...)
   local msg = (...)
   if select('#', ...) > 1 then
      msg = format(...)
   end
   stdout:flush()
   stderr:write('luke: fatal: ' .. msg .. '\n')
   exit(1)
end


local M = {}


M.fatal = fatal


-- Like assert, give back *predicate* when it holds.  Fail through M.fatal,
-- so that a caller that replaces fatal sees it called.
function M.diagnose(predicate, ...)
   if not predicate then
      M.fatal(...)
   end
   return predicate
end


return M

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


return {
   diagnose = function(predicate, ...)
      if not predicate then
         fatal(...)
      end
   end,

   fatal = fatal,
}

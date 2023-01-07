--[[
 Use the source, Luke!
 Copyright (C) 2014-2023 Gary V. Vaughan
]]

local _ENV = require 'std.normalize' {}

local function fatal(...)
   local msg = (...)
   if select('#', ...) > 1 then
      msg = format(...)
   end
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

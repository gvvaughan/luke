local _ENV = require 'std.normalize' {}

return {
   fatal = function(...)
      local msg = (...)
      if select('#', ...) > 1 then
         msg = format(...)
      end
      stderr:write('luke: fatal: ' .. msg .. '\n')
      exit(1)
   end
}

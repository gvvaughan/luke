local _ENV = require 'std.normalize' {
   destructure = next,
}

return {
   OrderedDict = function(...)
      local r, argu = {}, list(...)
      for i = 1, argu.n do
         local k, v = destructure(argu[i])
         append(r, k)
         r[k] = v
      end
      return r
   end,
}

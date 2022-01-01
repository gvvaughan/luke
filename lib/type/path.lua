--[[
 Use the source, Luke!
 Copyright (C) 2014-2022 Gary V. Vaughan
]]

local _ENV = require 'std.normalize' {}


local BASENAMEPAT = '.*' .. dirsep
local DIRNAMEPAT = dirsep .. '[^' .. dirsep .. ']*$'


return {
   basename = function(path)
      return (gsub(path, BASENAMEPAT, ''))
   end,

   dirname = function(path)
      return (gsub(path, DIRNAMEPAT, '', 1))
   end,

   exists = function(path)
      local fh = open(path)
      if fh == nil then
         return false
      end
      close(fh)
      return true
   end,
}


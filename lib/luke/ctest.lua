--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

-- The context manager of the C source that a probe compiles, which is the
-- one thing that luke has of its own.  The others, such as `File`, are
-- std.prototype's.

local _context = require 'std.prototype.contextmanager'

local _ENV = require 'std.normalize' {
   'io.close',
   'io.open',
   'os.remove',
   'os.tmpname',
   'string.gsub',
   iotype = 'io.type',
}


-- Close the file that *cm* holds.
local function closefile(cm)
   return iotype(cm.context) == 'file' and close(cm.context)
end


return {
   -- Unless `keep` is true, remove the C source and its object file
   -- (`cm.objfile`, in the current directory) on release.
   CTest = function(keep)
      local conftest = tmpname()
      local source = conftest .. '.c'
      local cm, err = _context(function(cm)
         local closed = closefile(cm)
         if keep then
            return closed
         end
         remove(conftest)
         remove(cm.objfile)
         return closed and remove(cm.filename)
      end, open, source, 'w')
      if cm ~= nil then
         cm.filename = source
         cm.objfile = gsub(conftest, '^.*/', '') .. '.o'
      end
      return cm, err
   end,
}

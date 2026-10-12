--[[
 Use the source, Luke!
 Copyright (C) 2014-2023 Gary V. Vaughan
]]

 local _ENV = require 'luke.normalize' {
   'luke.functional',
}


local contextmanager_mt = {
   __index = function(self, key)
      if iscallable(self.context[key]) then
         return function(_, ...)
            return self.context[key](self.context, ...)
         end
      end
      -- FIXME `cm.filename` beats `cm[1]`, but what about non-file context managers?
      if key == 'filename' then
         return self[1]
      end
   end,
}


local function ContextManager(release, acquire, ...)
   local fh, err = acquire(...)
   if not fh then
      return nil, err
   end
   local cm = {
      context = fh,
      release = release,
      n       = select("#", ...), ...
   }
   if cm.context ~= nil then
      setmetatable(cm, contextmanager_mt)
   end
   return cm
end


local function context_close(cm)
   return isfile(cm.context) and close(cm.context)
end


local function with(...)
   local argu = list(...)
   local block = pop(argu)
   local r = list(apply(block, argu))
   map(argu, function(cm)
      if cm ~= nil then
         cm:release()
      end
   end)
   return unpack(r)
end


return {
   ContextManager = ContextManager,

   -- Unless `keep` is true, remove the C source and its object file
   -- (`cm.objfile`, in the current directory) on release.
   CTest = function(keep)
      local conftest = tmpname()
      local cm, err = ContextManager(function(cm)
         local closed = context_close(cm)
         if keep then
            return closed
         end
         rm(conftest)
         rm(cm.objfile)
         return closed and rm(cm.filename)
      end, open, conftest .. '.c', 'w')
      if cm ~= nil then
         cm.objfile = gsub(conftest, '^.*/', '') .. '.o'
      end
      return cm, err
   end,

   File = function(fname, mode)
      return ContextManager(context_close, open, fname, mode)
   end,

   Pipe = function(cmd, mode)
      return ContextManager(context_close, popen, cmd, mode)
   end,

   TmpFile = function(fname, mode)
      return ContextManager(function(cm)
         if context_close(cm) then
            return rm(cm.filename)
         end
         return false
      end, open, fname or tmpname(), mode or 'w')
   end,

   slurp = function(cm, ...)
      if not cm then
          return cm, ...
      end
      return with(cm, function(h)
         return h:read '*a'
      end)
   end,

   with = with,
}

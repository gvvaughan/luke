--[[
 Use the source, Luke!
 Copyright (C) 2014-2018 Gary V. Vaughan
]]

 local _ENV = require 'std.normalize' {
   'std.functional',
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

   CTest = function()
      local conftest = tmpname()
      return ContextManager(function(cm)
         rm(conftest)
         rm(gsub(conftest, '^.*/', '') .. '.o')
         if context_close(cm) then
            return rm(cm.filename)
         end
         return false
      end, open, conftest .. '.c', 'w')
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

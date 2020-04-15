--[[
 Use the source, Luke!
 Copyright (C) 2014-2020 Gary V. Vaughan
]]

local _ENV = require 'std.normalize' {
   'luke.platforms',
   'std.functional',
   LUAVERSION = string.gsub(_VERSION, '[^0-9%.]+', ''),
}


local env_mt = {
   __index = function(self, varname)
      return dropuntil(self, function(env)
         local value = env[varname]
         if value ~= nil then
            self[varname] = value
            return value
         end
      end)
   end,
}


local function interpolate_with(pattern, env, s)
   local r = ''
   while r ~= s do
      r = s
      s = gsub(r, pattern, function(varname)
         return env[varname] or ''
      end)
   end
   return r
end


local function isenv(t)
   return getmetatable(t) == env_mt
end


return {
   CONFIGENV = {
      compile    = '$CC -c $CFLAGS $CPPFLAGS',
      libs       = '',
      link       = '$CC $CFLAGS $CPPFLAGS $LDFLAGS',
   },

   DEFAULTENV = filter_platforms {
      LUAVERSION    = LUAVERSION,

      PREFIX        = '/usr/local',
      INST_LIBDIR   = '$PREFIX/lib/lua/$LUAVERSION',
      INST_LUADIR   = '$PREFIX/share/lua/$LUAVERSION',

      LIB_EXTENSION = 'so',
      OBJ_EXTENSION = 'o',

      INSTALL       = 'cp',
      MAKEDIRS      = 'mkdir -p',

      CFLAGS        = '-O2',
      platforms     = {
         macosx        = {
            LIBFLAG       = '-fPIC -bundle -undefined dynamic_lookup -all_load',
         },
         LIBFLAG    = '-shared -fPIC',
      },
   },

   SHELLENV = setmetatable({}, {
      __index = function(_, v)
         return getenv(v)
      end,
   }),

   expand = bind(interpolate_with, {'@([^@]+)@'}),
   interpolate = bind(interpolate_with, {'%$([%w_]+)'}),

   makeenv = function(...)
      local env = reduce(except(list(...), nil), function(r, t)
         if isenv(t) then
            map(t, bind(append, {r}))
         else
            append(r, t)
         end
      end)

      return setmetatable(env, env_mt)
   end,
}

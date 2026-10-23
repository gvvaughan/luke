--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke.platforms',
   'luke.functional',
   LUAVERSION = string.gsub(_VERSION, '[^0-9%.]+', ''),
   SHELLMETACHARS = '[%s%$"\'&;|<>()*?`\\]',
}


-- *s* with each name that matches *pattern* replaced by its value in
-- *env*, or nothing, and then again, until that changes nothing.
local function interpolate_with(pattern, env, s)
   return fixpoint(s, function(text)
      return (gsub(text, pattern, function(varname)
         return env[varname] or ''
      end))
   end)
end


-- *s* as a single shell word, in single quotes, with each of its own
-- single quotes written as '\''.
local function quoted(s)
   return "'" .. gsub(s, "'", [['\'']]) .. "'"
end


return {
   CONFIGENV = {
      compile    = '$CC -c $CFLAGS $CPPFLAGS',
      libs       = '',
      link       = '$CC $CFLAGS $CPPFLAGS $LDFLAGS',
   },

   DEFAULTENV = filter_platforms {
      LUA           = 'lua',
      LUAVERSION    = LUAVERSION,

      PREFIX        = '/usr/local',
      INST_BINDIR   = '$PREFIX/bin',
      INST_LIBDIR   = '$PREFIX/lib/lua/$LUAVERSION',
      INST_LUADIR   = '$PREFIX/share/lua/$LUAVERSION',

      LIB_EXTENSION = 'so',
      OBJ_EXTENSION = 'o',

      CHMOD         = 'chmod',
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

   -- Like `interpolate`, only names made of word characters count, so
   -- that a lone '@', as in an email address, leaves the text after it
   -- alone.
   expand = bind(interpolate_with, {'@([%w_]+)@'}),
   interpolate = bind(interpolate_with, {'%$([%w_]+)'}),

   -- *s* as a single shell word: as it is, or else quoted.  Quote a
   -- word after interpolating it, or a quote in a variable it uses is
   -- left bare.
   shellword = function(s)
      if match(s, SHELLMETACHARS) then
         return quoted(s)
      end
      return s
   end,

   -- An environment that looks a name up in each of the tables *...* in
   -- turn, skipping nils, and remembers what it finds.  An environment
   -- among them is such a table too.
   mkenv = function(...)
      local tables, found = reject(list(...), nil), {}
      return setmetatable({}, {
         __index = function(_, varname)
            if found[varname] == nil then
               found[varname] = firstof(tables, function(t)
                  return t[varname]
               end)
            end
            return found[varname]
         end,
      })
   end,
}

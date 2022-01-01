--[[
 Use the source, Luke!
 Copyright (C) 2014-2022 Gary V. Vaughan
]]

package.path = os.getenv 'LUA_PATH'

require 'spec.spec_helpers'


local platforms = require 'luke.platforms'


describe('luke.environment', function()
   describe('filter_platforms', function()
      local filter_platforms = platforms.filter_platforms

      describe('DEFAULTENV', function()
         local defines  = {
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
         }

         local CANON = {
            ['Darwin']    = list('macosx', 'bsd', 'unix'),
            ['Linux']     = list('linux', 'unix'),
         }

         local ALLPLATFORMS = set('bsd', 'linux', 'macosx', 'unix')

         local function isplatform(x)
            return ALLPLATFORMS[x] ~= nil
         end

         it('sets the right defines on Darwin', function()
            local expected = {
               LUAVERSION    = LUAVERSION,

               PREFIX        = '/usr/local',
               INST_LIBDIR   = '$PREFIX/lib/lua/$LUAVERSION',
               INST_LUADIR   = '$PREFIX/share/lua/$LUAVERSION',

               LIB_EXTENSION = 'so',
               OBJ_EXTENSION = 'o',

               INSTALL       = 'cp',
               MAKEDIRS      = 'mkdir -p',

               CFLAGS        = '-O2',
               LIBFLAG       = '-fPIC -bundle -undefined dynamic_lookup -all_load',
            }

            assert.same(expected, filter_platforms(defines, CANON.Darwin, isplatform))
         end)

         it('sets the right defines on Linux', function()
            local expected = {
               LUAVERSION    = LUAVERSION,

               PREFIX        = '/usr/local',
               INST_LIBDIR   = '$PREFIX/lib/lua/$LUAVERSION',
               INST_LUADIR   = '$PREFIX/share/lua/$LUAVERSION',

               LIB_EXTENSION = 'so',
               OBJ_EXTENSION = 'o',

               INSTALL       = 'cp',
               MAKEDIRS      = 'mkdir -p',

               CFLAGS        = '-O2',
               LIBFLAG       = '-shared -fPIC',
            }

            assert.same(expected, filter_platforms(defines, CANON.Linux, isplatform))
         end)

      end)
   end)
end)


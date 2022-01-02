--[[
 Use the source, Luke!
 Copyright (C) 2014-2022 Gary V. Vaughan
]]

package.path = os.getenv 'LUA_PATH'

require 'spec.spec_helpers'

local compile = require 'luke.compile'
local spawn = compile.spawn

local mocks = {
   spawn = setmetatable({
      clear = function(self)
         self.values = {}
      end,
   }, {
      __call = function(self, env, ...)
         if #self.values > 0 then
            return unpack(table.remove(self.values, 1))
         end
         return spawn(env, ...)
      end,
   }),
}


local LINK_SUCCESS = list(0, '', '')
local LINK_FAILURE = list(1, '', 'error')


describe('luke.configure', function()
   local fatal = stub.new()
   package.loaded['luke._base'] = {fatal=fatal} -- don't kill the test-runner!

   local L = {
      log = stub.new(),
      verbose = stub.new(),
   }


   insulate('checkdecl', function()
      -- Don't hoist these: or you'll load luke.compile.spawn before mocks.spawn
      local configure = require 'luke.configure'.configure
      local E = require 'luke.environment'
      local env = E.makeenv({CC='cc'}, E.DEFAULTENV, E.SHELLENV)

      it('notes a missing declaration', function()
         assert.same(0, configure(L, env, {checkdecl='_not_a_real_c_function_decl'}))
      end)

      it('finds an existing declaration in given header', function()
         assert.same(1, configure(L, env, {checkdecl='gethostid', includes={'unistd.h'}}))
      end)

      it('correctly resolves lukefile defines', function()
         local run_configs = require 'luke.lukefile'.run_configs
         local lukefile = {
            defines = {
               HAVE__NOT_A_REAL_FUNCTION_DECL = {checkdecl='_not_a_real_function_decl'},
               HAVE_GETHOSTID_DECL = {checkdecl='gethostid', includes={'unistd.h'}},
            },
         }
         local r = run_configs(L,  env, lukefile)
         assert.same(0, r.defines.HAVE__NOT_A_REAL_FUNCTION_DECL)
         assert.same(1, r.defines.HAVE_GETHOSTID_DECL)
      end)
    end)

   insulate('checkfunc', function()
      local configure = require 'luke.configure'.configure
      local E = require 'luke.environment'
      local env = E.makeenv({CC='cc'}, E.DEFAULTENV, E.SHELLENV)

      it('notes a missing function', function()
         assert.same(0, configure(L, env, {checkfunc='_not_a_real_c_function'}))
      end)

      it('finds an existing linkable function', function()
         assert.same(1, configure(L, env, {checkfunc='printf'}))
      end)

      it('correctly resolves lukefile defines', function()
         local run_configs = require 'luke.lukefile'.run_configs
         local lukefile = {
            defines = {
               HAVE__NOT_A_REAL_FUNCTION = {checkfunc='_not_a_real_function'},
               HAVE_PRINTF = {checkfunc='printf'},
            },
         }
         local r = run_configs(L,  env, lukefile)
         assert.same(0, r.defines.HAVE__NOT_A_REAL_FUNCTION)
         assert.same(1, r.defines.HAVE_PRINTF)
      end)
    end)

   insulate('checkheader', function()
      local configure = require 'luke.configure'.configure
      local E = require 'luke.environment'
      local env = E.makeenv({CC='cc'}, E.DEFAULTENV, E.SHELLENV)

      it('notes a missing header', function()
         assert.same(0, configure(L, env, {checkheader='-not-a-real-header.h'}))
      end)

      it('finds an existing header', function()
         assert.same(1, configure(L, env, {checkheader='stdio.h'}))
      end)

      it('also includes listed extra headers', function()
         assert.same(1, configure(L, env, {checkheader='net/if.h', includes={'sys/socket.h'}}))
      end)

      it('correctly resolves lukefile defines', function()
         local run_configs = require 'luke.lukefile'.run_configs
         local lukefile = {
            defines = {
               HAVE__NOT_A_REAL_HEADER_H = {checkheader='-not-a-real-header.h'},
               HAVE_STDIO_H = {checkheader='stdio.h'},
               HAVE_NET_IF_H = {checkheader='net/if.h', includes={'sys/socket.h'}},
            },
         }
         local r = run_configs(L,  env, lukefile)
         assert.same(0, r.defines.HAVE__NOT_A_REAL_HEADER_H)
         assert.same(1, r.defines.HAVE_STDIO_H)
         assert.same(1, r.defines.HAVE_NET_IF_H)
      end)
   end)

   insulate('checkmember', function()
      local configure = require 'luke.configure'.configure
      local E = require 'luke.environment'
      local env = E.makeenv({CC='cc'}, E.DEFAULTENV, E.SHELLENV)

      it('notes a missing struct member', function()
         assert.same(0, configure(L, env, {checkmember='struct stat.not_a_member', includes={'sys/stat.h'}}))
      end)

      it('finds an existing struct member', function()
         assert.same(1, configure(L, env, {checkmember='struct stat.st_mode', includes={'sys/stat.h'}}))
      end)

      it('correctly resolves lukefile defines', function()
         local run_configs = require 'luke.lukefile'.run_configs
         local lukefile = {
            defines = {
               HAVE_STAT_NOT_A_MEMBER = {checkmember='struct stat.not_a_member', includes={'sys/stat.h'}},
               HAVE_STAT_ST_MODE = {checkmember='struct stat.st_mode', includes={'sys/stat.h'}},
            },
         }
         local r = run_configs(L,  env, lukefile)
         assert.same(0, r.defines.HAVE_STAT_NOT_A_MEMBER)
         assert.same(1, r.defines.HAVE_STAT_ST_MODE)
      end)
   end)

   insulate('checkprog', function()
      local configure = require 'luke.configure'.configure
      local notreal = '|not:a:real:program|'

      before_each(function()
         fatal:clear()
         L.log:clear()
      end)

      it('logs found program', function()
         configure(L, nil, {checkprog='existing', progs={'sed'}})
         assert.stub(L.log).was_called_with('found /usr/bin/sed')
      end)

      it('logs missing program', function()
         configure(L, nil, {checkprog='non-existing', progs={notreal}})
         assert.stub(L.log).was_called_with(notreal .. ' not found')
      end)

      it('logs found fallback program', function()
         configure(L, nil, {checkprog='fallback', progs={notreal, 'sed'}})
         assert.stub(L.log).was_called_with(notreal .. ' not found')
         assert.stub(L.log).was_called_with('found /usr/bin/sed')
      end)

      it('fallsback to alternative non-fatally', function()
         configure(L, nil, {checkprog='non-fatal', progs={notreal, 'sed'}})
         assert.stub(fatal).was_not_called()
      end)
   end)

   insulate('checksymbol', function()
      compile.spawn = mocks.spawn

      local configure = require 'luke.configure'.configure
      local E = require 'luke.environment'
      local env = E.makeenv({CC='cc'}, E.DEFAULTENV, E.SHELLENV)

      before_each(function()
         L.verbose:clear()
         mocks.spawn:clear()
         E.CONFIGENV.libs = '' -- FIXME: global state :(
      end)

      it('reports "none required" for libc symbols', function()
         mocks.spawn.values = {
            LINK_SUCCESS,
         }
         local r = configure(L, env, {checksymbol='sprintf', libraries={'m'}})
         assert.same('', r)
         assert.stub(L.verbose).was_called_with 'none required'
      end)

      it('returns first lib satisfying required symbol', function()
         mocks.spawn.values = {
            LINK_FAILURE,
            LINK_SUCCESS,
         }
         local r = configure(L, env, {checksymbol='pow', libraries={'m'}})
         assert.same('-lm', r)
         assert.stub(L.verbose).was_called_with '-lm'
      end)

      it('returns optional libs according to successful ifdef', function()
         mocks.spawn.values = {
            LINK_SUCCESS, -- try_compile
            LINK_FAILURE, -- try_link library=''
            LINK_SUCCESS, -- try_link library='crypt'
         }
         local env = E.makeenv({CC='cc', CPPFLAGS='-D_XOPEN_CRYPT'}, E.DEFAULTENV, E.SHELLENV)
         local r = configure(L, env, {
            checksymbol='crypt',
            ifdef='_XOPEN_CRYPT',
            includes={'unistd.h'},
            libraries={'crypt'},
         })
         assert.same('-lcrypt', r)
         assert.stub(L.verbose).was_called_with '-lcrypt'
      end)

      it('elides optional libs according to failing ifdef', function()
         local r = configure(L, env, {
            checksymbol='poop',
            ifdef='_POOP_AWAY',
            includes={'unistd.h'},
            libraries={'poop'},
         })
         assert.same({}, r)
      end)

      it('searches for external dependencies', function()
         mocks.spawn.values = {
            LINK_FAILURE,
            LINK_SUCCESS,
         }
         local run_configs = require 'luke.lukefile'.run_configs
         local env = E.makeenv(
            {
               CC='cc',
               YAML_DIR='/usr/local/brew',
               YAML_INCDIR='$YAML_DIR/include',
               YAML_LIBDIR='$YAML_DIR/lib',
            },
            E.DEFAULTENV,
            E.SHELLENV
         )
         local lukefile = {
            external_dependencies = {
               YAML = {
                  library = {checksymbol='yaml_document_initialize', libraries={'yaml'}},
               },
            },
         }
         local r = run_configs(L,  env, lukefile)
         assert.contains('$YAML_INCDIR', r.incdirs)
         assert.contains('$YAML_LIBDIR', r.libdirs)
         assert.contains('-lyaml', r.libraries)
      end)
   end)
end)

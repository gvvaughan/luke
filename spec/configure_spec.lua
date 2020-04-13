--[[
 Use the source, Luke!
 Copyright (C) 2014-2019 Gary V. Vaughan
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

   local notreal = '|not:a:real:program|'

   insulate('checkprog', function()
      local configure = require 'luke.configure'.configure

      before_each(function()
         fatal:clear()
         L.log:clear()
      end)

      it('logs found program', function()
         configure(L, nil, {checkprog='existing', progs={'sh'}})
         assert.stub(L.log).was_called_with('found /bin/sh')
      end)

      it('logs missing program', function()
         configure(L, nil, {checkprog='non-existing', progs={notreal}})
         assert.stub(L.log).was_called_with(notreal .. ' not found')
      end)

      it('logs found fallback program', function()
         configure(L, nil, {checkprog='fallback', progs={notreal, 'sh'}})
         assert.stub(L.log).was_called_with(notreal .. ' not found')
         assert.stub(L.log).was_called_with('found /bin/sh')
      end)

      it('fallsback to alternative non-fatally', function()
         configure(L, nil, {checkprog='non-fatal', progs={notreal, 'sh'}})
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
   end)
end)

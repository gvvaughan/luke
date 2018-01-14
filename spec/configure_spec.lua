--[[
 Use the source, Luke!
 Copyright (C) 2014-2018 Gary V. Vaughan
]]

package.path = os.getenv 'LUA_PATH'

require 'spec.spec_helpers'


describe('luke.configure', function()
   local fatal = stub.new()
   package.loaded['luke._base'] = {fatal=fatal} -- don't kill the test-runner!
   local configure = require 'luke.configure'.configure

   local L = {
      log = stub.new(),
      verbose = stub.new(),
   }

   local notreal = '|not:a:read:program|'

   describe('checkprog', function()
      it('logs found program', function()
         L.log:clear()
         configure(L, nil, {checkprog='fallback', progs={notreal, 'true'}})
         assert.stub(L.log).was_called_with('found /bin/true')
      end)

      it('logs missing program', function()
         L.log:clear()
         configure(L, nil, {checkprog='non-existing', progs={notreal}})
         assert.stub(L.log).was_called_with(notreal .. ' not found')
      end)

      it('fallsback to true non-fatally', function()
         fatal:clear()
         configure(L, nil, {checkprog='non-fatal', progs={notreal, 'true'}})
         assert.stub(fatal).was_not_called()
      end)
   end)

   describe('checksymbol', function()
      local E = require 'luke.environment'
      local env = E.makeenv({CC='cc'}, E.DEFAULTENV, E.SHELLENV)

      before_each(function()
         L.verbose:clear()
      end)

      it('reports "none required" for libc symbols', function()
         local r = configure(L, env, {checksymbol='sprintf', libraries={'m'}})
         assert.same('', r)
         assert.stub(L.verbose).was_called_with 'none required'
      end)

      it('returns first lib satisfying required symbol', function()
         local r = configure(L, env, {checksymbol='pow', libraries={'m'}})
         assert.same('-lm', r)
         assert.stub(L.verbose).was_called_with '-lm'
      end)

      it('returns optional libs according to successful ifdef', function()
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

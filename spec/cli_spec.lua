--[[
 Use the source, Luke!
 Copyright (C) 2014-2023 Gary V. Vaughan
]]

package.path = os.getenv 'LUA_PATH'

require 'spec.spec_helpers'


describe('luke.cli', function()
   local cli = require 'luke.cli'


   describe('parse_arguments', function()
      local parse_arguments = cli.parse_arguments

      it('accepts equals signs on RHS of a define', function()
         local argt = parse_arguments {'foo=bar=baz'}
         assert.same({foo='bar=baz'}, argt.clidefs)
      end)

      it('does not confuse --file=foo with defining a variable', function()
         local argt = parse_arguments {'--file=foo', 'file=bar'}
         assert.equal('foo', argt.fname)
         assert.same({file='bar'}, argt.clidefs)
      end)
   end)
end)

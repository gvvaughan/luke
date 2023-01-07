--[[
 Use the source, Luke!
 Copyright (C) 2014-2023 Gary V. Vaughan
]]

package.path = os.getenv 'LUA_PATH'

require 'spec.spec_helpers'


local normalize = require 'std.normalize'


describe('std.normalize', function()
   describe('int', function()
      local int = normalize.int

      it('returns any integer argument', function()
         assert.equal(100, int(100))
         assert.equal(-100, int(-100))
      end)

      it('returns an integer equivalent of any float argument', function()
         assert.equal(100, int(100.0))
         assert.equal(-100, int(-100.0))
      end)

      it('returns nil for any integer-like string', function()
         assert.is_nil(int '100')
         assert.is_nil(int '100.0')
         assert.is_nil(int '-100')
         assert.is_nil(int '-100.0')
      end)

      it('returns nil for non-integer number', function()
         assert.is_nil(int(100.5))
         assert.is_nil(int(-100.5))
      end)

      it('returns nil non-number', function()
         assert.is_nil(int '100.5')
         assert.is_nil(int '-100.5')
         assert.is_nil(int(false))
      end)
   end)

   describe('pop', function()
      local pop = normalize.pop

      it('removes and returns the last item', function()
         local stack = {1, 2, 3, n=3}
         assert.equal(3, pop(stack))
         assert.same({1, 2, n=2}, stack)
      end)

      it('removes and returns the only item', function()
         local stack = {3, n=1}
         assert.equal(3, pop(stack))
         assert.same({n=0}, stack)
      end)

      it('handles nil elements', function()
         local stack = {[42]=42, n=42}
         assert.equal(42, pop(stack))
         assert.same({n=41}, stack)
         assert.is_nil(pop(stack))
         assert.same({n=40}, stack)
      end)

      it('does not underflow the stack', function()
         local stack = {n=1}
         assert.is_nil(pop(stack))
         assert.same({n=0}, stack)
         assert.is_nil(pop(stack))
         assert.same({n=0}, stack)
      end)
   end)
end)

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
end)

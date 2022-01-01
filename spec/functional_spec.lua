--[[
 Use the source, Luke!
 Copyright (C) 2014-2022 Gary V. Vaughan
]]

package.path = os.getenv 'LUA_PATH'

require 'spec.spec_helpers'


local functional = require 'std.functional'


describe('std.functional', function()
   describe('keys', function()
      local keys = functional.keys

      it('returns a list of table keys', function()
         assert.same(list(1, 'a', 'b'), sorted(keys{a=2,b=1,'c'}))
      end)
   end)

   describe('partition', function()
      local partition = functional.partition

      local square, nonsquare = partition(list(1, 2, 3, 4, 5, 6, 7, 8, 9), function(x)
         local sqrt = math.sqrt(x)
         return math.ceil(sqrt) == sqrt
       end)

      it('separates a list according to a predicate', function()
          assert.same(list(1, 4, 9), square)
          assert.same(list(2, 3, 5, 6, 7, 8), nonsquare)
      end)
   end)
end)

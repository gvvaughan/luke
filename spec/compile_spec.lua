--[[
 Use the source, Luke!
 Copyright (C) 2014-2020 Gary V. Vaughan
]]

package.path = os.getenv 'LUA_PATH'

require 'spec.spec_helpers'


local compile = require 'luke.compile'


describe('luke.compile', function()
   describe('incdirs', function()
      local incdirs = compile.incdirs

      it('prepends -I to argument', function()
         local dir = '/usr/local/include'

         assert.same({'-I' .. dir, n=1}, incdirs(dir))
      end)

      it('prepends -I to each argument in a list', function()
         local dirs = {'/usr/local/include', '/opt/yaml/include', '/opt/libgit2/include'}

         local expected = {}
         for _, dir in ipairs(dirs) do
            expected[#expected +1] = '-I' .. dir
         end
         expected.n = #expected

         assert.same(expected, incdirs(dirs))
      end)

      it('returns an empty list for no arguments', function()
         assert.same({n=0}, incdirs())
      end)

   end)

   describe('libdirs', function()
      local libdirs = compile.libdirs

      it('prepends -L to argument', function()
         local dir = '/usr/local/lib'

         assert.same({'-L' .. dir, n=1}, libdirs(dir))
      end)

      it('prepends -L to each argument in a list', function()
         local dirs = {'/usr/local/lib', '/opt/yaml/lib', '/opt/libgit2/lib'}

         local expected = {}
         for _, dir in ipairs(dirs) do
            expected[#expected +1] = '-L' .. dir
         end
         expected.n = #expected

         assert.same(expected, libdirs(dirs))
      end)

      it('returns an empty list for no arguments', function()
         assert.same({n=0}, libdirs())
      end)

   end)
end)


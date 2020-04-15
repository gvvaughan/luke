--[[
 Use the source, Luke!
 Copyright (C) 2014-2020 Gary V. Vaughan
]]

package.path = os.getenv 'LUA_PATH'

require 'spec.spec_helpers'

local normalize = require 'std.normalize'
local popen = normalize.popen

local mocks = {
   popen = setmetatable({
      clear = function(self)
         self.uname = 'not a real uname!'
      end,
   }, {
      __call = function(self, prog, mode)
         if prog == 'uname -s' then
            return {
               read = function() return self.uname end
            }
         end
         return popen(prog, mode)
      end
   }),
}


insulate('mocks', function()
   normalize.popen = mocks.popen

   before_each(function()
      mocks.popen:clear()
   end)

   it('mocks normalize.popen', function()
      assert.same(mocks.popen.uname, normalize.popen('uname -s'):read '*l')
   end)

   it('overrides system uname', function()
      mocks.popen.uname = 'QNX'
      assert.same('QNX', normalize.popen('uname -s'):read '*l')
   end)

   it('overrides system uname again without reloading', function()
      mocks.popen.uname = 'Cygwin'
      assert.same('Cygwin', normalize.popen('uname -s'):read '*l')
   end)
end)


describe('luke.platforms', function()
   mocks.popen.uname = 'Linux'

   insulate('platforms', function()
      local platforms = require 'luke.platforms'.platforms

      it('is a list of platforms', function()
         assert.same(list('linux', 'unix'), platforms)
      end)
   end)

   insulate('toplatforms', function()
      local toplatforms = require 'luke.platforms'.toplatforms

      local lookup = {
         ['literal'] = 'literal',
         ['^pattern'] = 'pattern',
      }

      it('returns a literal match from the lookup table', function()
         assert.equal('literal', toplatforms(lookup, 'literal'))
      end)

      it('returns an anchored pattern match from the lookup table', function()
         assert.equal('pattern', toplatforms(lookup, 'pattern-extra-stuff'))
      end)

      it('returns unix without another match in the lookup table', function()
         assert.same(list 'unix', toplatforms(lookup, 'no match!'))
      end)

      it('returns the values in original order', function()
         local lookup = {
            ['Linux'] = list('linux', 'unix'),
         }
         assert.same(lookup.Linux, toplatforms(lookup, 'Linux'))
      end)
   end)

   insulate('filter_platforms', function()
      local filter_platforms = require'luke.platforms'.filter_platforms

      local unfiltered = {
         unaffected = true,

         platforms = {
            matching = { match=1 },
            mismatching = { mismatch=1 },
            repeating = { match=0, mismatch=0 },
            misrepeating = { mismatch=0, misrepeat=1 },
            default=1,
            other=1,
         },
      }

      local function isplatform(x)
         return set('matching', 'mismatching', 'repeating', 'misrepeating')[x]
      end

      it('narrows platform values to match given system', function()
         local filtered = filter_platforms(unfiltered, list('matching'), isplatform)

         assert.same({unaffected=true, match=1}, filtered)
      end)

      it('narrows to the contents of all matches', function()
         local platforms = list('matching', 'mismatching', 'no match')
         local filtered = filter_platforms(unfiltered, platforms, isplatform)
         assert.same({unaffected=true, match=1, mismatch=1}, filtered)

         platforms = list('no match', 'mismatching', 'matching')
         filtered = filter_platforms(unfiltered, platforms, isplatform)
         assert.same({unaffected=true, match=1, mismatch=1}, filtered)
      end)

      it('gives precedence to elements from earlier platform matches', function()
         local platforms = list('matching', 'repeating')
         local filtered = filter_platforms(unfiltered, platforms, isplatform)
         assert.same({unaffected=true, match=1, mismatch=0}, filtered)
      end)

      it('falls back to defaults with no matching system', function()
         local filtered = filter_platforms(unfiltered, list('no matches'), isplatform)

         assert.same({unaffected=true, default=1, other=1}, filtered)
      end)
   end)

   describe('luaposix lukefile', function()
         local defines  = {
            PACKAGE           = '"package"',
            VERSION           = '"version"',
            NDEBUG            = 1,
            _FORTIFY_SOURCE   = 2,
            platforms   = {
               aix      = {_ALL_SOURCE       = 1},
               bsd      = {_BSD_SOURCE       = 1},
               freebsd  = {__BSD_VISIBLE     = 1},
               macosx   = {_DARWIN_C_SOURCE  = 1},
               -- QNX is only POSIX 2001, but _XOPEN_SOURCE turns off other functions
               -- luaposix can bind.
               qnx      = {_POSIX_C_SOURCE   = '200112L'},
               unix     = {
                  _POSIX_C_SOURCE   = '200809L',
                  _XOPEN_SOURCE     = 700,
               },
               -- Otherwise, enable POSIX 2008.   Please send the output of `uname -s` if
               -- your host is not compliant.
               _POSIX_C_SOURCE      = '200809L',
            },
         }

      insulate('QNX', function()
         it('gets the right defines', function()
            mocks.popen.uname = 'QNX'
            local filter_platforms = require'luke.platforms'.filter_platforms

            local expected = {
               PACKAGE           = '"package"',
               VERSION           = '"version"',
               NDEBUG            = 1,
               _FORTIFY_SOURCE   = 2,
               _POSIX_C_SOURCE   = '200112L',
            }

            assert.same(expected, filter_platforms(defines))
         end)
      end)

      insulate('Darwin', function()
         it('gets the right defines', function()
            mocks.popen.uname = 'Darwin'
            local filter_platforms = require'luke.platforms'.filter_platforms

            local expected = {
               PACKAGE           = '"package"',
               VERSION           = '"version"',
               NDEBUG            = 1,
               _BSD_SOURCE       = 1,
               _DARWIN_C_SOURCE  = 1,
               _POSIX_C_SOURCE   = '200809L',
               _XOPEN_SOURCE     = 700,
               _FORTIFY_SOURCE   = 2,
            }

            assert.same(expected, filter_platforms(defines))
         end)
      end)

      insulate('Linux', function()
         it('gets the right defines', function()
            mocks.popen.uname = 'Linux'
            local filter_platforms = require'luke.platforms'.filter_platforms

            local expected = {
               PACKAGE           = '"package"',
               VERSION           = '"version"',
               NDEBUG            = 1,
               _FORTIFY_SOURCE   = 2,
               _POSIX_C_SOURCE   = '200809L',
               _XOPEN_SOURCE     = 700,
            }

            assert.same(expected, filter_platforms(defines))
         end)
      end)
   end)
end)

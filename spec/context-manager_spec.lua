--[[
 Use the source, Luke!
 Copyright (C) 2014-2021 Gary V. Vaughan
]]

package.path = os.getenv 'LUA_PATH'

require 'spec.spec_helpers'


describe('type.context-manager', function()
   local context_manager = require 'type.context-manager'

   local cm

   -- Does it quack like a context manager?
   local function iscontextmanager(x)
      return not not (x.context and x.release and type(x.n) == 'number' and x.filename)
   end


   describe('ContextManager', function()
      local ContextManager = context_manager.ContextManager

      local function record(name)
         return setmetatable({n=0, name=name}, {
            __call = function(self, ...)
               self.n = self.n + 1
               self[self.n] = pack(...)
               return {}
            end,
         })
      end

      local acquire

      before_each(function()
         acquire = record 'acquire'
         cm = ContextManager(record 'release', acquire, 'arg1', 'arg2')
      end)

      it('returns a context manager instance', function()
         assert.is_true(iscontextmanager(cm))
      end)

      it('acquires a resource once', function()
         assert.equal(1, acquire.n)
      end)

      it('passes additional parameters to acquire', function()
         assert.same(pack('arg1', 'arg2'), acquire[1])
      end)

      it('releases the resource once', function()
         cm:release()
         assert.equal(1, cm.release.n)
      end)
   end)


   describe('File', function()
      local File = context_manager.File

      before_each(function()
         cm = File('build-aux/luke', 'r')
      end)

      after_each(function()
         if cm ~= nil then
            cm:release()
         end
      end)

      it('returns a context manager instance', function()
         assert.is_true(iscontextmanager(cm))
      end)

      it('records the calling arguments', function()
         assert.equal('build-aux/luke', cm[1])
         assert.equal('r', cm[2])
      end)

      it('records the number of arguments', function()
         assert.equal(2, cm.n)
      end)

      it('supports filename property', function()
         assert.equal(cm[1], cm.filename)
      end)

      it('propagates acquire errors', function()
         local fname = 'this/file/does/not/exist!/nope :)'
         local t = list(File(fname, 'r'))
         assert.same(list(nil, fname .. ': No such file or directory'), t)
      end)
   end)


   describe('CTest', function()
      local CTest = context_manager.CTest

      before_each(function()
         cm = CTest()
      end)

      after_each(function()
         cm:release()
      end)

      it('returns a context manager instance', function()
         assert.is_true(iscontextmanager(cm))
      end)

      it('has a filename ending in .c', function()
         assert.equal('.c', string.match(cm.filename, '%.c$'))
      end)
   end)


   describe('slurp', function()
      local File, slurp = context_manager.File, context_manager.slurp

      it('propagates context manager errors', function()
         local fname = 'this/file/does/not/exist/either =)O|'
         local t = list(slurp(File(fname, 'r')))
         assert.same(list(nil, fname .. ': No such file or directory'), t)
      end)

      it('returns the entire contents of named file', function()
         local fname = 'build-aux/luke'
         local fh = io.open(fname, 'r')
         local content = fh:read '*a'
         fh:close()
         local cm = File(fname, 'r')
         assert.equal(content, slurp(cm))
         cm:release()
      end)
   end)


   describe('with', function()
      local File, with = context_manager.File, context_manager.with
      local rm = os.remove

      it('releases passed context managers', function()
         local cm1, cm2 = mock(File('f1', 'w')), mock(File('f2', 'w'))
         with(cm1, cm2, function(first, second)
            assert.equal(cm1, first)
            assert.equal(cm2, second)
         end)
         assert.spy(cm1.release).called_with(cm1)
         assert.spy(cm2.release).called_with(cm2)
         rm 'f1'
         rm 'f2'
      end)

      it('does not try to release unacquired context managers', function()
         local fname = 'this/is/not/an/existing/file!'
         with(File(fname, 'r'), File(fname, 'r'), function(...)
            assert.same(list(nil, nil), list(...))
         end) 
      end)
   end)
end)

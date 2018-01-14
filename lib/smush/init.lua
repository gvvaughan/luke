--[[
 Use the source, Luke!
 Copyright (C) 2014-2018 Gary V. Vaughan
]]

package.preload['type.charset'] = function()
   local _ENV = require 'std.normalize' {}

   local mt; mt = {
      __call = function(self, x)
         return self[x]
      end,

      __concat = function(a, b)
         local r = copy(a)
         for k in next, b do
            r[k] = true
         end
         return setmetatable(r, mt)
      end,
   }

   return setmetatable({
      new = function(s)
         local r = {}
         for i = 1, #s do
            r[sub(s, i, i)] = true
         end
         return setmetatable(r, mt)
      end,
   }, {
      __call = function(self, ...)
         return self.new(...)
      end,
   })
end


package.preload['type.scanner'] = function()
   local _ENV = require 'std.normalize' {}

   local methods = {
      eof = function(self)
         return self.i >= self.n
      end,

      advance = function(self, o)
         o = int(o) or 1
         while o > 0 do
            self.i, o = self.i + 1, o - 1
            if sub(self.s, self.i, self.i) == '\n' then
               self.l = self.l + 1
            end
         end
         return self:peek()
      end,

      lookahead = function(self, s)
         return sub(self.s, self.i, self.i + len(s) -1) == s
      end,

      peek = function(self, o)
         return self[self.i + (int(o) or 0)]
      end,
   }

   local mt = {
      __index = function(self, name)
         local i = int(name)
         if i then
            return sub(str(self), i, i)
         end
         return methods[name]
      end,

      __len = function(self)
         return self.n
      end,

      __tostring = function(self)
         return self.s
      end,
   }

   return setmetatable({
      new = function(s)
         return setmetatable({s=s, i=1, l=1, n=len(s)}, mt)
      end,
   }, {
      __call = function(self, ...)
         return self.new(...)
      end,
   })
end


package.preload['type.strbuf'] = function()
   local _ENV = require 'std.normalize' {
      'std.functional',
   }

   local function __concat(self, x)
      self.n = self.n + 1
      self[self.n] = x
      return self
   end

   local mt = {
      __concat = __concat,

      __index = {
         concat = __concat,
      },

      __len = function(self)
         return self.n
      end,

      __tostring = function(self)
         return concat(map(self, str))
      end,
   }

   return setmetatable({
      new = function(...)
         return setmetatable(pack(...), mt)
      end,
   }, {
      __call = function(self, ...)
         return self.new(...)
      end,
   })
end


package.preload['type.varargs'] = function()
   local _ENV = require 'std.normalize' {}

   local mt; mt = {
      __index = {
      },

      __len = function(self)
         return self.n
      end,
   }

   return setmetatable({
      new = function(...)
         local r = setmetatable(pack(...), mt)
      end,
   }, {
      __call = function(self, ...)
         return self.new(...)
      end,
   })
end


package.preload['smush'] = function()
   local _ENV = require 'std.normalize' {
      'std.functional',
      'type.context-manager',
      Charset = require 'type.charset',
      Scanner = require 'type.scanner',
      StrBuf  = require 'type.strbuf',

      DIGIT = '1234567890',
      IDENT = '_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ',
      SPACE = ' \t\r\n',
      QUOTE = [["']],
   }

   local isdigit = Charset(DIGIT)
   local isident = Charset(IDENT)
   local isidnum = Charset(IDENT .. DIGIT)
   local isspace = Charset(SPACE)

   local function tointeger(x)
      return int(tonumber(x))
   end

   local function comment(scanner, c)
      local l = scanner.l
      if scanner:peek(1) ~= '-' then
         scanner:advance()
         return {'PUNCTUATION', c, l}
      end
      c = scanner:advance(2)
      local buf, eos = StrBuf '--', '\n'
      if c == '[' then
         buf, c = buf .. c, scanner:advance()
         local eqx = 0
         while scanner:peek(eqx) == '=' do
            eqx = eqx + 1
         end
         if scanner:peek(eqx) == '[' then
            eos = ']' .. rep('=', eqx) .. ']'
            buf = buf .. rep('=', eqx) .. '['
            c = scanner:advance(eqx + 1)
         end
      end
      while not scanner:lookahead(eos) do
         buf, c = buf .. c, scanner:advance()
      end
      scanner:advance(len(eos))
      return {'COMMENT', str(buf .. eos), l}
   end

   local function identifier(scanner, c)
      local buf, l = StrBuf(), scanner.l
      while isidnum(c) do
         buf, c = buf .. c, scanner:advance()
      end
      return {'IDENTIFIER', str(buf), l}
   end

   local function longstring(scanner, c)
      local l = scanner.l
      c = scanner:advance()
      if c ~= '[' and c ~= '=' then
         return {'PUNCTUATION', '[', l}
      end
      local eqx = 0
      while scanner:peek(eqx) == '=' do
         eqx = eqx + 1
      end
      if scanner:peek(eqx) ~= '[' then
         return {'PUNCTUATION', '[', l}
      end
      c = scanner:advance(eqx + 1)		-- consume beginning-of-string
      local eos = ']' .. rep('=', eqx) .. ']'
      local buf = StrBuf '[' .. rep('=', eqx) .. '['
      while c ~= ']' or not scanner:lookahead(eos) do
         buf, c = buf .. c, scanner:advance()	-- consume scanned char
      end
      scanner:advance(eqx + 2)			-- consume end-of-string
      return {'STRING', str(buf .. eos), l}
   end

   local function number(scanner, c)
      local buf, l = StrBuf(), scanner.l
      while isdigit(c) do
         buf, c = buf .. c, scanner:advance()
      end
      return {'INTEGER', tointeger(str(buf)), l}
   end

   local function punctuation(scanner, c)
      local l = scanner.l
      scanner:advance()
      return {'PUNCTUATION', c, l}
   end

   local function shortstring(scanner, c)
      local buf, upto, l = StrBuf(c), c, scanner.l
      c = scanner:advance()			-- first non-quote
      while c ~= upto do
          buf = buf .. c
         if c == '\\' then
            buf = buf .. scanner:advance()
         end
         c = scanner:advance()			-- consume scanned char
      end
      scanner:advance()				-- consume closing quote
      return {'STRING', str(buf .. upto), l}
   end

   local function whitespace(scanner, c)
      local buf, l = StrBuf(), scanner.l
      while isspace(c) do
         buf, c = buf .. c, scanner:advance()
      end
      return {'WHITESPACE', str(buf), l}
   end

   local function State(...)
      local r, argu = {}, pack(...)
      for i = 1, argu.n do
         local k, v = next(argu[i])
         if k == 1 then
            for j = 0, 127 do
               r[char(j)] = r[char(j)] or v
            end
         else
            for j = 1, #k do
               r[sub(k, j, j)] = v
            end
         end
      end
      return r
   end

   local start = State(
      {[SPACE] = whitespace},
      {[IDENT] = identifier},
      {[DIGIT] = number},
      {[QUOTE] = shortstring},
      {['[']   = longstring},
      {['-']   = comment},
      {punctuation}
   )

   local tokenize = function(fname)
      local r, scanner = {}, Scanner(slurp(File(fname)))
      while not scanner:eof() do
         local c = scanner:peek()
         append(r, start[c](scanner, c))
      end
      return r
   end

   local function needspace(a, b)
      if a ~= 'INTEGER' and a ~= 'IDENTIFIER' then
         return false
      elseif b ~= 'INTEGER' and b ~= 'IDENTIFIER' then
         return false
      end
      return true
   end

   return {
      main = function()
         map({
            '#!/usr/bin/env lua',
            '--[[ minified code follows, see --help text for source location! ]]',
            'package.searchers=package.searchers or package.loaders',
            'for i=2,#package.searchers do',
            'package.searchers[i]=nil',
            'end',
         }, print)

         map(arg, function(fname)
            print("package.preload['"
              .. gsub(fname, '/', '.'):gsub('lib%.', ''):gsub('%.lua$', ''):gsub('%.init', '')
              .. "']=function()"
            )

            -- Filter out all comment and whitespace tokens.
            local tokens = except(tokenize(fname), function(token)
               return token[1] == 'COMMENT' or token[1] == 'WHITESPACE'
            end)

            -- strategically inject whitespace tokens back into the stream
            local l, prev = 1
            map(tokens, function(token)
               if needspace(prev, token[1]) then
                  write(l < token[3] and '\n' or ' ')
               end
               write(str(token[2]))
               prev, l = token[1], token[3]
            end)

            print '\nend'
         end)

         print "os.exit(require'luke'.main(arg))"
      end,
   }
end


os.exit(require 'smush'.main(arg))

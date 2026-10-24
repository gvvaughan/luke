--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke.functional',
   'package',
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


local function tokenize(fname)
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


-- A module name from the path of the file that holds it.
local function modname(fname)
   return (gsub(fname, '/', '.'):gsub('lib%.', ''):gsub('%.lua$', ''):gsub('%.init$', ''))
end


-- The file for an argument that is a module name rather than a path: find
-- it in the Lua path, as `require` would.
local function modfile(name)
   local fname, err = searchpath(name, path)
   if fname == nil then
      stderr:write('smush: module ', name, ' not found:', err, '\n')
      exit(1)
   end
   return fname
end


-- Each argument is a path, which is bundled under the module name that
-- its path makes, or NAME=PATH, which is bundled as NAME, or else the name
-- of a module to find in the Lua path, which is bundled under that name.
local function source(arg)
   local name, fname = match(arg, '^([%w_.%-]+)=(.+)$')
   if name ~= nil then
      return name, fname
   elseif find(arg, '/', 1, true) or find(arg, '%.lua') then
      return modname(arg), arg
   end
   return arg, modfile(arg)
end


-- The script or module that smush writes, runs bundled packages in a private
-- environment of its own with a copy of the globals, require` and a
-- `package.loaded` so that nothing leaks into the host's `package` module,
-- and nothing leaks out of it, except for the modules that the host is to
-- provide, named by `--external`, which the host has loaded already.  Any
-- other module that the host happens to have loaded, such as typecheck or
-- std.strict, which std.normalize and std.functional behave differently
-- with, is not there for the bundle.
local function header(script, externals)
   return (script and '#!/usr/bin/env lua\n' or '') .. concat({
      '--[[ minified code follows, see --help text for source location! ]]',
      'local host=package',
      'local env={}for k,v in next,_G do env[k]=v end env._G=env',
      'local bundled,loaded={},{}' .. concat(map(externals, function(name)
         return format(' loaded[%q]=host.loaded[%q]', name, name)
      end)),
      'env.package=setmetatable({preload={},loaded=loaded},{__index=host})',
      'local require=function(modname)local m=loaded[modname]if m==nil then',
      'if bundled[modname]==nil then',
      [=[error("module '" .. modname .. "' not found:\n   no bundled module '" .. modname .. "'",2)]=],
      'end',
      'm=bundled[modname](modname)if m==nil then m=true end loaded[modname]=m end',
      'return m end',
      'env.require=require',
      'local _ENV=env',
   }, '\n')
end


-- What follows the bundled modules: run them in their environment.
local function footer(script, entry)
   return concat({
      "if _VERSION=='Lua 5.1'then for _,f in next,bundled do setfenv(f,env)end end",
      script and "os.exit(require'" .. entry .. "'.main(arg))"
              or "return require'" .. entry .. "'",
   }, '\n')
end

-- The tokens of *fname* that matter to the program, without its comments
-- and whitespace.
local function significant(fname)
   return reject(tokenize(fname), function(token)
      return token[1] == 'COMMENT' or token[1] == 'WHITESPACE'
   end)
end

-- Write *tokens* with whitespace strategically injected back into the stream.
local function minify(tokens)
   local l, prev = 1
   each(tokens, function(token)
      if needspace(prev, token[1]) then
         write(l < token[3] and '\n' or ' ')
      end
      write(str(token[2]))
      prev, l = token[1], token[3]
   end)
end


-- The modules that are in the Lua path and not bundled, but which  a
-- string in *tokens* names.  A string such as 'std.functional._base.argscheck'
-- implies the modules std.functional._base, or std.functional or std , so look
-- for the longest of them that is already bundled, or else the longest in the
-- path.  A module that is only asked for as `pcall(require, 'name')` is not
-- flagged as missing.
local function unbundled(tokens, known)
   local r = {}
   for i = 1, len(tokens) do
      local token = tokens[i]
      local name = token[1] == 'STRING' and match(token[2], '^["\']([%w_][%w_.%-]*[%w_])["\']$')
      local optional = i > 2 and tokens[i - 1][2] == ',' and tokens[i - 2][2] == 'require'
      if name and not optional then
         local found
         while name ~= nil and not known[name] do
            found = found or (searchpath(name, path) and name)
            name = match(name, '^(.+)%.[^.]*$')
         end
         if name == nil and found then
            r[found] = true
         end
      end
   end
   return keys(r)
end


--- Write a single file that bundles *sources*.
-- A source is a path, NAME=PATH, or the name of a module in the Lua path.
-- With `--module=NAME` the file is a module that returns the bundled
-- module NAME, otherwise it is a script that exits with what the main
-- function of the bundled module `luke` returns (or of `--main=NAME`).
-- Warn of a module in the Lua path that a bundled module names, but is not
-- bundled, unless it is an `--external=NAME` that the host is to provide.
local function main(args)
   local script, entry, sources, known, externals = true, 'luke', {}, {}, {}
   each(args, function(a)
      local k, v = match(a, '^%-%-(%w+)=(.*)$')
      if k == 'module' then
         script, entry = false, v
      elseif k == 'main' then
         entry = v
      elseif k == 'external' then
         known[v] = true
         append(externals, v)
      else
         append(sources, a)
      end
   end)

   local tokens = {}
   each(sources, function(a)
      local name, fname = source(a)
      known[name], tokens[name] = true, significant(fname)
   end)

   print(header(script, sorted(externals)))

   each(sources, function(a)
      local name = source(a)
      print("bundled['" .. name .. "']=function()")
      minify(tokens[name])
      print '\nend'
      each(sorted(unbundled(tokens[name], known)), function(missing)
         stderr:write('smush: warning: ', name, " names the module '", missing,
            "', which is in the Lua path, but is not bundled\n")
      end)
   end)

   print(footer(script, entry))
end

return {
   main = function(args)
      return main(args or arg)
   end,
}

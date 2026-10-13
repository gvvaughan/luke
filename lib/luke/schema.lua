--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke._base',
   'luke.functional',
   'type.path',
}


--[[
 Normalizers for lukefile values.  Each is called with a value and the
 path to it in the lukefile, and returns that value in its normalized
 form, diagnosing anything malformed.  Absent (nil) values are always
 accepted, and returned as nil.
]]


local function bad(path, ...)
   fatal('bad %s: %s', path, format(...))
end


-- The path to the value at key *k* of the table at *path*, written as a
-- Lua index expression.
local function index(path, k)
   if isstring(k) and match(k, '^[%a_][%w_]*$') then
      return path == '' and k or path .. '.' .. k
   end
   return format(isstring(k) and "%s['%s']" or '%s[%s]', path, str(k))
end


-- A value of type *kind*.
local function mkcheck(kind)
   return function(x, path)
      if x ~= nil and type(x) ~= kind then
         bad(path, '%s expected, got %s', kind, type(x))
      end
      return x
   end
end


-- A list of values that pass *normalize*, or a single string to be
-- treated as a list of one.
local function list_of(normalize)
   return function(x, path)
      if isstring(x) then
         x = {x}
      end
      mkcheck 'table'(x, path)
      if x ~= nil then
         local r = {}
         for i = 1, len(x) do
            r[i] = normalize(x[i], index(path, i))
         end
         return r
      end
   end
end


-- A table mapping names to values that pass *normalize*, and with
-- *names*, names that pass that too.
local function map_of(normalize, names)
   return function(x, path)
      mkcheck 'table'(x, path)
      if x ~= nil then
         local r = {}
         for k, v in next, x do
            if names ~= nil then
               names(k, index(path, k))
            end
            r[k] = normalize(v, index(path, k))
         end
         return r
      end
   end
end


-- A table with only the keys in *schema*, each with a value that passes
-- the normalizer for that key; or with *open*, also any other keys,
-- which are returned as they are.
local function fields(schema, open)
   return function(x, path)
      mkcheck 'table'(x, path)
      if x ~= nil then
         local r = {}
         for k, v in next, x do
            local normalize = schema[k]
            if normalize ~= nil then
               r[k] = normalize(v, index(path, k))
            elseif open then
               r[k] = v
            else
               bad(path, "unsupported key '%s'", str(k))
            end
         end
         return r
      end
   end
end


-- The rules for building a module: a source path, a list of source
-- paths, or a table with `sources` and other build settings.
local function rules(x, path)
   return case(type(x), {
      ['nil'] = nop,

      ['string'] = function()
         return {sources={x}}
      end,

      ['table'] = function()
         if len(x) > 0 then
            return {sources=x}
         elseif isstring(x.sources) then
            return merge({sources = {x.sources}}, x)
         end
         return x
      end,

      function(kind)
         bad(path, 'string or table expected, got %s', kind)
      end,
   })
end


-- The rules for building a program from several sources, with an
-- optional `command` and `env`, as well as the module build settings.
local function program(x, path)
   local r = rules(x, path)
   if isempty(r.sources or {}) then
      bad(path, 'no sources')
   end
   r.sources = list_of(mkcheck 'string')(r.sources, index(path, 'sources'))
   mkcheck 'string'(r.command, index(path, 'command'))
   map_of(mkcheck 'string', mkcheck 'string')(r.env, index(path, 'env'))
   return r
end


-- Like the rockspec `build.install.bin` table, map each name to its
-- source path, naming an array entry with *mkname* from its source.  A
-- table-valued entry is a rule for building a program.
local function mkscripts(mkname)
   -- The name and normalized rules for entry *k* at *path*.
   local function entry(k, source, path)
      return case(type(source), {
         ['string'] = function()
            return choose(isstring(k), k, bind(mkname, {source})), source
         end,

         ['table'] = function()
            local name = choose(isstring(k), k, bind(bad, {path, 'programs need a name'}))
            return name, program(source, path)
         end,

         function(kind)
            bad(path, 'string or table expected, got %s', kind)
         end,
      })
   end

   return function(x, path)
      return mkcheck 'table'(x, path) and reduce(keys(x), {}, function(r, k)
         local name, rules = entry(k, x[k], index(path, k))
         r[name] = rules
      end)
   end
end


-- Scripts, with array entries named for their source, without the
-- directory or any '.in' suffix.
local scripts = mkscripts(function(source)
   return (gsub(basename(source), '%.in$', ''))
end)


-- Generated files, with array entries named for the path of their
-- source, without any '.in' suffix.
local files = mkscripts(function(source)
   return (gsub(source, '%.in$', ''))
end)


return {
   fields  = fields,
   files   = files,
   list_of = list_of,
   map_of  = map_of,
   mkcheck = mkcheck,
   rules   = rules,
   scripts = scripts,
}

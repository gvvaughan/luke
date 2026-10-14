--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke._base',
   'luke.configure',
   'luke.functional',
   'luke.platforms',
   'type.path',
}


-- The name of a C preprocessor macro.
local MACRO = '^[%a_][%w_]*$'

-- The name of every ordered map in the lukefile, which resolves its own
-- platforms, so that platform filtering leaves it alone.
local ORDERED = {defines = true, modules = true}


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


-- Set *name* in *r* to *value*, diagnosing another entry of the table
-- at *path* that already set it, such as an array entry named for its
-- source as well as a key with the same name.
local function claim(r, name, value, path)
   choose(r[name] ~= nil, bind(bad, {path, "more than one entry for '%s'", name}))
   r[name] = value
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
-- the normalizer for that key; or with *others*, also any other keys,
-- with values that pass *others*, or that are returned as they are when
-- *others* is `true`.  The normalizer is a callable table that keeps
-- *schema*, for `keypaths`.
local function fields(schema, others)
   -- Each leg is wrapped, as `choose` would call a normalizer.
   local rest = choose(others == true, function() return id end, function() return others end)
   return setmetatable({schema = schema}, {__call = function(_, x, path)
      return mkcheck 'table'(x, path) and reduce(keys(x), {}, function(r, k)
         local normalize = schema[k] or rest or bind(bad, {path, "unsupported key '%s'", str(k)})
         r[k] = normalize(x[k], index(path, k))
      end)
   end})
end


-- The path of every key in the `fields` normalizer *normalize*, and in
-- each `fields` normalizer nested in it, in sorted order.
local function keypaths(normalize, path)
   return sorted(flatten(map(keys(normalize.schema), function(k)
      local nested, p = normalize.schema[k], index(path or '', k)
      return choose(istable(nested), function()
         return {p, keypaths(nested, p)}
      end, p)
   end)))
end


-- A path, without any empty or '.' components or trailing '/', so that
-- every spelling of a path is the same; or '.' for the directory itself.
-- A '..' component is left alone, as following a symlink may not lead
-- back to the parent.
local function pathname(x, path)
   choose(mkcheck 'string'(x, path) == '', bind(bad, {path, 'empty path'}))
   local r = x and match(x, '^/?') .. concat(except(gmatch(x, '[^/]+'), '.'), '/')
   return choose(r == '', '.', r)
end


-- Whether *x* is a probe, which luke runs at build time for a value.
local function isprobe(x)
   return istable(x) and contains(configure, function(name)
      return x[name] ~= nil
   end)
end


-- A macro definition, as a table pairing the macro name with its value
-- or probe, from such a table or a rockspec style 'NAME' or 'NAME=value'
-- string, where 'NAME' defines NAME to 1.
local function definition(x, path)
   return case(type(x), {
      ['string'] = function()
         local name, eq, value = match(x, '^([%a_][%w_]*)(=?)(.*)$')
         choose(name == nil or eq == '' and value ~= '', bind(bad, {path, "bad macro definition '%s'", x}))
         return {[name] = choose(eq == '', 1, value)}
      end,

      ['table'] = function()
         local names = keys(x)
         choose(names.n ~= 1, bind(bad, {path, 'one definition expected, got %d', names.n}))
         local name = names[1]
         choose(isstring(name) and configure[name] ~= nil,
            bind(bad, {path, 'probe needs a macro name, such as {HAVE_X = {%s = ...}}', str(name)}))
         choose(not isstring(name) or match(name, MACRO) == nil, bind(bad, {path, "bad macro name '%s'", str(name)}))
         local value = x[name]
         choose(not (isstring(value) or type(value) == 'number' or isprobe(value)),
            bind(bad, {index(path, name), 'string, number or probe expected, got %s', type(value)}))
         return {[name] = value}
      end,

      function(kind)
         bad(path, 'string or table expected, got %s', kind)
      end,
   })
end


-- An entry of an ordered map: a table pairing one name with a value
-- that passes *normalize*.
local function pair_of(normalize)
   return function(x, path)
      local names = keys(mkcheck 'table'(x, path))
      choose(names.n ~= 1, bind(bad, {path, 'one entry expected, got %d', names.n}))
      local name = names[1]
      choose(not isstring(name), bind(bad, {path, 'name expected, got %s', type(name)}))
      return {[name] = normalize(x[name], index(path, name))}
   end
end


-- An ordered map: a list of entries in the order written, each
-- normalized by *entry* into a table pairing one name with its value,
-- where a `platforms` table adds or replaces entries for particular
-- platforms.  Every platform's entries are diagnosed, not only those
-- for this one, and so is a field rather than a list entry, or a name
-- with more than one entry for the same platform.  The entries that
-- apply here are merged least specific first, where a more specific
-- entry replaces the value of one for the same name, in place.
local function ordered_map(entry)
   -- *x*, an entry, narrowed for this platform, apart from any ordered
   -- map in it, and then normalized by *entry*.
   local function narrowed(x, path)
      return entry(istable(x) and filter_platforms(x, nil, nil, ORDERED) or x, path)
   end

   -- The entries of one *layer* at *path*, apart from its platforms.
   local function layer_entries(layer, path)
      map(filter(sorted_keys(layer), function(k)
         return k ~= 'platforms' and not islistkey(layer, k)
      end), function(k)
         bad(index(path, k), 'list entry expected, such as {%s = ...}', str(k))
      end)
      local r = list_of(narrowed)(layer, path)
      reduce(r, {}, function(seen, pair)
         claim(seen, (next(pair)), true, path)
      end)
      return r
   end

   -- Diagnose every layer of *x* at *path*, whichever platforms apply.
   local function check_layers(x, path)
      layer_entries(mkcheck 'table'(x, path), path)
      local at = index(path, 'platforms')
      local platforms = mkcheck 'table'(x.platforms, at)
      choose(platforms ~= nil, function()
         local names, others = partition(sorted_keys(platforms), isplatform)
         map(names, function(name)
            check_layers(platforms[name], index(at, name))
         end)
         check_layers(pluck(others, platforms) or {}, at)
      end)
   end

   -- The entries of each layer of *x* at *path* that applies here.
   local function resolve(x, path)
      return ordered_merge(unpack(map(layers(x), function(layer)
         return choose(layer.platforms ~= nil, function()
            return resolve(layer, path)
         end, function()
            return layer_entries(layer, path)
         end)
      end)))
   end

   return function(x, path)
      local t = choose(isstring(x), function()
         return {x}
      end, function()
         return x
      end)
      choose(t ~= nil, bind(check_layers, {t, path}))
      return t and resolve(t, path)
   end
end


-- Like the rockspec `defines` list, macro definitions in the order the
-- compiler sees them.
local defines = ordered_map(definition)


-- The rules for building a module: a source path, a list of source
-- paths, or a table with `sources` and other build settings, where the
-- source and directory paths are normalized.
local function rules(x, path)
   local r = case(type(x), {
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
   return r and merge({
      defines = defines(r.defines, index(path, 'defines')),
      sources = list_of(pathname)(r.sources, index(path, 'sources')),
      incdirs = list_of(pathname)(r.incdirs, index(path, 'incdirs')),
      libdirs = list_of(pathname)(r.libdirs, index(path, 'libdirs')),
   }, r)
end


-- The rules for building a program from several sources, with an
-- optional `command` and `env`, as well as the module build settings.
local function program(x, path)
   local r = rules(x, path)
   if isempty(r.sources or {}) then
      bad(path, 'no sources')
   end
   mkcheck 'string'(r.command, index(path, 'command'))
   map_of(mkcheck 'string', mkcheck 'string')(r.env, index(path, 'env'))
   return r
end


-- Like the rockspec `build.install.bin` table, map each name to its
-- source path, naming an array entry with *mkname* from its source.  A
-- table-valued entry is a rule for building a program.  Names are paths
-- too, of the target built or installed.
local function mkscripts(mkname)
   -- The name and normalized rules for entry *k* at *path*.
   local function entry(k, source, path)
      return case(type(source), {
         ['string'] = function()
            source = pathname(source, path)
            return choose(isstring(k), function()
               return pathname(k, path)
            end, bind(mkname, {source})), source
         end,

         ['table'] = function()
            local name = choose(isstring(k), function()
               return pathname(k, path)
            end, bind(bad, {path, 'programs need a name'}))
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
         claim(r, name, rules, path)
      end)
   end
end


-- *path* without any '.in' suffix, where a template there is filled.
local function filled(path)
   return (gsub(path, '%.in$', ''))
end


-- Scripts, with array entries named for their source, without the
-- directory or any '.in' suffix.
local scripts = mkscripts(function(source)
   return filled(basename(source))
end)


-- Generated files, with array entries named for the path of their
-- source, without any '.in' suffix.
local files = mkscripts(filled)


-- Whether the copy to *dest* in *r* is a template copied under its own
-- name, which is then filled into *dest* without the '.in' as well.
local function fills_too(r, dest)
   return match(dest, '%.in$') ~= nil and match(r[dest].source, '%.in$') ~= nil
end


-- Copies of release files: map each destination path to its source in
-- the release, where an array entry names a path that is the same in
-- both, and is optional, being copied only when the release has it.
local function copies(x, path)
   local r = mkcheck 'table'(x, path) and reduce(keys(x), {}, function(r, k)
      local source = pathname(x[k], index(path, k))
      local dest = choose(isstring(k), function()
         return pathname(k, index(path, k))
      end, source)
      claim(r, dest, {optional = not isstring(k), source = source}, path)
   end)
   -- Every path written, starting with each destination, then the path
   -- each template copied under its own name is filled into.
   reduce(filter(keys(r or {}), bind(fills_too, {r})), copy(r), function(written, dest)
      claim(written, filled(dest), true, path)
   end)
   return r
end


return {
   ORDERED     = ORDERED,

   copies      = copies,
   defines     = defines,
   fields      = fields,
   files       = files,
   keypaths    = keypaths,
   list_of     = list_of,
   map_of      = map_of,
   mkcheck     = mkcheck,
   ordered_map = ordered_map,
   pair_of     = pair_of,
   pathname    = pathname,
   rules       = rules,
   scripts     = scripts,
}

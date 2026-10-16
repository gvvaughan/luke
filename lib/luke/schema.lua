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


-- The lukefile format this luke reads, which goes up by one with each
-- incompatible change to the lukefile syntax.
local FORMAT = 0

-- The name of a C preprocessor macro.
local MACRO = '^[%a_][%w_]*$'

-- The name of every ordered map in the lukefile, which resolves its own
-- platforms, so that platform filtering leaves it alone.
local ORDERED = {
   bin = true, defines = true, external_dependencies = true, files = true, modules = true,
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


-- The lukefile format, which must be the one this luke reads, as each
-- format is incompatible with every other.  Lukefiles for luke 0.4 and
-- earlier have none.
-- TODO: needing an older luke is unreachable while FORMAT is 0, so
-- specify it when FORMAT goes up.
local function luke_format(x, path)
   choose(x == nil, bind(bad, {path,
      'missing; this luke reads format %d, which replaces the lukefiles of luke 0.4 and earlier', FORMAT}))
   choose(int(mkcheck 'number'(x, path)) == nil or x < 0,
      bind(bad, {path, 'non-negative integer expected, got %s', str(x)}))
   choose(x ~= FORMAT, function()
      bad(path, 'lukefile format %d needs %s luke; this one reads format %d',
         x, choose(x > FORMAT, 'a newer', 'an older'), FORMAT)
   end)
   return x
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


-- An entry of an ordered map: a table pairing one name, normalized by
-- *rename* if given, with a value that passes *normalize*.
local function pair_of(normalize, rename)
   return function(x, path)
      local names = keys(mkcheck 'table'(x, path))
      choose(names.n ~= 1, bind(bad, {path, 'one entry expected, got %d', names.n}))
      local name = names[1]
      choose(not isstring(name), bind(bad, {path, 'name expected, got %s', type(name)}))
      return {[(rename or id)(name, path)] = normalize(x[name], index(path, name))}
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
         bad(index(path, k), 'list entry expected, such as {%s = ...}', index('', k))
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


-- The name of an external dependency, which also names its variables,
-- such as `$YAML_DIR`.
local function dependency_name(name, path)
   choose(match(name, MACRO) == nil, bind(bad, {path, "bad dependency name '%s'", name}))
   return name
end


-- Like the rockspec `external_dependencies` table, each dependency name
-- mapped to a table with its `library`, but as an ordered map, so that
-- their compiler and linker flags are added in the order written.
local dependencies = ordered_map(pair_of(mkcheck 'table', dependency_name))


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


-- The source path of a script, or the rules for building a program.
local function script(x, path)
   return case(type(x), {
      ['string'] = function()
         return pathname(x, path)
      end,

      ['table'] = function()
         return program(x, path)
      end,

      function(kind)
         bad(path, 'string or table expected, got %s', kind)
      end,
   })
end


-- Like the rockspec `build.install.bin` table, map each name to its
-- source path, but as an ordered map: each entry is a table pairing a
-- name with its source, or with the rules for building a program, or
-- else a bare source path, named by *mkname* from it.  Names are paths
-- too, of the target built or installed.
local function mkscripts(mkname)
   local pair = pair_of(script, pathname)
   return ordered_map(function(x, path)
      return case(type(x), {
         ['string'] = function()
            local source = pathname(x, path)
            return {[mkname(source)] = source}
         end,

         ['table'] = function()
            -- Every program has sources, so an entry with them is the
            -- rules for a program without a name; a script or program
            -- named 'sources' is written as './sources'.
            choose(x.sources ~= nil,
               bind(bad, {path, 'programs need a name, such as {prog = {sources = ...}}'}))
            return pair(x, path)
         end,

         function(kind)
            bad(path, 'string or table expected, got %s', kind)
         end,
      })
   end)
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


-- Whether the copy of *source* to *dest* is a template copied under its
-- own name, which is then filled into *dest* without the '.in' as well.
local function fills_too(dest, source)
   return match(dest, '%.in$') ~= nil and match(source, '%.in$') ~= nil
end


-- A copy of a release file to a branch: a table pairing the destination
-- path with its source in the release, or else a bare path that is the
-- same in both, which is optional, being copied only when the release
-- has it.
local copy_pair = pair_of(function(x, path)
   return {optional = false, source = pathname(x, path)}
end, pathname)

local function copy_entry(x, path)
   return case(type(x), {
      ['string'] = function()
         local source = pathname(x, path)
         return {[source] = {optional = true, source = source}}
      end,

      ['table'] = function()
         return copy_pair(x, path)
      end,

      function(kind)
         bad(path, 'string or table expected, got %s', kind)
      end,
   })
end


-- Copies of release files to a branch, as an ordered map of
-- `copy_entry`s, in the order written, where a path that a template is
-- filled into is diagnosed when it is also copied, and with the
-- `command`, if any, to run in the branch after copying, such as to
-- remove files that a copied directory should not publish.  Unlike
-- other lists, a single string is diagnosed, as any key of the
-- `release` table that luke does not know names a branch, and that is
-- more likely a typo.
-- TODO: a branch table is named for its branch, not in ORDERED, so its
-- platforms are filtered before this, and only this platform's copies
-- are diagnosed.
local function copies(x, path)
   if mkcheck 'table'(x, path) == nil then
      return nil
   end
   local entries = copy(x)
   entries.command = nil
   local r = ordered_map(copy_entry)(entries, path)
   r.command = mkcheck 'string'(x.command, index(path, 'command'))
   -- Every path written: each destination, then the path that each
   -- template copied under its own name is filled into.
   local written = reduce(ordered_keys(r), {}, function(written, dest)
      written[dest] = true
   end)
   map(r or {}, function(pair)
      local dest, copy = destructure(pair)
      choose(fills_too(dest, copy.source), function()
         claim(written, filled(dest), true, path)
      end)
   end)
   return r
end

return {
   ORDERED      = ORDERED,

   copies       = copies,
   defines      = defines,
   dependencies = dependencies,
   fields       = fields,
   files        = files,
   keypaths     = keypaths,
   list_of      = list_of,
   luke_format  = luke_format,
   map_of       = map_of,
   mkcheck      = mkcheck,
   ordered_map  = ordered_map,
   pair_of      = pair_of,
   pathname     = pathname,
   rules        = rules,
   scripts      = scripts,
}

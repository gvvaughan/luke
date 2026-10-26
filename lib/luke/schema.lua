--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _base = require 'luke._base'
local _configure = require 'luke.configure'
local _ordered = require 'std.prototype.orderedmap'
local _platforms = require 'luke.platforms'
local _set = require 'std.prototype.set'
local _std = require 'std.functional.init'
local _path = require 'type.path'

local _ENV = require 'std.normalize' {
   'string.format',
   'string.gmatch',
   'string.gsub',
   'string.match',
   'table.concat',
   int = 'math.tointeger',
   fatal = _base.fatal,
   isprobe = _configure.isprobe,
   probes = _configure.probes,
   destructure = next,
   bind = _std.bind,
   case = _std.case,
   choose = _std.choose,
   cond = _std.cond,
   each = _std.each,
   except = _std.except,
   filter = _std.filter,
   flatten = _std.flatten,
   foldl = _std.foldl,
   id = _std.id,
   isempty = _std.isempty,
   islistkey = _std.islistkey,
   iter = _std.iter,
   isstring = _std.isstring,
   istable = _std.istable,
   keys = _std.keys,
   map = _std.map,
   merged = _std.merged,
   nop = _std.nop,
   reject = _std.reject,
   sorted = _std.sorted,
   OrderedMap = _ordered.prototype,
   elems = _ordered.elems,
   ordered_keys = _ordered.keys,
   ordered_merge = _ordered.merged,
   Set = _set.prototype,
   isplatform = _platforms.isplatform,
   layers = _platforms.layers,
   narrow_platforms = _platforms.narrow_platforms,
   basename = _path.basename,
}


-- The lukefile format this luke reads, which goes up by one with each
-- incompatible change to the lukefile syntax.
local FORMAT = 0

-- The name of a C preprocessor macro.
local MACRO = '^[%a_][%w_]*$'

-- The name of every ordered map in the lukefile, which resolves its own
-- platforms, so that platform filtering leaves it alone.
local ORDERED = Set {'bin', 'defines', 'external_dependencies', 'files', 'modules'}


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

local checkstring, checktable = mkcheck 'string', mkcheck 'table'


-- *x*, or a list of just *x* if it is a string.
local function listed(x)
   return choose(isstring(x), function()
      return {x}
   end, function()
      return x
   end)
end


-- A list of values that pass *normalize*, or a single string to be
-- treated as a list of one.
local function listof(normalize)
   return function(x, path)
      x = listed(x)
      checktable(x, path)
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
local function mapof(normalize, names)
   return function(x, path)
      checktable(x, path)
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
      return checktable(x, path) and foldl(keys(x), {}, function(r, k)
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
   choose(checkstring(x, path) == '', bind(bad, {path, 'empty path'}))
   local r = x and match(x, '^/?') .. concat(reject(gmatch(x, '[^/]+'), '.'), '/')
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


-- Choose by the type of *x*, a string or a table, with the *branches*
-- for them, and diagnose anything else at *path*.
local function string_or_table(x, path, branches)
   return case(type(x), merged(branches, {
      default = function(kind)
         bad(path, 'string or table expected, got %s', kind)
      end,
   }))
end


-- A macro definition, as a table pairing the macro name with its value
-- or probe, from such a table or a rockspec style 'NAME' or 'NAME=value'
-- string, where 'NAME' defines NAME to 1.
local function definition(x, path)
   return string_or_table(x, path, {
      ['string'] = function()
         local name, eq, value = match(x, '^([%a_][%w_]*)(=?)(.*)$')
         choose(name == nil or eq == '' and value ~= '', bind(bad, {path, "bad macro definition '%s'", x}))
         return {[name] = choose(eq == '', 1, value)}
      end,

      ['table'] = function()
         local names = keys(x)
         choose(names.n ~= 1, bind(bad, {path, 'one definition expected, got %d', names.n}))
         local name = names[1]
         choose(isstring(name) and probes[name] ~= nil,
            bind(bad, {path, 'probe needs a macro name, such as {HAVE_X = {%s = ...}}', str(name)}))
         choose(not isstring(name) or match(name, MACRO) == nil, bind(bad, {path, "bad macro name '%s'", str(name)}))
         local value = x[name]
         choose(not (isstring(value) or type(value) == 'number' or isprobe(value)),
            bind(bad, {index(path, name), 'string, number or probe expected, got %s', type(value)}))
         return {[name] = value}
      end,
   })
end


-- An entry of an ordered map: a table pairing one name, normalized by
-- *rename* if given, with a value that passes *normalize*.
local function pairof(normalize, rename)
   return function(x, path)
      local names = keys(checktable(x, path) or {})
      choose(names.n ~= 1, bind(bad, {path, 'one entry expected, got %d', names.n}))
      local name = names[1]
      choose(not isstring(name), bind(bad, {path, 'name expected, got %s', type(name)}))
      return {[(rename or id)(name, path)] = normalize(x[name], index(path, name))}
   end
end


-- An ordered map, which is an OrderedMap of the entries in the order written,
-- each normalized by *entry* into a table pairing one name with its value,
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
      return entry(choose(istable(x), function()
         return narrow_platforms(x, ORDERED)
      end, function()
         return x
      end), path)
   end

   -- The entries of one *layer* at *path*, apart from its platforms.
   local function layer_entries(layer, path)
      each(filter(keys(layer), function(k)
         return k ~= 'platforms' and not islistkey(layer, k)
      end), function(k)
         bad(index(path, k), 'list entry expected, such as {%s = ...}', index('', k))
      end)
      local r = listof(narrowed)(layer, path)
      local seen = {}
      each(r, function(pair)
         claim(seen, (destructure(pair)), true, path)
      end)
      return r
   end

   -- Diagnose every layer of *x* at *path*, whichever platforms apply.
   local function check_layers(x, path)
      layer_entries(checktable(x, path), path)
      local at = index(path, 'platforms')
      local platforms = checktable(x.platforms, at)
      choose(platforms ~= nil, function()
         each(filter(keys(platforms), isplatform), function(name)
            check_layers(platforms[name], index(at, name))
         end)
         check_layers(except(platforms, isplatform), at)
      end)
   end

   -- The entries of each layer of *x* at *path* that applies here, in an
   -- OrderedMap.
   local function resolve(x, path)
      return ordered_merge(unpack(map(layers(x), function(layer)
         return choose(layer.platforms ~= nil, function()
            return resolve(layer, path)
         end, function()
            return OrderedMap(layer_entries(layer, path))
         end)
      end)))
   end

   return function(x, path)
      local t = listed(x)
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
local dependencies = ordered_map(pairof(checktable, dependency_name))


-- The rules for building a module: a source path, a list of source
-- paths, or a table with `sources` and other build settings, where the
-- source and directory paths are normalized.
local function rules(x, path)
   local r = string_or_table(x, path, {
      ['nil'] = nop,

      ['string'] = function()
         return {sources={x}}
      end,

      ['table'] = function()
         return cond({len(x) > 0, {sources = x}}, {true, x})
      end,
   })
   return r and merged(r, {
      defines = defines(r.defines, index(path, 'defines')),
      sources = listof(pathname)(r.sources, index(path, 'sources')),
      incdirs = listof(pathname)(r.incdirs, index(path, 'incdirs')),
      libdirs = listof(pathname)(r.libdirs, index(path, 'libdirs')),
   })
end


-- The rules for building a program from several sources, with an
-- optional `command` and `env`, as well as the module build settings.
local function program(x, path)
   local r = rules(x, path)
   if isempty(r.sources or {}) then
      bad(path, 'no sources')
   end
   checkstring(r.command, index(path, 'command'))
   mapof(checkstring, checkstring)(r.env, index(path, 'env'))
   return r
end


-- The source path of a script, or the rules for building a program.
local function script(x, path)
   return string_or_table(x, path, {
      ['string'] = function()
         return pathname(x, path)
      end,

      ['table'] = function()
         return program(x, path)
      end,
   })
end


-- Like the rockspec `build.install.bin` table, map each name to its
-- source path, but as an ordered map: each entry is a table pairing a
-- name with its source, or with the rules for building a program, or
-- else a bare source path, named by *mkname* from it.  Names are paths
-- too, of the target built or installed.
local function mkscripts(mkname)
   local pair = pairof(script, pathname)
   return ordered_map(function(x, path)
      return string_or_table(x, path, {
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
local copy_pair = pairof(function(x, path)
   return {optional = false, source = pathname(x, path)}
end, pathname)

local function copy_entry(x, path)
   return string_or_table(x, path, {
      ['string'] = function()
         local source = pathname(x, path)
         return {[source] = {optional = true, source = source}}
      end,

      ['table'] = function()
         return copy_pair(x, path)
      end,
   })
end


-- Copies of release files to a branch, as a table with its `copies`, an
-- ordered map of `copy_entry`s in the order written, where a path that a
-- template is filled into is diagnosed when it is also copied, and the
-- `command`, if any, to run in the branch after copying, such as to
-- remove files that a copied directory should not publish.  Unlike
-- other lists, a single string is diagnosed, as any key of the
-- `release` table that luke does not know names a branch, and that is
-- more likely a typo.
-- TODO: a branch table is named for its branch, not in ORDERED, so its
-- platforms are filtered before this, and only this platform's copies
-- are diagnosed.
local function copies(x, path)
   if checktable(x, path) == nil then
      return nil
   end
   local r = ordered_map(copy_entry)(except(x, 'command'), path)
   -- Every path written: each destination, then the path that each
   -- template copied under its own name is filled into.
   local written = Set(ordered_keys(r))
   each(iter(elems(r)), function(dest, entry)
      choose(fills_too(dest, entry.source), function()
         claim(written, filled(dest), true, path)
      end)
   end)
   return {copies = r, command = checkstring(x.command, index(path, 'command'))}
end

return {
   ORDERED      = ORDERED,

   bad          = bad,
   index        = index,
   copies       = copies,
   defines      = defines,
   dependencies = dependencies,
   fields       = fields,
   files        = files,
   keypaths     = keypaths,
   listof      = listof,
   luke_format  = luke_format,
   mapof       = mapof,
   mkcheck      = mkcheck,
   ordered_map  = ordered_map,
   pairof      = pairof,
   pathname     = pathname,
   rules        = rules,
   scripts      = scripts,
}

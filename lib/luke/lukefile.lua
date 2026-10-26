--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _configure = require 'luke.configure'
local _environment = require 'luke.environment'
local _functional = require 'luke.functional'
local _platforms = require 'luke.platforms'
local _schema = require 'luke.schema'
local _std = require 'std.functional.init'
local _context = require 'type.context-manager'

local _ENV = require 'std.normalize' {
   'io.lines',
   'string.format',
   'string.match',
   configure = _configure.configure,
   isprobe = _configure.isprobe,
   expand = _environment.expand,
   destructure = next,
   bind = _std.bind,
   case = _std.case,
   compact = _std.compact,
   cond = _std.cond,
   each = _std.each,
   either = _std.either,
   except = _std.except,
   filter = _std.filter,
   flatmap = _std.flatmap,
   flatten = _std.flatten,
   id = _std.id,
   indexof = _std.indexof,
   isempty = _std.isempty,
   istable = _std.istable,
   keys = _std.keys,
   map = _std.map,
   mapvalues = _std.mapvalues,
   merged = _std.merged,
   sorted = _std.sorted,
   ordered_get = _functional.ordered_get,
   ordered_keys = _functional.ordered_keys,
   ordered_mapvalues = _functional.ordered_mapvalues,
   narrow_platforms = _platforms.narrow_platforms,
   ORDERED = _schema.ORDERED,
   bad = _schema.bad,
   copies = _schema.copies,
   defines = _schema.defines,
   dependencies = _schema.dependencies,
   fields = _schema.fields,
   files = _schema.files,
   index = _schema.index,
   keypaths = _schema.keypaths,
   listof = _schema.listof,
   luke_format = _schema.luke_format,
   mkcheck = _schema.mkcheck,
   ordered_map = _schema.ordered_map,
   pairof = _schema.pairof,
   pathname = _schema.pathname,
   rules = _schema.rules,
   scripts = _schema.scripts,
   File = _context.File,
   slurp = _context.slurp,
   with = _context.with,
}


--[[
 The lukefile schema: every key luke understands, with the normalizer
 that turns its value into the form the rest of luke relies on, after
 platform overrides are filtered and probe tables are normalized.
 Normalizers diagnose malformed values, and come from `luke.schema`.
]]

local str, t = mkcheck 'string', mkcheck 'table'

-- How `luke release` updates NEWS, writes the release rockspec, edits
-- files for the release branch, commits generated files, and whether
-- it first checks that the rockspec's dependencies are installed; any
-- other key names a branch, such as `gh-pages`, mapped to the release
-- files to copy there.  The `rockspec` can be a list, to release more
-- than one rock together, at one version.
--
-- To release rocks separately, each with versions of its own, every
-- development rockspec is instead the key of a table of the keys above,
-- except `rockspec`, or a bare name when there are none, and nothing else.
local RELEASEKEYS = {
   add                = listof(pathname),
   check_dependencies = mkcheck 'boolean',
   news               = pathname,
   replacements       = ordered_map(pairof(ordered_map(pairof(str)), pathname)),
}
local release_fields = fields(merged(RELEASEKEYS, {rockspec = listof(pathname)}), copies)
local rock_fields = fields(RELEASEKEYS, copies)


local function isrockspec(k)
   return type(k) == 'string' and match(k, '%.rockspec$') ~= nil
end


local RELEASE = setmetatable({schema = release_fields.schema}, {__call = function(_, x, path)
   if t(x, path) == nil then
      return nil
   end
   local own, rocks = {}, {}
   for k, v in next, x do
      if type(k) == 'number' then
         -- A bare development rockspec, for a rock with no other keys.
         if not isrockspec(str(v, index(path, k))) then
            bad(index(path, k), 'development rockspec name expected, got %s', v)
         end
         rocks[v] = {}
      elseif isrockspec(k) then
         rocks[k] = rock_fields(v, index(path, k))
      else
         own[k] = v
      end
   end
   if next(rocks) == nil then
      return release_fields(x, path)
   elseif next(own) ~= nil then
      bad(path, 'a release table with rockspecs has no other keys: put them in an entry of one')
   end
   return rocks
end})


-- TODO: lukefile keys luke does not understand are let through, as a
-- rockspec-style lukefile may have fields for other tools; diagnose
-- misspellings of the keys below.
local LUKEFILE = fields({
   luke_format           = luke_format,
   package               = str,
   version               = str,

   defines               = defines,
   external_dependencies = dependencies,
   incdirs               = listof(pathname),
   ldocs                 = rules,
   libdirs               = listof(pathname),
   libraries             = listof(id),
   modules               = ordered_map(pairof(rules)),
   substitute            = t,
   variables             = t,

   bin                   = scripts,
   files                 = files,
   install               = fields {
      bin = scripts,
   },

   release               = RELEASE,
}, true)


-- Every probe in *luke*, in the order it is written: list entries in
-- order, and the elements of any other table in `keys` order, so
-- that probes of the same kind run in the same order on every run.
local function collect_configs(luke, modulename, sectionname)
   return flatmap(keys(luke), function(k)
      local v = luke[k]
      return cond({isprobe(v), {{t=luke, k=k, module=modulename, section=sectionname}}},
         {istable(v) and (k == 'modules' or k == 'external_dependencies'), function()
            return flatmap(v, function(pair)
               local name, rules = destructure(pair)
               return collect_configs(rules, name, k)
            end)
         end},
         {istable(v), function()
            return collect_configs(v, modulename, sectionname)
         end})
   end)
end


local function deepcopy(tree)
   return mapvalues(tree, function(v)
      if istable(v) then
         return deepcopy(v)
      end
      return v
   end)
end


-- The position of the kind of probe that *config* is in the order of
-- `configure`, so that headers are settled before linking against
-- functions, for example.
local function weight(config)
   local probe = config.t[config.k]
   return indexof(configure, function(kind)
      return probe[kind] ~= nil
   end)
end


-- Probes run by kind, in the order of `configure`, and then in the order
-- they are written, as `sorted` keeps the order of probes of one kind.
local function config_cmp(a, b)
   return weight(a) < weight(b)
end


local function fill_templates(env, src, dest)
   with(File(dest, 'w'), function(cm)
      each(lines(src), function(line)
         cm:write(expand(env, line) .. '\n')
      end)
   end)
end


local function rewrite_template_files(L, env, source)
   return case(source, {
      {'(.+)%.in', function(r)
         -- Fill each template once, even when a module and a script
         -- share it.
         if not L.filled[r] then
            L.filled[r] = true
            L.write('creating ' .. r .. '\n')
            if not L.dryrun then
               fill_templates(env, r .. '.in', r)
            end
         end
         return r
      end},

      default = source,
   })
end


-- The variables that say where the external dependency *name* is, and
-- where its executables, headers and libraries are beneath that.
local function dependency_variables(name)
   local rootdir = '$' .. name .. '_DIR'
   return {
      [name .. '_DIR']    = '/usr',
      [name .. '_BINDIR'] = rootdir .. '/bin',
      [name .. '_INCDIR'] = rootdir .. '/include',
      [name .. '_LIBDIR'] = rootdir .. '/lib',
   }
end


local function collect_variables(luke)
   return merged(unpack(flatmap(keys(luke), function(k)
      local v = luke[k]
      return cond(
         {k == 'external_dependencies', function()
            return map(ordered_keys(v), dependency_variables)
         end},
         {istable(v), function()
            return {collect_variables(v)}
         end}
      )
   end)))
end


-- The singular probe keys, each with the plural that it joins.
local PLURALS = {include = 'includes', prog = 'progs', library = 'libraries'}


-- *config* with the value of each singular key merged, ahead of those
-- of its plural.
local function pluralize(config)
   local r = except(config, function(k)
      return PLURALS[k] ~= nil
   end)
   each(keys(PLURALS), function(singular)
      if config[singular] ~= nil then
         local plural = PLURALS[singular]
         r[plural] = compact(flatten(pack(config[singular], config[plural])))
      end
   end)
   return r
end


local function normalize_configs(config)
   return cond({not istable(config), function()
      return config
   end}, {not isprobe(config), function()
      return mapvalues(config, normalize_configs)
   end}, {true, function()
      return pluralize(config)
   end})
end


-- Whether the external dependency *config* needs a library: `{}` is
-- unsupported, and `{library = ''}` needs none.
local function needs_library(config)
   return istable(config) and not isempty(config) and config.library ~= ''
end


-- The list *existing* followed by *items*, or nil if there are none.
local function extend(existing, items)
   return either(compact(flatten(pack(existing, items))), nil)
end


local function unwrap_external_dependencies(luke)
   if istable(luke.external_dependencies) then
      local needed = filter(luke.external_dependencies, function(pair)
         local _, config = destructure(pair)
         return needs_library(config)
      end)
      local prefixes = ordered_keys(needed)
      luke.incdirs = extend(luke.incdirs, map(prefixes, bind(format, {'$%s_INCDIR'})))
      luke.libdirs = extend(luke.libdirs, map(prefixes, bind(format, {'$%s_LIBDIR'})))
      luke.libraries = extend(luke.libraries, map(prefixes, function(prefix)
         return ordered_get(needed, prefix).library
      end))
      luke.external_dependencies = nil
   end
   return luke
end


-- Normalize the table *r* of the settings of a lukefile, however they were
-- written, such as the globals of a lukefile or the `build` table of a
-- rockspec, to fully specified values, one time only, so the rest of the
-- code can safely operate on the normalized table contents.
local function normalize(r)
   -- A lukefile for a newer luke is diagnosed before any syntax that
   -- this luke doesn't know.
   luke_format(r.luke_format, 'luke_format')
   -- Each ordered map resolves its own platforms, to diagnose its
   -- entries for every platform, not only this one.
   return LUKEFILE(normalize_configs(narrow_platforms(r, ORDERED)), '')
end


return {
   -- Load `lukefile` into a nested Lua table, normalized, so that the
   -- rest of the code can safely operate on the table contents.
   loadluke = function(filename)
      local content, err = slurp(File(filename))
      if content == nil then
         return nil, err
      end
      local r = {}
      local chunk, err = load(content, filename, 't', r)
      if chunk == nil then
         return nil, "Error loading file: " .. err
      end
      local ok, err = pcall(chunk)
      if not ok then
         return nil, "Error running file: " .. err
      end
      return normalize(r)
   end,

   normalize = normalize,

   collect_variables = collect_variables,

   -- The branches that the lukefile *release* table copies files to,
   -- in sorted order.
   branches = function(release)
      return filter(keys(release or {}), function(k)
         return RELEASE.schema[k] == nil and not isrockspec(k)
      end)
   end,

   -- The path of every lukefile key luke understands, such as
   -- `install.bin`, in sorted order.
   keypaths = function()
      return keypaths(LUKEFILE)
   end,

   -- The scripts, programs and generated files of *luke*, by the
   -- section name that build entries are looked up with.
   -- The script sections in build order: scripts before generated
   -- files, which may be made by running them.
   SCRIPT_SECTIONS = {'bin', 'install', 'files'},

   script_sections = function(luke)
      return {
         bin     = luke.bin or {},
         files   = luke.files or {},
         install = (luke.install or {}).bin or {},
      }
   end,

   -- If *source* ends with '.in', copy it to a file without the suffix,
   -- expanding all '@varname@' templates; return the resulting path.
   fill_template = rewrite_template_files,

   -- Recursively collect every config table from normalized lukefile
   -- table, and execute each in topological order.
   run_configs = function(L, env, luke)
      local r = deepcopy(luke)
      each(sorted(collect_configs(r), config_cmp), function(config)
         local prefix = case(config.section, {
            external_dependencies = function() return config.module end,
         })
         config.t[config.k] = configure(L, env, config.t[config.k], prefix)
      end)
      return unwrap_external_dependencies(r)
   end,

   -- For all modules, copy source files with names ending with '.in',
   -- expanding all '@varname@' templates, writing the result back to a
   -- source with the '.in' suffix removed.
   run_templates = function(L, env, luke)
      local rewrite = bind(rewrite_template_files, {L, env})
      local function rewritten(rules)
         return merged(rules, {sources = map(rules.sources, rewrite)})
      end

      local r = merged(luke)
      r.modules = ordered_mapvalues(r.modules, rewritten)
      if r.ldocs then
         r.ldocs = rewritten(r.ldocs)
      end
      return r
   end,
}

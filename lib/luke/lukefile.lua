--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke._base',
   'luke.configure',
   'luke.environment',
   'luke.platforms',
   'luke.functional',
   'luke.schema',
   'type.context-manager',
   'type.path',
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
-- files to copy there.
local RELEASE = fields({
   add                = list_of(pathname),
   check_dependencies = mkcheck 'boolean',
   news               = pathname,
   replacements       = ordered_map(pair_of(ordered_map(pair_of(str)), pathname)),
   rockspec           = pathname,
}, copies)

-- TODO: lukefile keys luke does not understand are let through, as a
-- rockspec-style lukefile may have fields for other tools; diagnose
-- misspellings of the keys below.
local LUKEFILE = fields({
   luke_format           = luke_format,
   package               = str,
   version               = str,

   defines               = defines,
   external_dependencies = dependencies,
   incdirs               = list_of(pathname),
   ldocs                 = rules,
   libdirs               = list_of(pathname),
   libraries             = list_of(id),
   modules               = ordered_map(pair_of(rules)),
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
-- order, and the elements of any other table in `sorted_keys` order, so
-- that probes of the same kind run in the same order on every run.
local function collect_configs(luke, modulename, sectionname)
   return flatmap(sorted_keys(luke), function(k)
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


local function collect_variables(luke, variables)
   for k, v in next, luke do
      if k == 'external_dependencies' then
         each(ordered_keys(v), function(name)
            merge(variables, dependency_variables(name))
         end)
      elseif istable(v) then
         collect_variables(v, variables)
      end
   end
   return variables
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
         r[plural] = flatten(config[singular], config[plural])
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
   return either(flatten(existing, items), nil)
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


return {
   -- Load `lukefile` into a nested Lua table, normalizing valid shorthands
   -- from the file to fully specified values in the returned table one
   -- time only while we're loading, so the rest of the code can safely
   -- operate on the normalized table contents.
   loadluke = function(filename)
      local content, err = slurp(File(filename))
      if content == nil then
         return nil, err
      end
      local r = {}
      local chunk, err = loadstring(content, filename, r)
      if chunk == nil then
         return nil, "Error loading file: " .. err
      end
      local ok, err = pcall(chunk)
      if not ok then
         return nil, "Error running file: " .. err
      end
      -- A lukefile for a newer luke is diagnosed before any syntax that
      -- this luke doesn't know.
      luke_format(r.luke_format, 'luke_format')
      -- Each ordered map resolves its own platforms, to diagnose its
      -- entries for every platform, not only this one.
      return LUKEFILE(normalize_configs(filter_platforms(r, nil, nil, ORDERED)), '')
   end,

   collect_variables = function(luke)
      return collect_variables(luke, {})
   end,

   -- The branches that the lukefile *release* table copies files to,
   -- in sorted order.
   branches = function(release)
      return filter(sorted(keys(release or {})), function(k)
         return RELEASE.schema[k] == nil
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
         return merge({sources = map(rules.sources, rewrite)}, rules)
      end

      local r = copy(luke)
      r.modules = ordered_mapvalues(r.modules, rewritten)
      if r.ldocs then
         r.ldocs = rewritten(r.ldocs)
      end
      return r
   end,
}

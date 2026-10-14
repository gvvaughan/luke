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

local string, table = mkcheck 'string', mkcheck 'table'

-- How `luke release` updates NEWS, writes the release rockspec, and
-- commits generated files; any other key names a branch, such as
-- `gh-pages`, mapped to the release files to copy there.
local RELEASE = fields({
   add      = list_of(pathname),
   news     = pathname,
   rockspec = pathname,
}, copies)

-- TODO: lukefile keys luke does not understand are let through, as a
-- rockspec-style lukefile may have fields for other tools; diagnose
-- misspellings of the keys below.
local LUKEFILE = fields({
   package               = string,
   version               = string,

   defines               = defines,
   external_dependencies = dependencies,
   incdirs               = list_of(pathname),
   ldocs                 = rules,
   libdirs               = list_of(pathname),
   libraries             = list_of(id),
   modules               = ordered_map(pair_of(rules)),
   substitute            = table,
   variables             = table,

   bin                   = scripts,
   files                 = files,
   install               = fields {
      bin = scripts,
   },

   release               = RELEASE,
}, true)


local function has_anykey(t, keylist)
   return any(map(keylist, function(k)
      return t[k] ~= nil
   end))
end


local function isconfig(x)
   return istable(x) and has_anykey(x, configure)
end


-- Every probe in *luke*, in the order it is written: list entries in
-- order, and the elements of any other table in `sorted_keys` order, so
-- that probes of the same kind run in the same order on every run.
local function collect_configs(luke, modulename, configs, sectionname)
   configs = configs or {}
   map(sorted_keys(luke), function(k)
      local v = luke[k]
      cond({
         [isconfig(v)] = function()
            append(configs, {t=luke, k=k, module=modulename, section=sectionname, order=len(configs) + 1})
         end,
      }, {
         [istable(v) and (k == 'modules' or k == 'external_dependencies')] = function()
            map(v, function(pair)
               local name, rules = destructure(pair)
               collect_configs(rules, name, configs, k)
            end)
         end,
      }, {
         [istable(v)] = function()
            collect_configs(v, modulename, configs, sectionname)
         end,
      })
   end)
   return configs
end


local function deepcopy(t)
   return mapvalues(t, function(v)
      return case(type(v), {
         ['table'] = function() return deepcopy(v) end,
         v,
      })
   end)
end


local weighting = setmetatable(copy(configure), {
   __call = function(self, config)
      local t = config.t[config.k]
      for i = 1, len(self) do
         if t[self[i]] ~= nil then
            return i
         end
      end
   end
})


-- Probes run by kind, in the order of `configure`, so that headers are
-- settled before linking against functions, for example, and then in the
-- order they are written.
local function config_cmp(a, b)
   local wa, wb = weighting(a), weighting(b)
   return wa < wb or wa == wb and a.order < b.order
end


local function fill_templates(env, src, dest)
   with(File(dest, 'w'), function(cm)
      for line in lines(src) do
         cm:write(expand(env, line) .. '\n')
      end
   end)
   return dest
end


local function rewrite_template_files(L, env, source)
   return case(source, {
      ['(.+)%.in'] = function(r)
         L.write('creating ' .. r .. '\n')
         return fill_templates(env, r .. '.in', r)
      end,

      source,
   })
end


local function collect_variables(luke, variables)
   for k, v in next, luke do
      if k == 'external_dependencies' then
         map(ordered_keys(v), function(name)
            local rootdir = concat{'$', name, '_DIR'}
            variables[name .. '_DIR'] = '/usr'
            variables[name .. '_BINDIR'] = rootdir .. '/bin'
            variables[name .. '_INCDIR'] = rootdir .. '/include'
            variables[name .. '_LIBDIR'] = rootdir .. '/lib'
         end)
      elseif istable(v) then
         collect_variables(v, variables)
      end
   end
   return variables
end


local function normalize_configs(config)
   return cond({
      [not istable(config)] = config,
   }, {
      [not isconfig(config)] = function()
         return mapvalues(config, normalize_configs)
      end,
   }, {
      [true] = function()
         local keymap = {
            include = 'includes',
            prog = 'progs',
            library = 'libraries',
         }
         return foldkeys(keymap, config, function(a, b)
            local r = istable(a) and copy(a) or {a}
            b = istable(b) and b or {b}
            return reduce(b, r, function(v)
               append(r, v)
            end)
         end)
      end,
   })
end


local function unwrap_external_dependencies(luke)
   if istable(luke.external_dependencies) then
      map(luke.external_dependencies, function(pair)
         local prefix, config = destructure(pair)
         -- `config={}` for unsupported, `config={library=''}` for no library required
         if istable(config) and next(config) and config.library ~= '' then
            luke.incdirs = append(luke.incdirs or {}, format('$%s_INCDIR', prefix))
            luke.libdirs = append(luke.libdirs or {}, format('$%s_LIBDIR', prefix))
            luke.libraries = append(luke.libraries or {}, config.library)
         end
      end)
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
   fill_template = function(L, env, source)
      return rewrite_template_files(L, env, source)
   end,

   -- Recursively collect every config table from normalized lukefile
   -- table, and execute each in topological order.
   run_configs = function(L, env, luke)
      local r = deepcopy(luke)
      map(sorted(collect_configs(r), config_cmp), function(config)
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
      local r = copy(luke)
      local rewrite = bind(rewrite_template_files, {L, env})
      r.modules = ordered_mapvalues(r.modules, function(rules)
         rules.sources = map(rules.sources, rewrite)
         return rules
      end)
      if r.ldocs then
         r.ldocs.sources = map(r.ldocs.sources, rewrite)
      end
      return r
   end,
}

--[[
 Use the source, Luke!
 Copyright (C) 2014-2023 Gary V. Vaughan
]]

local _ENV = require 'std.normalize' {
   'luke._base',
   'luke.configure',
   'luke.environment',
   'luke.platforms',
   'std.functional',
   'type.context-manager',
}


local function has_anykey(t, keylist)
   return any(map(keylist, function(k)
      return t[k] ~= nil
   end))
end


local function isconfig(x)
   return istable(x) and has_anykey(x, configure)
end


local function collect_configs(luke, modulename, configs, sectionname)
   configs = configs or {}
   for k, v in next, luke do
      if isconfig(v) then
         append(configs, {t=luke, k=k, module=modulename, section=sectionname})
      elseif istable(v) then
         if k == 'modules' or k == 'external_dependencies' then
            for name, rules in next, v do
               collect_configs(rules, name, configs, k)
            end
         else
            collect_configs(v, modulename, configs, sectionname)
         end
      end
   end
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


local function config_cmp(a, b)
   return weighting(a) < weighting(b)
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
         map(keys(v), function(name)
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


local function normalize_rules(rules)
   return case(type(rules), {
      ['nil'] = nop,

      ['string'] = function()
         return {sources={rules}}
      end,

      ['table'] = function()
         if len(rules) > 0 then
            return {sources=rules}
         elseif isstring(rules.sources) then
            return merge({sources = {rules.sources}}, normalize_configs(rules))
         end
         return normalize_configs(rules)
      end,

      function(v)
         fatal("unsupported rule type '%s'", v)
      end,
   })
end


local function unwrap_external_dependencies(luke)
   if istable(luke.external_dependencies) then
      for prefix, config in next, luke.external_dependencies do
         -- `config={}` for unsupported, `config={library=''}` for no library required
         if istable(config) and next(config) and config.library ~= '' then
            luke.incdirs = append(luke.incdirs or {}, format('$%s_INCDIR', prefix))
            luke.libdirs = append(luke.libdirs or {}, format('$%s_LIBDIR', prefix))
            luke.libraries = append(luke.libraries or {}, config.library)
         end
      end
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
      r = filter_platforms(r)
      r.external_dependencies = normalize_configs(r.external_dependencies)
      r.ldocs = normalize_rules(r.ldocs)
      r.modules = mapvalues(r.modules, normalize_rules)
      return r
   end,

   collect_variables = function(luke)
      return collect_variables(luke, {})
   end,

   -- Recursively collect every config table from normalized lukefile
   -- table, and execute each in topological order.
   run_configs = function(L, env, luke)
      local r = deepcopy(luke)
      local all_configs = collect_configs(r)
      sort(all_configs, config_cmp)
      map(all_configs, function(config)
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
      r.modules = mapvalues(r.modules, function(rules)
         rules.sources = map(rules.sources, rewrite)
      end)
      if r.ldocs then
         r.ldocs.sources = map(r.ldocs.sources, rewrite)
      end
      return r
   end,
}

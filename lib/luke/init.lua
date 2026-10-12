--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke.cli',
   'luke.compile',
   'luke.configure',
   'luke.environment',
   'luke.lukefile',
   'luke.functional',
}


local function run_ldocs(L, env, ldocs)
   return run_command(L, env, flatten{'$LDOC -c', ldocs.sources, '.'})
end


-- The rules for script *entry*, as selected by `validate_arguments`.
local function script_rules(L, entry)
   if entry.installed then
      return L.luke.install.bin[entry.name]
   end
   return L.luke.bin[entry.name]
end


local function build_script(L, env, substitute, entry)
   local rules = script_rules(L, entry)
   local target = script_target(entry.name, rules, L.luke.variables.objdir, entry.installed)

   if isstring(rules) then
      fill_template(L, substitute, rules)
   else
      -- TODO: a template shared with a module being built is filled
      -- twice.
      local sources = map(rules.sources, function(source)
         return fill_template(L, substitute, source)
      end)
      local status = build_program(L, env, L.luke, rules, target, sources)
      if status ~= 0 then
         return status
      end
   end

   return make_executable(L, env, target)
end


local function build(L, env)
   local modules = not isempty(L.luke.modules or {})
   local conf = makeenv(CONFIGENV, env)

   if modules and not isempty(L.luke.ldocs or {}) then
      conf = config_ldoc(L, conf)
      env = makeenv(env, {LDOC=conf.LDOC})
   end

   local c = c_modules(L.luke.modules or {})
   local cprograms = filter(L.scripts.build, function(entry)
      return c_program(script_rules(L, entry))
   end)
   if not isempty(c) or not isempty(cprograms) then
      conf = config_compiler(L, conf)
      env = makeenv(env, {CC=conf.CC})
   end
   -- TODO: this runs the probes in every bin and install.bin rule, even
   -- those not selected by the command line targets.
   L.luke = run_configs(L, conf, L.luke)

   local substitute = makeenv(L.clidefs, L.luke.substitute, SHELLENV)
   local status = 0

   if modules then
      L.luke = run_templates(L, substitute, L.luke)

      status = dropuntil(c, isnonzero, function(name)
         return build_c_module(L, env, L.luke, name)
      end) or 0

      if status == 0 and not isempty(L.luke.ldocs or {}) then
         status = run_ldocs(L, env, L.luke.ldocs)
      end
   end

   if status == 0 then
      status = dropuntil(L.scripts.build, isnonzero, function(entry)
         return build_script(L, env, substitute, entry)
      end) or 0
   end

   return status
end


return {
   main = function(args)
      local L = validate_arguments(parse_arguments(args))
      local env = makeenv(L.clidefs, L.luke.variables, DEFAULTENV, SHELLENV)
      local status = 0

      if not isempty(L.valreqs) then
         map(L.valreqs, function(name)
            print(interpolate(env, concat {name, "='$", name, "'"}))
         end)
         exit(0)
      end

      if not isempty(L.luke.modules or {}) or not isempty(L.scripts.build) then
         status = build(L, env)
      end

      if status == 0 then
         status = install_modules(L, env, L.luke, L.install)
      end

      if status == 0 then
         status = install_scripts(L, env, L.luke, L.scripts.install)
      end

      return status
   end,
}

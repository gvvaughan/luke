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
   'luke.release',
}


local function run_ldocs(L, env, ldocs)
   return run(L, env, flatten{'$LDOC -c', ldocs.sources, '.'})
end


-- The rules for script *entry*, as selected by `validate_arguments`.
local function script_rules(L, entry)
   return ordered_get(script_sections(L.luke)[entry.section], entry.name)
end


-- Build the script, program or generated file for *entry*, making all
-- but generated files executable.
local function build_script(L, env, substitute, entry)
   local rules = script_rules(L, entry)
   local target = script_target(entry.name, rules, L.luke.variables.objdir, entry.section == 'install')

   if isstring(rules) then
      fill_template(L, substitute, rules)
   else
      local sources = map(rules.sources, function(source)
         return fill_template(L, substitute, source)
      end)
      local status = build_program(L, env, L.luke, rules, target, sources)
      if status ~= 0 then
         return status
      end
   end

   return choose(entry.section == 'files', 0, bind(make_executable, {L, env, target}))
end


local function build(L, env)
   local modules = not isempty(L.luke.modules or {})
   local conf = mkenv(CONFIGENV, env)

   if modules and not isempty(L.luke.ldocs or {}) then
      conf = config_ldoc(L, conf)
      env = mkenv(env, {LDOC=conf.LDOC})
   end

   local c = c_modules(L.luke.modules or {})
   local cprograms = filter(L.scripts.build, function(entry)
      return c_program(script_rules(L, entry))
   end)
   if not isempty(c) or not isempty(cprograms) then
      conf = config_compiler(L, conf)
      env = mkenv(env, {CC=conf.CC})
   end
   -- TODO: this runs the probes in every bin and install.bin rule, even
   -- those not selected by the command line targets.
   L.luke = run_configs(L, conf, L.luke)
   -- Commands expand the variables that probes have now set, such as a
   -- program found with checkprog, while command line values still win.
   env = mkenv(L.clidefs, L.luke.variables, env)

   local substitute = mkenv(L.clidefs, L.luke.substitute, SHELLENV)
   local status = 0

   if modules then
      L.luke = run_templates(L, substitute, L.luke)

      status = firstof(c, isnonzero, function(name)
         return build_c_module(L, env, L.luke, name)
      end) or 0

      if status == 0 and not isempty(L.luke.ldocs or {}) then
         status = run_ldocs(L, env, L.luke.ldocs)
      end
   end

   if status == 0 then
      status = firstof(L.scripts.build, isnonzero, function(entry)
         return build_script(L, env, substitute, entry)
      end) or 0
   end

   return status
end


return {
   main = function(args)
      local L = validate_arguments(parse_arguments(args))
      local env = mkenv(L.clidefs, L.luke.variables, DEFAULTENV, SHELLENV)
      local status = 0

      if not isempty(L.valreqs) then
         -- Only the probes in `variables` can set a value to print.
         local probed = run_configs(L, mkenv(CONFIGENV, env), {variables = L.luke.variables})
         env = mkenv(L.clidefs, probed.variables, env)
         each(L.valreqs, function(name)
            print(interpolate(env, concat {name, "='$", name, "'"}))
         end)
         exit(0)
      end

      if L.release ~= nil then
         return release(L, env, function()
            return build(L, env)
         end)
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

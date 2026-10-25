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
   'luke.prepare',
   'luke.release',
}


local function run_ldocs(L, env, ldocs)
   return run(L, env, compact(flatten(list('$LDOC -c', ldocs.sources, '.'))))
end


-- The rules for script *entry*, as selected by `prepare`.
local function script_rules(L, entry)
   return ordered_get(script_sections(L.luke)[entry.section], entry.name)
end


-- Build the script, program or generated file for *entry*, making all
-- but generated files executable.
local function build_script(L, env, substitute, entry)
   local rules = script_rules(L, entry)
   local target = script_target(entry.name, rules, L.luke.variables.objdir, entry.section == 'install')

   return sequence{
      function()
         if isstring(rules) then
            fill_template(L, substitute, rules)
            return 0
         end
         local sources = map(rules.sources, function(source)
            return fill_template(L, substitute, source)
         end)
         return build_program(L, env, L.luke, rules, target, sources)
      end,
      function()
         return choose(entry.section == 'files', 0, bind(make_executable, {L, env, target}))
      end,
   }
end


-- Run the probes that building *L.luke* needs, and return the
-- environment for commands, the substitutions for templates, and the
-- names of the C modules, as they are before templates are filled.
local function configured(L, env)
   local conf = mkenv(CONFIGENV, env)

   if not isempty(L.luke.ldocs or {}) then
      conf = config_ldoc(L, conf)
      env = mkenv(env, {LDOC=conf.LDOC})
   end

   local c_names = c_modules(L.luke.modules or {})
   local c_programs = filter(L.scripts.build, function(entry)
      return c_program(script_rules(L, entry))
   end)
   if not isempty(c_names) or not isempty(c_programs) then
      conf = config_compiler(L, conf)
      env = mkenv(env, {CC=conf.CC})
   end
   -- TODO: this runs the probes in every bin and install.bin rule, even
   -- those not selected by the command line targets.
   L.luke = run_configs(L, conf, L.luke)
   -- Commands expand the variables that probes have now set, such as a
   -- program found with checkprog, while command line values still win.
   env = mkenv(L.clidefs, L.luke.variables, env)

   return env, mkenv(L.clidefs, L.luke.substitute, SHELLENV), c_names
end


-- Fill the templates of the modules, build the C modules *c_names*, and
-- run ldocs, if there are any.
local function build_modules(L, env, substitute, c_names)
   if isempty(L.luke.modules or {}) and isempty(L.luke.ldocs or {}) then
      return 0
   end
   L.luke = run_templates(L, substitute, L.luke)
   return sequence(compact(flatten(list(
      map(c_names, function(name)
         return bind(build_c_module, {L, env, L.luke, name})
      end),
      choose(not isempty(L.luke.ldocs or {}), function()
         return bind(run_ldocs, {L, env, L.luke.ldocs})
      end)
   ))))
end


-- Build each script, program and generated file selected.
local function build_scripts(L, env, substitute)
   return sequence(map(L.scripts.build, function(entry)
      return bind(build_script, {L, env, substitute, entry})
   end))
end


local function build(L, env)
   local env, substitute, c_names = configured(L, env)
   return sequence{
      bind(build_modules, {L, env, substitute, c_names}),
      bind(build_scripts, {L, env, substitute}),
   }
end


-- Build just the ldocs, as a release does after LuaRocks builds the rest.
local function build_ldocs(L, env)
   if isempty(L.luke.ldocs or {}) then
      return 0
   end
   local env, substitute = configured(L, env)
   L.luke = run_templates(L, substitute, L.luke)
   return run_ldocs(L, env, L.luke.ldocs)
end


-- Print the value of each variable that the command line asks for, and
-- exit.  Only the probes in `variables` can set a value to print.
local function print_values(L, env)
   local probed = run_configs(L, mkenv(CONFIGENV, env), {variables = L.luke.variables})
   env = mkenv(L.clidefs, probed.variables, env)
   each(L.valreqs, function(name)
      print(interpolate(env, format("%s='$%s'", name, name)))
   end)
   exit(0)
end


-- Make *recipe*, as *request* asks, and return the exit status.  Every
-- front end calls this, with the normalized table of what to build and
-- what was asked for it, as `mkrequest` makes.
local function make(recipe, request)
   local L = prepare(recipe, request)
   local env = mkenv(L.clidefs, L.luke.variables, DEFAULTENV, SHELLENV)

   if not isempty(L.valreqs) then
      print_values(L, env)
   end

   if L.release ~= nil then
      return release(L, env, bind(build, {L, env}), bind(build_ldocs, {L, env}))
   end

   return sequence{
      function()
         local wanted = not isempty(L.luke.modules or {}) or not isempty(L.scripts.build) or
                        not isempty(L.luke.ldocs or {})
         return choose(wanted, bind(build, {L, env}), 0)
      end,
      bind(install_modules, {L, env, L.luke, L.install}),
      bind(install_scripts, {L, env, L.luke, L.scripts.install}),
   }
end


return {
   -- Make the recipe that the lukefile on the command line *args* gives.
   main = function(args)
      return make(commandline(args))
   end,

   make = make,
}

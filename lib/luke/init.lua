local _ENV = require 'std.normalize' {
   'luke.cli',
   'luke.compile',
   'luke.configure',
   'luke.environment',
   'luke.lukefile',
   'std.functional',
}


local function run_ldocs(L, env, ldocs)
   return run_command(L, env, flatten{'$LDOC -c', ldocs.sources, '.'})
end


local function build_modules(L, env)
   local conf = makeenv(CONFIGENV, env)

   if not isempty(L.luke.ldocs or {}) then
      conf = config_ldoc(L, conf)
      env = makeenv(env, {LDOC=conf.LDOC})
   end

   local c = c_modules(L.luke.modules)
   if not isempty(c) then
      conf = config_compiler(L, conf)
      env = makeenv(env, {CC=conf.CC})
   end
   L.luke = run_configs(L, conf, L.luke)

   local substitute = makeenv(L.clidefs, L.luke.substitute, SHELLENV)
   L.luke = run_templates(L, substitute, L.luke)

   local status = dropuntil(c, isnonzero, function(name)
      return build_c_module(L, env, L.luke, name)
   end) or 0

   if status == 0 and not isempty(L.luke.ldocs or {}) then
      status = run_ldocs(L, env, L.luke.ldocs)
   end

   return status
end


return {
   main = function(args)
      local L = validate_arguments(parse_arguments(args))
      local env = makeenv(L.clidefs, L.luke.variables, DEFAULTENV, SHELLENV)
      local status = 0

      if status == 0 and not isempty(L.luke.modules or {}) then
         status = build_modules(L, env)
      end

      if status == 0 then
         status = install_modules(L, env, L.luke, L.install)
      end

      return status
   end,
}

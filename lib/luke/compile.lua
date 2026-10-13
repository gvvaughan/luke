--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke._base',
   'luke.environment',
   'luke.functional',
   'type.context-manager',
   'type.path',

   SHELLMETACHARS = '[%s%$"]',
}


local function spawn(env, ...)
   local command = interpolate(env, concat({...}, ' '))
   return with(TmpFile(), TmpFile(), function(out, err)
      -- Group the command, so that capturing its output redirects every
      -- part of a compound command, not just the last.
      local pipe = concat{'{ ', command, '\n} >', out.filename, ' 2>', err.filename, '; printf $?'}
      return tonumber(slurp(Pipe(pipe))), slurp(File(err.filename)), slurp(File(out.filename))
   end)
end


local function run(L, env, command)
   L.write(interpolate(env, concat(command, ' ')), '\n')
   local status, err, out = spawn(env, unpack(command))
   if status ~= 0 then
      if L.write == nop then
         stdout:write(concat(command, ' ') .. '\n')
      end
      stderr:write(err .. '\n')
   end
   return status, out, err
end


local function defines(...)
   return zip_with(merge({}, unpack(except(list(...), nil))), function(name, value)
      local fmt = cond(
         {[int(value) == 1] = '-D%s'},
         {[match(value, SHELLMETACHARS) ~= nil] = "-D%s='%s'"},
         {[true] = '-D%s=%s'}
      )
      return format(fmt, name, value)
   end)
end


local function incdirs(...)
   return map(flatten(...), function(v)
      return '-I' .. v
   end)
end


local function libdirs(...)
   return map(flatten(...), function(v)
      return '-L' .. v
   end)
end


local function c_module_path(objdir, name)
   return format('%s/%s.$LIB_EXTENSION', objdir, gsub(name, '%.', '/'))
end


local function c_source(module, objdir)
   local path = gsub(module, '%.', '/')
   local src = c_module_path(objdir, path)
   return src, (gsub('$INST_LIBDIR/' .. path, '/[^/]+$', ''))
end


local function lua_source(module, src)
   local abspath = '$INST_LUADIR/' .. gsub(module, '%.', '/')
   if match(src, '/init%.lua$') then
      abspath = abspath .. '/init'
   end
   abspath = abspath .. '.lua'
   return src, (gsub(abspath, '/[^/]+%.lua$', ''))
end


-- Where the script or program called *name* is built: a script beside
-- its source, without any '.in' suffix; an in-tree program at the path
-- *name*; and an installable program beneath *objdir*.
local function script_target(name, rules, objdir, installed)
   if isstring(rules) then
      return (gsub(rules, '%.in$', ''))
   elseif installed then
      return format('%s/%s', objdir, name)
   end
   return name
end


local function c_sources(sources)
   return dropuntil(sources, bind(match, {[2]='%.[ch]$'}))
end


local function module_to_path(module, sources, objdir)
   return dropuntil(sources, function(source)
      return case(source, {
         ['.*%.[ch]']       = bind(c_source,   {module, objdir}),
         ['(.*%.[ch])%.in'] = bind(c_source,   {module, objdir}),
         ['.*%.lua']        = bind(lua_source, {module}),
         ['(.*%.lua)%.in']  = bind(lua_source, {module}),

         function(src)
            fatal("unsupported source type '%s'", src)
         end,
      })
   end)
end


return {
   build_c_module = function(L, env, luke, name)
      local rules = luke.modules[name]
      local c_module = c_module_path(luke.variables.objdir, name)

      local command = {'$MAKEDIRS', dirname(c_module)}
      local status, err, out = spawn(env, unpack(command))
      if status ~= 0 then
         stdout:write(concat(command, ' ') .. '\n')
         stderr:write(err .. '\n')
         exit(status)
      end

      return run(L, env, flatten(
         '$CC $CFLAGS $LIBFLAG $PKGFLAGS $CPPFLAGS',
         defines(rules.defines, luke.defines),
         incdirs(rules.incdirs, luke.incdirs),
         rules.sources,
         '-o', c_module,
         '$LDFLAGS',
         libdirs(rules.libdirs, luke.libdirs),
         '$LIBS',
         rules.libraries, luke.libraries
      ))
   end,

   c_modules = function(modules)
      return filter(keys(modules), function(name)
         return dropuntil(modules[name].sources, bind(match, {[2]='%.[ch]$'}))
      end)
   end,

   defines = defines,
   incdirs = incdirs,

   install_modules = function(L, env, luke, modules)
      return reduce(keys(modules), 0, function(status, name)
         if status == 0 then
            local src, dir = module_to_path(name, modules[name].sources, luke.variables.objdir)
            if not exists(interpolate(env, dir)) then
               status = run(L, env, {'$MAKEDIRS', dir})
            end
            if status == 0 then
               status = run(L, env, {'$INSTALL', src, dir .. '/'})
            end
         end
         return status
      end)
   end,

   -- Build *target* from *sources* with the `command` from *rules*, or
   -- else by compiling and linking C sources.
   build_program = function(L, env, luke, rules, target, sources)
      if match(target, '/') then
         local command = {'$MAKEDIRS', dirname(target)}
         local status, err = spawn(env, unpack(command))
         if status ~= 0 then
            stdout:write(concat(command, ' ') .. '\n')
            stderr:write(err .. '\n')
            return status
         end
      end

      if rules.command ~= nil then
         local names = sorted(keys(rules.env))
         -- Export env for the whole command, and let `$NAME` in the
         -- command itself expand to the same value.
         -- TODO: values are interpolated inside single quotes, so one
         -- containing a single quote breaks the command.
         local exports = {}
         if not isempty(names) then
            exports = flatten('export', map(names, function(name)
               return format("%s='%s'", name, rules.env[name])
            end), ';')
         end
         env = makeenv({sources = concat(sources, ' '), target = target}, rules.env, env)
         return run(L, env, flatten(exports, rules.command))
      end

      if c_sources(sources) == nil then
         fatal("no command to build '%s' from %s", target, concat(sources, ' '))
      end
      return run(L, env, flatten(
         '$CC $CFLAGS $CPPFLAGS',
         defines(rules.defines, luke.defines),
         incdirs(rules.incdirs, luke.incdirs),
         sources,
         '-o', target,
         '$LDFLAGS',
         libdirs(rules.libdirs, luke.libdirs),
         '$LIBS',
         rules.libraries, luke.libraries
      ))
   end,

   -- Whether *rules* builds a program by compiling C sources.
   c_program = function(rules)
      return istable(rules) and rules.command == nil and c_sources(rules.sources) ~= nil
   end,

   -- Copy each installable script or program in *names*, built as for
   -- `script_target`, to its name beneath INST_BINDIR.
   install_scripts = function(L, env, luke, names)
      if isempty(names) then
         return 0
      end
      local status = 0
      if not exists(interpolate(env, '$INST_BINDIR')) then
         status = run(L, env, {'$MAKEDIRS', '$INST_BINDIR'})
      end
      return reduce(names, status, function(status, name)
         local rules = luke.install.bin[name]
         local src = script_target(name, rules, luke.variables.objdir, true)
         local dest = '$INST_BINDIR/' .. name
         if status == 0 then
            status = run(L, env, {'$INSTALL', src, dest})
         end
         if status == 0 then
            status = run(L, env, {'$CHMOD', '+x', dest})
         end
         return status
      end)
   end,

   libdirs = libdirs,

   make_executable = function(L, env, path)
      return run(L, env, {'$CHMOD', '+x', path})
   end,

   run_command = run,

   script_target = script_target,

   spawn = spawn,
}

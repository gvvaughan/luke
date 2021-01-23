--[[
 Use the source, Luke!
 Copyright (C) 2014-2021 Gary V. Vaughan
]]

local _ENV = require 'std.normalize' {
   'luke._base',
   'luke.environment',
   'std.functional',
   'type.context-manager',
   'type.path',

   SHELLMETACHARS = '[%s%$"]',
}


local function spawn(env, ...)
   local command = interpolate(env, concat({...}, ' '))
   return with(TmpFile(), TmpFile(), function(out, err)
      local pipe = concat{command, ' >', out.filename, ' 2>', err.filename, '; printf $?'}
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


local function defines(env, deftables)
   return zip_with(merge({}, unpack(deftables)), function(name, value)
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
         defines(env, except(list(rules.defines, luke.defines), nil)),
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

   libdirs = libdirs,

   run_command = run,

   spawn = spawn,
}

--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _base = require 'luke._base'
local _environment = require 'luke.environment'
local _functional = require 'luke.functional'
local _std = require 'std.functional.init'
local _context = require 'type.context-manager'
local _path = require 'type.path'

local _ENV = require 'std.normalize' {
   'io.stderr',
   'io.stdout',
   'string.gsub',
   'string.match',
   'table.concat',
   int = 'math.tointeger',
   fatal = _base.fatal,
   interpolate = _environment.interpolate,
   mkenv = _environment.mkenv,
   shellword = _environment.shellword,
   format = _functional.format,
   call = _functional.call,
   destructure = _functional.destructure,
   isnonzero = _functional.isnonzero,
   isstring = _functional.isstring,
   istable = _functional.istable,
   keys = _functional.keys,
   ordered_get = _functional.ordered_get,
   ordered_keys = _functional.ordered_keys,
   ordered_merge = _functional.ordered_merge,
   bind = _std.bind,
   case = _std.case,
   choose = _std.choose,
   compact = _std.compact,
   cond = _std.cond,
   filter = _std.filter,
   firstof = _std.firstof,
   flatten = _std.flatten,
   isempty = _std.isempty,
   map = _std.map,
   some = _std.some,
   sorted = _std.sorted,
   File = _context.File,
   Pipe = _context.Pipe,
   TmpFile = _context.TmpFile,
   slurp = _context.slurp,
   with = _context.with,
   dirname = _path.dirname,
   exists = _path.exists,
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


-- Write the error output *err* of a failed command as it is, ending with
-- a newline, and nothing at all if there was none.
local function write_error(err)
   if err ~= '' then
      stderr:write(err, match(err, '\n$') and '' or '\n')
   end
end


-- Write *command*, and run it with `L.spawn`, which only pretends to
-- with --dry-run; return its exit status, output and error output.
local function run(L, env, command)
   L.write(interpolate(env, concat(command, ' ')), '\n')
   local status, err, out = L.spawn(env, unpack(command))
   if status ~= 0 then
      if L.quiet then
         stdout:write(concat(command, ' ') .. '\n')
      end
      write_error(err)
   end
   return status, out, err
end


-- The compiler flag for each macro defined by the lists of definitions
-- *...*, skipping nils, in the order each macro is first defined, with
-- the value from its last definition, such as a module's redefinition
-- of a macro defined for every module.
local function defines(...)
   return map(ordered_merge(...), function(definition)
      local name, value = destructure(definition)
      local fmt = cond(
         {int(value) == 1, '-D%s'},
         {true, '-D%s=%s'}
      )
      return format(fmt, name, shellword(value))
   end)
end


-- A function that gives *flag* before each of its arguments, or the
-- items of any lists among them.
local function flagged(flag)
   return function(...)
      return map(compact(flatten(pack(...))), function(v)
         return flag .. v
      end)
   end
end


local incdirs = flagged '-I'
local libdirs = flagged '-L'


local function c_module_path(objdir, name)
   return format('%s/%s.$LIB_EXTENSION', objdir, gsub(name, '%.', '/'))
end


local function c_source(module, objdir)
   local path = gsub(module, '%.', '/')
   local src = c_module_path(objdir, path)
   return src, (gsub('$INST_LIBDIR/' .. path, '/[^/]+$', ''))
end


local function lua_source(module, src)
   local suffix = choose(match(src, '/init%.lua$'), '/init', '')
   local abspath = '$INST_LUADIR/' .. gsub(module, '%.', '/') .. suffix .. '.lua'
   return src, (gsub(abspath, '/[^/]+%.lua$', ''))
end


-- Where the script or program called *name* is built: a script beside
-- its source, without any '.in' suffix; an in-tree program at the path
-- *name*; and an installable program beneath *objdir*.
local function script_target(name, rules, objdir, installed)
   return cond(
      {isstring(rules), function()
         return (gsub(rules, '%.in$', ''))
      end},
      {installed, function()
         return format('%s/%s', objdir, name)
      end},
      {true, name}
   )
end


local function c_sources(sources)
   return some(sources, bind(match, {[2]='%.[ch]$'}))
end


local function module_to_path(module, sources, objdir)
   return case(sources[1], {
      {'.*%.[ch]',       bind(c_source,   {module, objdir})},
      {'(.*%.[ch])%.in', bind(c_source,   {module, objdir})},
      {'.*%.lua',        bind(lua_source, {module})},
      {'(.*%.lua)%.in',  bind(lua_source, {module})},

      default = function(src)
         fatal("unsupported source type '%s'", src)
      end,
   })
end


-- The status of the first of the functions in *steps* to fail, calling
-- them in order and no more than that, or else 0.
local function sequence(steps)
   return firstof(steps, isnonzero, call) or 0
end


-- Make the directory *dir* to build into, and report it if that fails.
local function make_dir(L, env, dir)
   local command = {'$MAKEDIRS', dir}
   local status, err = L.spawn(env, unpack(command))
   if status ~= 0 then
      stdout:write(concat(command, ' ') .. '\n')
      write_error(err)
   end
   return status
end


-- Make the directory *dir* to install into, unless it is there.
local function install_dir(L, env, dir)
   return choose(exists(interpolate(env, dir)), 0, function()
      return run(L, env, {'$MAKEDIRS', dir})
   end)
end


-- The command to compile and link *sources* into *output*, beginning
-- with *head*, with the defines, include and library directories, and
-- libraries that the rules of *luke* and *rules* give.
local function c_command(luke, rules, head, sources, output)
   return compact(flatten(pack(
      head,
      defines(luke.defines, rules.defines),
      incdirs(rules.incdirs, luke.incdirs),
      sources,
      '-o', output,
      '$LDFLAGS',
      libdirs(rules.libdirs, luke.libdirs),
      '$LIBS',
      rules.libraries, luke.libraries
   )))
end


-- The shell command to export each variable of `rules.env`, which
-- `$NAME` in the command itself expands to the same value as.  Each
-- value is expanded before it is quoted, so that a quote in a variable
-- it uses is quoted too.
local function exports_for(env, rules)
   local names = sorted(keys(rules.env or {}))
   return choose(isempty(names), {}, function()
      return compact(flatten(pack('export', map(names, function(name)
         return format('%s=%s', name, shellword(interpolate(env, rules.env[name])))
      end), ';')))
   end)
end


-- Install the module *name*, in the directory for it.
local function install_module(L, env, luke, modules, name)
   local src, dir = module_to_path(name, ordered_get(modules, name).sources, luke.variables.objdir)
   return sequence{
      bind(install_dir, {L, env, dir}),
      bind(run, {L, env, {'$INSTALL', src, dir .. '/'}}),
   }
end


-- Install the script or program *name* beneath INST_BINDIR, and make
-- it executable.
local function install_script(L, env, luke, name)
   local rules = ordered_get(luke.install.bin, name)
   local src = script_target(name, rules, luke.variables.objdir, true)
   local dest = '$INST_BINDIR/' .. name
   return sequence{
      bind(run, {L, env, {'$INSTALL', src, dest}}),
      bind(run, {L, env, {'$CHMOD', '+x', dest}}),
   }
end


return {
   build_c_module = function(L, env, luke, name)
      local rules = ordered_get(luke.modules, name)
      local c_module = c_module_path(luke.variables.objdir, name)

      return sequence{
         bind(make_dir, {L, env, dirname(c_module)}),
         bind(run, {L, env, c_command(
            luke,
            rules,
            '$CC $CFLAGS $LIBFLAG $PKGFLAGS $CPPFLAGS',
            rules.sources,
            c_module
         )}),
      }
   end,

   -- Build *target* from *sources* with the `command` from *rules*, or
   -- else by compiling and linking C sources.
   build_program = function(L, env, luke, rules, target, sources)
      local status = choose(match(target, '/'), function()
         return make_dir(L, env, dirname(target))
      end, 0)
      if status ~= 0 then
         return status
      end

      if rules.command ~= nil then
         -- Export env for the whole command, and let `$NAME` in the
         -- command itself expand to the same value.
         env = mkenv({sources = concat(sources, ' '), target = target}, rules.env, env)
         return run(L, env, compact(flatten(pack(exports_for(env, rules), rules.command))))
      end

      if not c_sources(sources) then
         fatal("no command to build '%s' from %s", target, concat(sources, ' '))
      end
      return run(L, env, c_command(luke, rules, '$CC $CFLAGS $CPPFLAGS', sources, target))
   end,

   c_modules = function(modules)
      return filter(ordered_keys(modules), function(name)
         return c_sources(ordered_get(modules, name).sources)
      end)
   end,

   -- Whether *rules* builds a program by compiling C sources.
   c_program = function(rules)
      return istable(rules) and rules.command == nil and c_sources(rules.sources)
   end,

   defines = defines,

   incdirs = incdirs,

   install_modules = function(L, env, luke, modules)
      return sequence(map(ordered_keys(modules), function(name)
         return bind(install_module, {L, env, luke, modules, name})
      end))
   end,

   -- Copy each installable script or program in *names*, built as for
   -- `script_target`, to its name beneath INST_BINDIR.
   install_scripts = function(L, env, luke, names)
      if isempty(names) then
         return 0
      end
      return sequence(compact(flatten(pack(
         bind(install_dir, {L, env, '$INST_BINDIR'}),
         map(names, function(name)
            return bind(install_script, {L, env, luke, name})
         end)
      ))))
   end,

   libdirs = libdirs,

   make_executable = function(L, env, path)
      return run(L, env, {'$CHMOD', '+x', path})
   end,

   run = run,

   sequence = sequence,

   script_target = script_target,

   spawn = spawn,
}

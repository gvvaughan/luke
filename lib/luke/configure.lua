--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _base = require 'luke._base'
local _compile = require 'luke.compile'
local _environment = require 'luke.environment'
local _std = require 'std.functional.init'
local _context = require 'type.context-manager'
local _dict = require 'type.dict'

local _ENV = require 'std.normalize' {
   'os.getenv',
   'string.find',
   'string.format',
   'string.gmatch',
   'string.gsub',
   'string.sub',
   'table.concat',
   diagnose = _base.diagnose,
   fatal = _base.fatal,
   defines = _compile.defines,
   incdirs = _compile.incdirs,
   libdirs = _compile.libdirs,
   spawn = _compile.spawn,
   CONFIGENV = _environment.CONFIGENV,
   interpolate = _environment.interpolate,
   mkenv = _environment.mkenv,
   apply = _std.apply,
   bind = _std.bind,
   call = _std.call,
   case = _std.case,
   choose = _std.choose,
   compact = _std.compact,
   cond = _std.cond,
   each = _std.each,
   firstof = _std.firstof,
   flatten = _std.flatten,
   isempty = _std.isempty,
   isfile = _std.isfile,
   istable = _std.istable,
   keys = _std.keys,
   map = _std.map,
   merged = _std.merged,
   some = _std.some,
   CTest = _context.CTest,
   File = _context.File,
   TmpFile = _context.TmpFile,
   slurp = _context.slurp,
   with = _context.with,
   OrderedDict = _dict.OrderedDict,
   CCPROGS = {'cc', 'gcc', 'clang'},
}


local function logspawn(L, env, filename, ...)
   local status, err = spawn(env, ...)
   if status ~= 0 and err ~= '' then
      with(File(filename, 'r'), function(h)
         L.log(h.filename .. ':')
         L.log(slurp(h))
      end)
      L.log(err)
   end
   return status
end


-- With --debug, keep each probe's files and log where they are.
local function Conftest(L)
   local cm = CTest(L.debug)
   if L.debug and cm ~= nil then
      L.log('keeping ' .. cm.filename .. ' and ' .. cm.objfile)
   end
   return cm
end


local function checking(L, ...)
   L.verbose('checking ', concat({...}, ' '), '... ')
end


local function found_library(L, x)
   L.verbose(cond({x == nil or x == '', 'none required'}, {isempty(x), 'not supported'}, {true, x}))
   L.verbose '\n'
   return x
end


local function found_prog(L, x)
   L.verbose(choose(x, 'yes\n', 'no\n'))
   return x
end


local function found_result(L, x)
   L.verbose(choose(x == 0, 'yes\n', 'no\n'))
   -- non-zero exit status 'x' is a failure, so define value in 0, otherwise 1
   return choose(x ~= 0, 0, 1)
end


-- *template* with each '@NAME@' replaced by its value in *values*, in one
-- pass, so that nothing a value says is replaced again.
local function fill(template, values)
   return (gsub(template, '@(%u+)@', values))
end


local function bindirs(...)
   return map(compact(flatten(pack(...))), function(v)
      return v .. ':'
   end)
end


-- TODO: a probe compiles with the top-level `defines` as written, so it
-- cannot see the results of earlier probes, and a probe among them is
-- passed to `defines` unresolved.
local function compile_command(L, env, config, objfile, filename)
   local command = compact(flatten(pack(
      '$CC', '-c', '$CFLAGS',
      defines(L.luke.defines),
      incdirs(config.incdir),
      '$CPPFLAGS',
      '-o', objfile,
      filename
   )))
   L.log(interpolate(env, concat(command, ' ')))
   return unpack(command)
end


local function link_command(L, env, config, a_out, source, lib)
   local command = compact(flatten(pack(
      '$CC', '$CFLAGS',
      defines(L.luke.defines),
      incdirs(config.incdir),
      '$CPPFLAGS',
      '-o',  a_out,
      source,
      libdirs(config.libdir),
      '$LDFLAGS',
      lib,
      '$libs', CONFIGENV.libs
   )))
   L.log(interpolate(env, concat(command, ' ')))
   return unpack(command)
end


local function check_executable_in_path(L, env, config, prog)
   local PATH = concat(bindirs(config.bindir)) .. getenv('PATH')
   local found = firstof(gmatch(PATH, '[^:]+'), function(path)
      local progpath = path .. '/' .. prog
      return with(File(progpath, 'r'), function(h)
         return choose(h and isfile(h.context), progpath)
      end)
   end)
   L.log(choose(found, function()
      return 'found ' .. found
   end, prog .. ' not found'))
   return found ~= nil
end


-- The status of compiling the C program *source*, for a probe.
local function compile_probe(L, env, config, source)
   return with(Conftest(L), function(conftest)
      conftest:write(source)
      conftest:flush()
      return logspawn(
         L,
         env,
         conftest.filename,
         compile_command(L, env, config, conftest.objfile, conftest.filename)
      )
   end)
end


-- The status of compiling and linking the C program *source*, with *lib*
-- if there is one, for a probe.
local function link_probe(L, env, config, source, lib)
   return with(Conftest(L), TmpFile(), function(conftest, a_out)
      conftest:write(source)
      conftest:flush()
      return logspawn(
         L,
         env,
         conftest.filename,
         link_command(L, env, config, a_out.filename, conftest.filename, lib)
      )
   end)
end


local function check_header_compile(L, env, config, header, extra_hdrs)
   return compile_probe(L, env, config, format('%s\n#include "%s"\n', extra_hdrs, header))
end


local function check_struct_member_compile(L, env, config, structname, member, extra_hdrs)
   return compile_probe(L, env, config, fill([[
@HEADERS@
int main () {
static @STRUCT@ aggr;
if (sizeof aggr.@MEMBER@)
    return 0;
return 0;
}
]], {HEADERS = extra_hdrs, STRUCT = structname, MEMBER = member}))
end


local function try_link(L, env, config, lib, symbol)
   return link_probe(L, env, config, fill([[
/* Override any GCC internal prototype to avoid an error.
 Use char because int might match the return type of a GCC
 builtin and then its argument prototype would still apply.   */
char @SYMBOL@ ();
int main () {
return @SYMBOL@ ();
}
]], {SYMBOL = symbol}), lib)
end


local function try_compile(L, env, config, headers)
   return link_probe(L, env, config, fill([[
@HEADERS@
#if !defined @IFDEF@ || @IFDEF@ == -1
choke me
#endif
int
main()
{
return 0;
}
]], {HEADERS = headers, IFDEF = config.ifdef}))
end


local function check_func_decl(L, env, config, fname, extra_hdrs)
   return compile_probe(L, env, config, fill([[
@HEADERS@
int
main()
{
#ifndef @FUNC@
(void) @FUNC@;
#endif
return 0;
}
]], {HEADERS = extra_hdrs, FUNC = fname}))
end


local function check_func_link(L, env, config, fname)
   return link_probe(L, env, config, fill([[
/* Define to an innocous variant, in case <limits.h> declares it.
 For example, HP-UX 11i <limits.h> declares gettimeofday.   */
#define @FUNC@ innocuous_@FUNC@

/* System header to define __stub macros and hopefully few prototypes,
 which can conflict with declaration below.
 Prefer <limits.h> to <assert.h> if __STDC__ is defined, since
 <limits.h> exists even on freestanding compilers.   */

#ifdef __STDC__
# include <limits.h>
#else
# include <assert.h>
#endif

#undef @FUNC@

/* Override any GCC internal prototype to avoid an error.
 Use char because int might match the return type of a GCC
 builtin and then its argument prototype would still apply.   */
char @FUNC@ ();

/* The GNU C library defines this for functions which it implements
 to always fail with ENOSYS.   Some functions are actually named
 something starting with __ and the normal name is an alias.   */
#if defined __stub_@FUNC@ || defined __stub__@FUNC@
choke me
#endif

int main () {
return @FUNC@ ();
}
]], {FUNC = fname}))
end


-- The kinds of directory that an external dependency can set, with the
-- variable for each, named for the dependency.
local DIRVARS = {bindir = '$%s_BINDIR', incdir = '$%s_INCDIR', libdir = '$%s_LIBDIR'}


-- The directories that the external dependency *prefix* sets in *env*.
local function external_dirs(env, prefix)
   local r = {}
   if prefix ~= nil then
      each(keys(DIRVARS), function(k)
         local envvar = interpolate(env, format(DIRVARS[k], prefix))
         if envvar ~= '' then
            r[k] = envvar
         end
      end)
   end
   return r
end


local function format_includes(includes)
   return map(includes or {}, function(include)
      return format('#include "%s"', include)
   end)
end


-- The includes that a probe puts in its source, one to a line.
local function include_lines(config)
   return concat(format_includes(config.includes), '\n')
end


-- Link with *lib* from now on, ahead of the libraries that were found.
local function add_library(lib)
   CONFIGENV.libs = choose(CONFIGENV.libs == '', lib, lib .. ' ' .. CONFIGENV.libs)
end


local configure = setmetatable(OrderedDict({
   checkprog = function(L, env, config)
      return diagnose(firstof(config.progs, function(prog)
         checking(L, 'for', prog)
         if found_prog(L, check_executable_in_path(L, env, config, prog)) then
            return prog
         end
      end), 'cannot find %s', config.checkprog)
   end
}, {
   checkheader = function(L, env, config)
      checking(L, 'for', config.checkheader)
      return found_result(
         L,
         check_header_compile(L, env, config, config.checkheader, include_lines(config))
      )
   end
}, {
   checkdecl = function(L, env, config)
      checking(L, 'whether', config.checkdecl, 'is declared')
      return found_result(
         L,
         check_func_decl(L, env, config, config.checkdecl, include_lines(config))
      )
   end
}, {
   checksymbol = function(L, env, config)
      checking(L, 'for library containing', config.checksymbol)

      -- Is the feature behind a preprocessor guard?
      if config.ifdef ~= nil then
         if try_compile(L, env, config, include_lines(config)) ~= 0 then
            return found_library(L, {})
         end
      end

      -- Look for required symbol in libc, and then each of `libraries`.
      local libraries, symbol = config.libraries, config.checksymbol
      local trylibs = flatten(pack('', map(libraries, function(lib)
         return '-l' .. lib
      end)))
      return firstof(trylibs, function(lib)
         if try_link(L, env, config, lib, symbol) == 0 then
            choose(lib ~= '', bind(add_library, {lib}))
            return found_library(L, lib)
         end
      end) or call(function()
         L.verbose '\n'
         fatal("required symbol '%s' not found in any of libc, lib%s",
            symbol, concat(libraries, ', lib'))
      end)
   end
}, {
   checkfunc = function(L, env, config)
      checking(L, 'for', config.checkfunc)
      return found_result(L, check_func_link(L, env, config, config.checkfunc))
   end
}, {
   checkmember = function(L, env, config)
      checking(L, 'for', config.checkmember)

      local i = find(config.checkmember, '%.')
      local structname = sub(config.checkmember, 1, i - 1)
      local member = sub(config.checkmember, i + 1)
      return found_result(
         L,
         check_struct_member_compile(L, env, config, structname, member, include_lines(config))
      )
   end
}), {
   __call = function(self, L, env, config, prefix)
      return case(type(config), {
         ['number'] = function()
            return str(config)
         end,

         ['string'] = function()
            return config
         end,

         ['table'] = function()
            return diagnose(firstof(self, function(fname)
               if config[fname] ~= nil then
                  return apply(self[fname], pack(L, env, merged(config, external_dirs(env, prefix))))
               end
            end), "unable to configure with keys '%s'", concat(keys(config), "', '"))
         end,

         default = function(kind)
            fatal("unsupported configure type '%s'", kind)
         end,
      })
   end,
})


-- Whether *x* is a probe, which luke runs at build time for a value.
local function isprobe(x)
   return istable(x) and some(configure, function(name)
      return x[name] ~= nil
   end)
end


return {
   config_compiler = function(L, env)
      local CC = env.CC
      if CC == nil then
         CC = configure(L, env, {checkprog='C compiler', progs=CCPROGS})
         env = mkenv(env, {CC=CC})
      end

      checking(L, interpolate(env, 'whether $CC works'))
      local cm = Conftest(L)
      local works, err = with(cm, function(conftest)
         conftest:write('typedef int x;\n')
         conftest:flush()
         return spawn(env, '$compile', '-o', conftest.objfile, conftest.filename)
      end)
      if works ~= 0 then
         L.verbose 'no\n'
         L.log(interpolate(env, '$compile -o ' .. cm.objfile .. ' ' .. cm.filename))
         if err and err ~= '' then
            L.log(err)
         end
         fatal('could not find a working C compiler')
      end
      found_prog(L, CC)
      return env
   end,

   config_ldoc = function(L, env)
      local LDOC = env.LDOC
      if LDOC == nil then
         LDOC = configure(L, env, {checkprog='LDocs generator', progs={'ldoc', 'true'}})
         env = mkenv(env, {LDOC=LDOC})
      end
      return env
   end,

   configure = configure,
   isprobe = isprobe,
}

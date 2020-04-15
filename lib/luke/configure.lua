--[[
 Use the source, Luke!
 Copyright (C) 2014-2020 Gary V. Vaughan
]]

local _ENV = require 'std.normalize' {
   'luke._base',
   'luke.compile',
   'luke.environment',
   'std.functional',
   'type.context-manager',
   'type.dict',

   CCPROGS = {'cc', 'gcc', 'clang'},
}


local function logspawn(L, env, ...)
   local status, err = spawn(env, ...)
   if status ~= 0 and err ~= '' then
      L.log(err)
   end
   return status
end


local function checking(L, ...)
   L.verbose('checking ', concat({...}, ' '), '... ')
end


local function found_library(L, x)
   if x == nil or x == '' then
      L.verbose 'none required'
   elseif isempty(x) then
      L.verbose 'not supported'
   else
      L.verbose(x)
   end
   L.verbose '\n'
   return x
end


local function found_prog(L, x)
   L.verbose(x and 'yes\n' or 'no\n')
   return x
end


local function found_result(L, x)
   L.verbose(x == 0 and 'yes\n' or 'no\n')
   -- non-zero exit status 'x' is a failure, so define value in 0, otherwise 1
   return x ~= 0 and 0 or 1
end


local function bindirs(...)
   return map(flatten(...), function(v)
      return v .. ':'
   end)
end


local function compile_command(L, env, config, filename)
   local command = flatten(
      '$CC', '-c', '$CFLAGS',
      incdirs(config.incdir),
      '$CPPFLAGS',
      filename
   )
   --L.log(slurp(filename))
   L.log(interpolate(env, concat(command, ' ')))
   return unpack(command)
end


local function link_command(L, env, config, a_out, source, lib)
   local command = flatten(
      '$CC', '$CFLAGS',
      incdirs(config.incdir),
      '$CPPFLAGS',
      '-o',  a_out,
      source,
      libdirs(config.libdir),
      '$LDFLAGS',
      lib,
      '$libs', CONFIGENV.libs
   )
   --L.log(slurp(source))
   L.log(interpolate(env, concat(command, ' ')))
   return unpack(command)
end


local function check_executable_in_path(L, env, config, prog)
   local PATH = concat(bindirs(config.bindir)) .. getenv('PATH')
   local found = dropuntil(gmatch(PATH, '[^:]+'), function(path)
      local progpath = path .. '/' .. prog
      return with(File(progpath, 'r'), function(h)
         return h and isfile(h.context) and progpath or nil
      end)
   end)
   L.log(found and 'found ' .. found or prog .. ' not found')
   return found ~= nil
end


local function check_header_compile(L, env, config, header, extra_hdrs)
   return with(CTest(), function(conftest)
      conftest:write(format('%s\n#include "%s"\n', extra_hdrs, header))
      return logspawn(
         L,
         env,
         compile_command(L, env, config, conftest.filename)
      )
   end)
end


local function try_link(L, env, config, lib, symbol)
   return with(CTest(), TmpFile(), function(conftest, a_out)
      conftest:write(format([[
/* Override any GCC internal prototype to avoid an error.
 Use char because int might match the return type of a GCC
 builtin and then its argument prototype would still apply.   */
char %s ();
int main () {
return %s ();
}
]], symbol, symbol))
      return logspawn(
         L,
         env,
         link_command(L, env, config, a_out.filename, conftest.filename, lib)
      )
   end)
end


local function try_compile(L, env, config, headers)
   return with(CTest(), TmpFile(), function(conftest, a_out)
      conftest:write(format([[
%s
#if !defined %s || %s == -1
choke me
#endif
int
main()
{
return 0;
}
]], headers, config.ifdef, config.ifdef))
      return logspawn(
         L,
         env,
         link_command(L, env, config, a_out.filename, conftest.filename)
      )
   end)
end


local function check_func_decl(L, env, config, fname, extra_hdrs)
   return with(CTest(), function(conftest)
      conftest:write(format([[
%s
int
main()
{
#ifndef %s
(void) %s;
#endif
return 0;
}
]], extra_hdrs, fname, fname))
      return logspawn(
         L,
         env,
         compile_command(L, env, config, conftest.filename)
      )
   end)
end


local function check_func_link(L, env, config, fname)
   return with(CTest(), TmpFile(), function(conftest, a_out)
      conftest:write(format([[
/* Define to an innocous variant, in case <limits.h> declares it.
 For example, HP-UX 11i <limits,h> declares gettimeofday.   */
#define %s innocuous_%s

/* System header to define __stub macros and hopefully few prototypes,
 which can conflict with declaration below.
 Prefer <limits.h> to <assert.h> if __STDC__ is defined, since
 <limits.h> exists even on freestanding compilers.   */

#ifdef __STDC__
# include <limits.h>
#else
# include <assert.h>
#endif

#undef %s

/* Override any GCC internal prototype to avoid an error.
 Use char because int might match the return type of a GCC
 builtin and then its argument prototype would still apply.   */
char %s ();

/* The GNU C library defines this for functions which it implements
 to always fail with ENOSYS.   Some functions are actually named
 something starting with __ and the normal name is an alias.   */
#if defined __stub_%s || defined __stub__%s
choke me
#endif

int main () {
return %s ();
}
]], fname, fname, fname, fname, fname, fname, fname))
      return logspawn(
         L,
         env,
         link_command(L, env, config, a_out.filename, conftest.filename)
      )
   end)
end


local function add_external_deps(env, config, prefix)
   if prefix ~= nil then
      for k, v in next, {bindir='$%s_BINDIR', incdir='$%s_INCDIR', libdir='$%s_LIBDIR'} do
         local envvar = interpolate(env, format(v, prefix))
         if envvar ~= '' then
            config[k] = envvar
         end
      end
   end
end


local function format_includes(includes)
   return map(includes or {}, function(include)
      return format('#include "%s"', include)
   end)
end


local configure = setmetatable(OrderedDict({
   checkprog = function(L, env, config)
      return dropuntil(config.progs, function(prog)
         checking(L, 'for', prog)
         if found_prog(L, check_executable_in_path(L, env, config, prog)) then
            return prog
         end
      end) or fatal('cannot find ' .. config.checkprog)
   end
}, {
   checkheader = function(L, env, config)
      checking(L, 'for', config.checkheader)

      local extra_hdrs = concat(format_includes(config.includes), '\n')
      return found_result(
         L,
         check_header_compile(L, env, config, config.checkheader, extra_hdrs)
      )
   end
}, {
   checkdecl = function(L, env, config)
      checking(L, 'whether', config.checkdecl, 'is declared')

      local extra_hdrs = concat(format_includes(config.includes), '\n')
      return found_result(
         L,
         check_func_decl(L, env, config, config.checkdecl, extra_hdrs)
      )
   end
}, {
   checksymbol = function(L, env, config)
      checking(L, 'for library containing', config.checksymbol)

      -- Is the feature behind a preprocessor guard?
      if config.ifdef ~= nil then
         local headers = concat(format_includes(config.includes), '\n')
         if try_compile(L, env, config, headers) ~= 0 then
            return found_library(L, {})
         end
      end

      -- Look for required symbol in libc, and then each of `libraries`.
      local libraries, symbol = config.libraries, config.checksymbol
      local trylibs = reduce(libraries, {''}, function(r, lib)
         append(r, '-l' .. lib)
      end)
      return dropuntil(trylibs, function(lib)
         if try_link(L, env, config, lib, symbol) == 0 then
            if lib ~= '' then
               if CONFIGENV.libs ~= '' then
                  CONFIGENV.libs = ' ' .. CONFIGENV.libs   -- FIXME
               end
               CONFIGENV.libs = lib .. CONFIGENV.libs
            end
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
            return dropuntil(self, function(fname)
               if config[fname] ~= nil then
                  add_external_deps(env, config, prefix)
                  return apply(self[fname], list(L, env, config))
               end
            end) or fatal("unable to configure with keys '%s'",
               concat(keys(config), "', '"))
         end,

         function(type)
            fatal("unsupported configure type '%s'", type)
         end,
      })
   end,
})


return {
   config_compiler = function(L, env)
      local CC = env.CC
      if CC == nil then
         CC = configure(L, env, {checkprog='C compiler', progs=CCPROGS})
         env = makeenv(env, {CC=CC})
      end

      checking(L, interpolate(env, 'whether $CC works'))
      local cm = CTest()
      local works, err = with(cm, function(conftest)
         conftest:write('typedef int x;\n')
         return spawn(env, '$compile', conftest.filename)
      end)
      if works ~= 0 then
         L.verbose 'no\n'
         L.log(interpolate(env, '$compile ' .. cm.filename))
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
         env = makeenv(env, {LDOC=LDOC})
      end
      return env
   end,

   configure = configure,
}

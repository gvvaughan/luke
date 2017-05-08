local _ENV = require 'std.normalize' {
   'luke._base',
   'luke.lukefile',
   'luke.platforms',
   'std.functional',
}


local function version()
   print [[
luke (Luke) 0.1
Written by Gary V. Vaughan <gary@gnu.org>, 2014

Copyright (C) 2017, Gary V. Vaughan
Luke comes with ABSOLUTELY NO WARRANTY.
You may redistribute copies of Luke under the terms of the MIT license;
it may be used for any purpose at absolutely no cost, without permission.
See <https://mit-license.org> for details.
]]
   exit(0)
end


local function help()
   print [[
Usage: luke [OPTION]... [VAR=VALUE]... [TARGET]

Use the source, Luke!

  --help        print this help, then exit
  --version     print version number, then exit
  --file=FILE   use FILE instead of lukefile
  --quiet       without any output
  --verbose     provide more progress output

Each TARGET can be one of the module table keys from lukefile, or:

  all           build all targets in lukefile
  install       copy all built targets to $PREFIX

If no TARGET is given, 'all' is implied.

Report bugs to https://github.com/gvvaughan/luke/issues.]]
   exit(0)
end


local function opterr(msg)
   if match(msg, '%.$') == nil then
      msg = msg .. '.'
   end
   stderr:write('luke: error: ' .. msg .. '\n')
   stderr:write("luke: try '" .. arg[0] .. " --help' for help.\n")
   exit(2)
end


local function display(...)
   return stdout:write(concat{...})
end


local function dump(...)
   return stderr:write('   DEBUG: "' .. concat(map(list(...), str)) .. '"\n')
end


local function interpolate_to_substitute(s)
   return (gsub(s, '%$([%w_]+)', '@%1@'))
end


return {
   parse_arguments = function(args)
      local clidefs, fname, targets, install = {}, 'lukefile', {}, {}
      local verbose, write, debug = nop, display, nop

      map(args, function(opt)
         case(opt, {
            ['--debug'] = function()
               debug = dump
            end,
               
            ['--file=(.+)'] = function(optarg)
               fname = optarg
            end,

            ['--quiet'] = function()
               write = nop
            end,

            ['--verbose'] = function()
               verbose = display
            end,

            ['--help'] = help,

            ['--version'] = version,

            ['([^=]+)=(.+)'] = function(name, value)
               clidefs[name] = value
            end,

            function(opt)
               if match(opt, '^-') ~= nil then
                  opterr(format("unrecognized option '%s'", opt))
               end
               append(targets, opt)
            end,
         })
      end)


      local luke, err = loadluke(fname)
      if luke == nil then
         fatal('bad ' .. fname .. ': ' .. err)
      end

      if isempty(luke.modules or {}) then
         fatal("no modules table in '%s', nothing to build", args.file)
      end

      targets = call(function()
         if isempty(targets) or contains(targets, 'all') then
            return except(flatten(targets, keys(luke.modules)), 'all')
         end
         local r = filter(targets, function(target)
            if target ~= 'install' and luke.modules[target] == nil then
               fatal("no rule to make target '%s'", target)
            end
            return true
         end)
         assert(len(r) > 0, "no build targets specified")
         return r
      end)

      local build = pluck(targets, luke.modules)
      if contains(targets, 'install') then
         install = build or luke.modules
      end
      luke.modules = build

      if isempty(luke.modules) then
         luke.external_dependencies = nil
	 end

      luke.substitute = merge(luke.substitute or {}, {
         package = interpolate_to_substitute(luke.package),
         version = interpolate_to_substitute(luke.version),
      })

      luke.variables = merge(
         luke.variables or {},
         collect_variables(luke),
         {
            LUA_DIR    = '/usr',
            LUA_BINDIR = '$LUA_DIR/bin',
            LUA_INCDIR = '$LUA_DIR/include/lua$LUAVERSION',
            LUA_LIBDIR = '$LUA_DIR/lib',
            objdir     = platforms[1],
            package    = luke.package,
            version    = luke.version,
         }
      )

      return {
         clidefs = clidefs,
         install = install,
         debug = debug,
         luke = luke,
         verbose = verbose,
         write = write,
      }
   end,
}

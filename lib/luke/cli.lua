--[[
 Use the source, Luke!
 Copyright (C) 2014-2022 Gary V. Vaughan
]]

local _ENV = require 'std.normalize' {
   'luke._base',
   'luke.lukefile',
   'luke.platforms',
   'std.functional',
}


local function version()
   print [[
luke (Luke) 0.2.3
Written by Gary V. Vaughan <gary@gnu.org>, 2014

Copyright (C) 2022, Gary V. Vaughan
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
  --value=NAME  print the value of variable NAME
  --quiet       without any output
  --verbose     provide more progress output

Each TARGET can be one of the module table keys from lukefile, or:

  all           build all targets in lukefile
  install       copy all built targets to $PREFIX

If no TARGET is given, 'all' is implied.

Report bugs to https://github.com/gvvaughan/luke/issues.]]
   exit(0)
end


local function opterr(...)
   local msg = (...)
   if select('#', ...) > 1 then
      msg = format(...)
   end
   msg = gsub(msg, '%.$', '')
   stderr:write('luke: error: ' .. msg .. '.\n')
   stderr:write("luke: try '" .. arg[0] .. " --help' for help.\n")
   exit(2)
end


local function display(...)
   return stdout:write(concat{...})
end


local function dump(...)
   local s = concat(map(list(...), str))
   if len(s) > 0 then
      gsub(concat(map(list(...), str)), '\n*$', '\n'):gsub('(.-)\n', function(line)
         stderr:write('   DEBUG: ' .. line .. '\n')
      end)
   end
end


local function interpolate_to_substitute(s)
   return (gsub(s, '%$([%w_]+)', '@%1@'))
end


return {
   parse_arguments = function(args)
      local r = {
         clidefs = {},
         valreqs = {},
         fname   = 'lukefile',
         install = {},
         log     = nop,
         targets = {},
         verbose = nop,
         write   = display,
      }

      map(args, function(opt)
         case(opt, {
            ['--debug'] = function()
               r.log = dump
            end,

            ['%-%-file=(.+)'] = function(optarg)
               r.fname = optarg
            end,

            ['%-%-value=(.+)'] = function(optarg)
               r.valreqs[#r.valreqs + 1] = optarg
            end,

            ['--quiet'] = function()
               r.write = nop
            end,

            ['--verbose'] = function()
               r.verbose = display
            end,

            ['--help'] = help,

            ['--version'] = version,

            ['([^-][^=]-)=(.+)'] = function(name, value)
               r.clidefs[name] = value
            end,

            function(opt)
               if match(opt, '^-') ~= nil then
                  opterr("unrecognized option '%s'", opt)
               end
               append(r.targets, opt)
            end,
         })
      end)

      return r
   end,

   validate_arguments = function(parsed)
      local luke, err = loadluke(parsed.fname)
      diagnose(luke ~= nil, 'bad %s: %s', parsed.fname, err)

      if isempty(luke.modules or {}) then
         fatal("no modules table in '%s', nothing to build", parsed.fname)
      end

      local targets = call(function()
         if isempty(parsed.targets) or contains(parsed.targets, 'all') then
            return except(flatten(parsed.targets, keys(luke.modules)), 'all')
         end
         local r = filter(parsed.targets, function(target)
            if target ~= 'install' and luke.modules[target] == nil then
               fatal("no rule to make target '%s'", target)
            end
            return true
         end)
         assert(len(r) > 0, "no build targets specified")
         return r
      end)

      local install
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
         clidefs = parsed.clidefs,
         install = install,
         log     = parsed.log,
         luke    = luke,
         valreqs = parsed.valreqs,
         verbose = parsed.verbose,
         write   = parsed.write,
      }
   end,
}

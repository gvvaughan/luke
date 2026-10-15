--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke._base',
   'luke.compile',
   'luke.lukefile',
   'luke.platforms',
   'luke.functional',
   'luke.version',
   'type.context-manager',
}


local function version()
   print(versiontext)
   exit(0)
end


local function help()
   print [[
Usage: luke [OPTION]... [VAR=VALUE]... [TARGET]

Use the source, Luke!

  --help        print this help, then exit
  --version     print version number, then exit
  --dry-run     print the commands, without running them
  --file=FILE   use FILE instead of lukefile
  --value=NAME  print the value of variable NAME
  --quiet       without any output
  --verbose     provide more progress output

Each TARGET can be one of the module table keys from lukefile, or:

  all           build all targets in lukefile
  install       copy all built targets to $PREFIX
  release       cut a release of the version given by version=VERSION

If no TARGET is given, 'all' is implied.

Report bugs to https://github.com/gvvaughan/luke/issues.]]
   exit(0)
end


-- Lua 5.1 declares an implicit local `arg` in every vararg function,
-- shadowing the global, so look up the program name outside of one.
local progname = arg[0]


local function opterr(...)
   local msg = (...)
   if select('#', ...) > 1 then
      msg = format(...)
   end
   msg = gsub(msg, '%.$', '')
   stderr:write('luke: error: ' .. msg .. '.\n')
   stderr:write("luke: try '" .. progname .. " --help' for help.\n")
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


-- The abbreviated hash of the commit checked out in the current
-- directory, or '' outside a git working tree.
local function gitref()
   local out = slurp(Pipe('git rev-parse --short HEAD 2>/dev/null'))
   return match(out or '', '^(%x+)\n?$') or ''
end


-- The absolute path of the current directory, where luke finds the
-- sources named in lukefile.
local function abs_top_srcdir()
   return (gsub(slurp(Pipe('pwd')) or '', '\n$', ''))
end


return {
   parse_arguments = function(args)
      local r = {
         clidefs = {},
         debug   = false,
         dryrun  = false,
         valreqs = {},
         fname   = 'lukefile',
         install = {},
         log     = nop,
         spawn   = spawn,
         targets = {},
         verbose = nop,
         write   = display,
      }

      map(args, function(opt)
         case(opt, {
            -- Undocumented: for debugging luke itself, not lukefiles.
            ['--debug'] = function()
               r.debug = true
               r.log = dump
            end,

            ['--dry-run'] = function()
               r.dryrun = true
               r.spawn = function()
                  return 0, '', ''
               end
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
      map({'package', 'version'}, function(key)
         diagnose(luke[key] ~= nil, "no %s in '%s'", key, parsed.fname)
      end)

      -- `release` builds everything, for the version given on the command
      -- line.
      local release
      if contains(parsed.targets, 'release') then
         if len(parsed.targets) > 1 then
            fatal('release cannot be combined with other targets')
         end
         release = parsed.clidefs.version
         diagnose(release ~= nil, 'release needs a version=VERSION argument')
         case(release, {
            ['%d+%.%d+']      = nop,
            ['%d+%.%d+%.%d+'] = nop,

            function()
               fatal("bad release version '%s': X.Y or X.Y.Z expected", release)
            end,
         })
         parsed.targets = {}
      end

      local sections = script_sections(luke)
      local installbin = sections.install
      local rulesets = {luke.modules, sections.bin, sections.files, installbin}

      local function hasrule(target)
         return target == 'install' or any(map(rulesets, function(rules)
            return ordered_get(rules, target) ~= nil
         end))
      end

      local targets = call(function()
         if isempty(parsed.targets) or contains(parsed.targets, 'all') then
            return except(flatten(parsed.targets, map(rulesets, ordered_keys)), 'all')
         end
         local unknown = except(parsed.targets, hasrule)
         diagnose(isempty(unknown), "no rule to make target '%s'", unknown[1])
         assert(len(parsed.targets) > 0, "no build targets specified")
         return parsed.targets
      end)

      -- Each target names every module, script and file called that,
      -- and `install` alone installs every module and installable
      -- script.
      local named = except(targets, 'install')
      local build = ordered_pluck(named, luke.modules)
      local scripts = {
         build = reduce(SCRIPT_SECTIONS, list(), function(entries, section)
            return reduce(ordered_keys(ordered_pluck(named, sections[section])), entries, function(entries, name)
               return append(entries, {name = name, section = section})
            end)
         end),
         install = {},
      }
      local install
      if contains(targets, 'install') then
         if isempty(named) then
            install, scripts.install = luke.modules, ordered_keys(installbin)
         else
            install, scripts.install = build, ordered_keys(ordered_pluck(named, installbin))
         end
      end
      luke.modules = build

      local ref, srcdir = gitref(), abs_top_srcdir()

      luke.substitute = merge(luke.substitute or {}, {
         abs_top_srcdir = srcdir,
         gitref         = ref,
         package        = interpolate_to_substitute(luke.package),
         version        = interpolate_to_substitute(luke.version),
      })

      luke.variables = merge(
         luke.variables or {},
         collect_variables(luke),
         {
            LUA_DIR        = '/usr',
            LUA_BINDIR     = '$LUA_DIR/bin',
            LUA_INCDIR     = '$LUA_DIR/include/lua$LUAVERSION',
            LUA_LIBDIR     = '$LUA_DIR/lib',
            abs_top_srcdir = srcdir,
            gitref         = ref,
            objdir         = platforms[1],
            package        = luke.package,
            version        = luke.version,
         }
      )

      return {
         clidefs = parsed.clidefs,
         debug   = parsed.debug,
         dryrun  = parsed.dryrun,
         install = install,
         log     = parsed.log,
         luke    = luke,
         release = release,
         scripts = scripts,
         spawn   = parsed.spawn,
         valreqs = parsed.valreqs,
         verbose = parsed.verbose,
         write   = parsed.write,
      }
   end,
}

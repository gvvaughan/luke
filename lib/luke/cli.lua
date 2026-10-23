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
   local msg = gsub(message(...), '%.$', '')
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
      -- Not gsub '\n*$', which matches again at the end in Lua 5.1.
      each(gmatch(match(s, '^(.-)\n*$') .. '\n', '(.-)\n'), function(line)
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


-- Load the lukefile that *parsed* names, and diagnose what it lacks.
local function check_lukefile(parsed)
   local luke, err = loadluke(parsed.fname)
   diagnose(luke ~= nil, 'bad %s: %s', parsed.fname, err)
   diagnose(not isempty(luke.modules or {}), "no modules table in '%s', nothing to build", parsed.fname)
   each({'package', 'version'}, function(key)
      diagnose(luke[key] ~= nil, "no %s in '%s'", key, parsed.fname)
   end)
   return luke
end


-- The version to release if the `release` target is given, which
-- builds everything, for the version given on the command line.
local function release_version(parsed)
   if not contains(parsed.targets, 'release') then
      return nil
   end
   diagnose(len(parsed.targets) == 1, 'release cannot be combined with other targets')
   local release = parsed.clidefs.version
   diagnose(release ~= nil, 'release needs a version=VERSION argument')
   case(release, {
      {'%d+',           nop},
      {'%d+%.%d+',      nop},
      {'%d+%.%d+%.%d+', nop},

      default = function()
         fatal("bad release version '%s': X, X.Y or X.Y.Z expected", release)
      end,
   })
   return release
end


-- The *targets* to make, or all of those in *rulesets* if there are
-- none, or `all` is one.
local function selected_targets(targets, rulesets)
   if isempty(targets) or contains(targets, 'all') then
      return reject(flatten(targets, map(rulesets, ordered_keys)), 'all')
   end
   local unknown = reject(targets, function(target)
      return target == 'install' or some(rulesets, function(rules)
         return ordered_get(rules, target) ~= nil
      end)
   end)
   diagnose(isempty(unknown), "no rule to make target '%s'", unknown[1])
   return targets
end


-- An entry for each script or file in *sections* that one of the
-- *named* targets names.
local function script_entries(sections, named)
   return flatmap(SCRIPT_SECTIONS, function(section)
      return map(ordered_keys(ordered_pluck(sections[section], named)), function(name)
         return {name = name, section = section}
      end)
   end)
end


-- What to install, if `install` is one of *targets*: the modules, and
-- the names of the scripts.  Each target names every module, script and
-- file called that, and `install` alone installs every module and
-- installable script.
local function installs(luke, installbin, build, named, targets)
   if not contains(targets, 'install') then
      return nil, {}
   end
   local everything = isempty(named)
   return choose(everything, luke.modules, build),
      choose(everything, ordered_keys(installbin), ordered_keys(ordered_pluck(installbin, named)))
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
         quiet   = false,
         spawn   = spawn,
         targets = {},
         verbose = nop,
         write   = display,
      }

      each(args, function(opt)
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

            {'%-%-file=(.+)', function(optarg)
               r.fname = optarg
            end},

            {'%-%-value=(.+)', function(optarg)
               append(r.valreqs, optarg)
            end},

            ['--quiet'] = function()
               r.quiet = true
               r.write = nop
            end,

            ['--verbose'] = function()
               r.verbose = display
            end,

            ['--help'] = help,

            ['--version'] = version,

            {'([^-][^=]-)=(.+)', function(name, value)
               r.clidefs[name] = value
            end},

            default = function(opt)
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
      local luke = check_lukefile(parsed)
      local release = release_version(parsed)

      local sections = script_sections(luke)
      local installbin = sections.install
      local rulesets = {luke.modules, sections.bin, sections.files, installbin}
      local targets = selected_targets(choose(release, {}, parsed.targets), rulesets)

      local named = reject(targets, 'install')
      local build = ordered_pluck(luke.modules, named)
      local install, install_scripts = installs(luke, installbin, build, named, targets)
      local scripts = {build = script_entries(sections, named), install = install_scripts}
      luke.modules = build

      local ref, srcdir = gitref(), abs_top_srcdir()

      luke.substitute = merged({
         abs_top_srcdir = srcdir,
         gitref         = ref,
         package        = interpolate_to_substitute(luke.package),
         version        = interpolate_to_substitute(luke.version),
      }, luke.substitute)

      luke.variables = merged({
         LUA_DIR        = '/usr',
         LUA_BINDIR     = '$LUA_DIR/bin',
         LUA_INCDIR     = '$LUA_DIR/include/lua$LUAVERSION',
         LUA_LIBDIR     = '$LUA_DIR/lib',
         abs_top_srcdir = srcdir,
         gitref         = ref,
         objdir         = platforms[1],
         package        = luke.package,
         version        = luke.version,
      }, collect_variables(luke), luke.variables)

      return {
         clidefs = parsed.clidefs,
         debug   = parsed.debug,
         dryrun  = parsed.dryrun,
         filled  = {},
         install = install,
         log     = parsed.log,
         luke    = luke,
         quiet   = parsed.quiet,
         release = release,
         scripts = scripts,
         spawn   = parsed.spawn,
         valreqs = parsed.valreqs,
         verbose = parsed.verbose,
         write   = parsed.write,
      }
   end,
}

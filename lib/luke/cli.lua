--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke._base',
   'luke.compile',
   'luke.environment',
   'luke.lukefile',
   'luke.functional',
   'luke.prepare',
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
  release       cut a release of the rock=NAME at version=VERSION
                (rock=@package@ if not specified)

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


-- Load the lukefile that *parsed* names.
local function check_lukefile(parsed)
   local luke, err = loadluke(parsed.fname)
   diagnose(luke ~= nil, 'bad %s: %s', parsed.fname, err)
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


local function parse_arguments(args)
   local r = {
      clidefs = {},
      debug   = false,
      dryrun  = false,
      valreqs = {},
      fname   = 'lukefile',
      quiet   = false,
      targets = {},
      verbose = false,
   }

   each(args, function(opt)
      case(opt, {
         -- Undocumented: for debugging luke itself, not lukefiles.
         ['--debug'] = function()
            r.debug = true
         end,

         ['--dry-run'] = function()
            r.dryrun = true
         end,

         {'%-%-file=(.+)', function(optarg)
            r.fname = optarg
         end},

         {'%-%-value=(.+)', function(optarg)
            append(r.valreqs, optarg)
         end},

         ['--quiet'] = function()
            r.quiet = true
         end,

         ['--verbose'] = function()
            r.verbose = true
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

   return mkrequest(r)
end


return {
   -- The recipe to make and the request to make it, from the command
   -- line *args*: the lukefile that it names, and what else it asks for.
   commandline = function(args)
      local parsed = parse_arguments(args)
      return check_lukefile(parsed), merged(parsed, {release = release_version(parsed)})
   end,

   parse_arguments = parse_arguments,

   validate_arguments = function(parsed)
      local luke = check_lukefile(parsed)
      return prepare(luke, merged(parsed, {release = release_version(parsed)}))
   end,
}

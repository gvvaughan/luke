--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

--[[--
 What every front end gives luke to make: a *recipe*, the normalized
 table of what to build, as `luke.lukefile.normalize` returns it, and a
 *request*, what was asked for of it.  Front ends are the command line,
 which reads the recipe from a lukefile, and the LuaRocks build backend,
 which reads it from a rockspec.
]]

local _base = require 'luke._base'
local _compile = require 'luke.compile'
local _environment = require 'luke.environment'
local _functional = require 'luke.functional'
local _lukefile = require 'luke.lukefile'
local _platforms = require 'luke.platforms'
local _std = require 'std.functional.init'
local _context = require 'type.context-manager'

local _ENV = require 'std.normalize' {
   'io.stderr',
   'io.stdout',
   'string.gmatch',
   'string.gsub',
   'string.match',
   'table.concat',
   diagnose = _base.diagnose,
   spawn = _compile.spawn,
   DEFAULTENV = _environment.DEFAULTENV,
   ordered_get = _functional.ordered_get,
   ordered_keys = _functional.ordered_keys,
   ordered_pluck = _functional.ordered_pluck,
   SCRIPT_SECTIONS = _lukefile.SCRIPT_SECTIONS,
   collect_variables = _lukefile.collect_variables,
   script_sections = _lukefile.script_sections,
   platforms = _platforms.platforms,
   choose = _std.choose,
   contains = _std.contains,
   each = _std.each,
   flatmap = _std.flatmap,
   flatten = _std.flatten,
   isempty = _std.isempty,
   map = _std.map,
   merged = _std.merged,
   nop = _std.nop,
   reject = _std.reject,
   some = _std.some,
   Pipe = _context.Pipe,
   slurp = _context.slurp,
}


local function display(...)
   return stdout:write(concat{...})
end


local function dump(...)
   -- Strings as they are, not as std.normalize's str escapes them.
   local s = concat(map(pack(...), function(x)
      return type(x) == 'string' and x or str(x)
   end))
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


-- The *targets* to make, or all of those in *rulesets* if there are
-- none, or `all` is one.
local function selected_targets(targets, rulesets)
   if isempty(targets) or contains(targets, 'all') then
      return reject(flatten(pack(targets, map(rulesets, ordered_keys))), 'all')
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


-- A request, from *options*, which may have:
--
--  * `clidefs`, settings that win over those of the recipe and the
--    defaults of luke, as the `VAR=VALUE` arguments of the command line do;
--  * `targets`, what to make: names of modules, scripts and files, or `all`
--    or `install` or `release`;
--  * `debug`, `dryrun`, `quiet` and `verbose`, whether to log every step
--    as it is taken, to only pretend to run commands, to say nothing and to
--    say more;
--  * `release`, the version to release, and `valreqs`, names of variables
--    to print, which only the command line gives;
--  * `fname`, the lukefile that the recipe is read from, which is what to
--    call the recipe in diagnoses, unless there is a `source`.
local function mkrequest(options)
   local o = merged({
      clidefs = {},
      debug   = false,
      dryrun  = false,
      quiet   = false,
      targets = {},
      valreqs = {},
      verbose = false,
   }, options)

   return merged(o, {
      log     = choose(o.debug, function() return dump end, function() return nop end),
      source  = o.source or o.fname or 'lukefile',
      spawn   = choose(o.dryrun, function()
         return function()
            return 0, '', ''
         end
      end, function() return spawn end),
      verbose = choose(o.verbose, function() return display end, function() return nop end),
      write   = choose(o.quiet, function() return nop end, function() return display end),
   })
end


-- Whether *recipe* has no rule for anything to make.
local function nothing_to_build(recipe)
   local sections = script_sections(recipe)
   return not some(pack(recipe.modules, recipe.ldocs, sections.bin, sections.files, sections.install), function(rules)
      return not isempty(rules or {})
   end)
end


-- What to make of *recipe*, as *request* asks, with the settings that
-- luke makes up for it, and what the rest of luke needs of that.
local function prepare(recipe, request)
   local source = request.source
   -- A release builds with LuaRocks, from the release rockspecs.
   diagnose(request.release ~= nil or not nothing_to_build(recipe),
      "nothing to build in '%s': it has no modules, scripts, files or ldocs", source)
   each({'package', 'version'}, function(key)
      diagnose(recipe[key] ~= nil, "no %s in '%s'", key, source)
   end)
   local luke, release = merged(recipe), request.release

   local sections = script_sections(luke)
   local installbin = sections.install
   local rulesets = {luke.modules or {}, sections.bin, sections.files, installbin}
   local targets = selected_targets(choose(release, {}, request.targets), rulesets)

   local named = reject(targets, 'install')
   local build = ordered_pluck(luke.modules, named)
   local install, install_scripts = installs(luke, installbin, build, named, targets)
   local scripts = {build = script_entries(sections, named), install = install_scripts}
   luke.modules = build

   local ref, srcdir = gitref(), abs_top_srcdir()

   luke.substitute = merged({
      abs_top_srcdir = srcdir,
      gitref         = ref,
      LUA_VERSION    = DEFAULTENV.LUA_VERSION,
      package        = interpolate_to_substitute(luke.package),
      version        = interpolate_to_substitute(luke.version),
   }, luke.substitute)

   luke.variables = merged({
      LUA_DIR        = '/usr',
      LUA_BINDIR     = '$LUA_DIR/bin',
      LUA_INCDIR     = '$LUA_DIR/include/lua$LUA_VERSION',
      LUA_LIBDIR     = '$LUA_DIR/lib',
      abs_top_srcdir = srcdir,
      gitref         = ref,
      objdir         = platforms[1],
      package        = luke.package,
      version        = luke.version,
   }, collect_variables(luke), luke.variables)

   return {
      clidefs = request.clidefs,
      debug   = request.debug,
      dryrun  = request.dryrun,
      filled  = {},
      install = install,
      log     = request.log,
      luke    = luke,
      quiet   = request.quiet,
      release = release,
      scripts = scripts,
      spawn   = request.spawn,
      valreqs = request.valreqs,
      verbose = request.verbose,
      write   = request.write,
   }
end


return {
   mkrequest = mkrequest,

   prepare   = prepare,
}

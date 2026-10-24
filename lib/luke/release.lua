--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke._base',
   'luke.compile',
   'luke.configure',
   'luke.environment',
   'luke.functional',
   'luke.lukefile',
   'type.context-manager',
   'type.path',

   date = os.date,
}


-- The header for the next release's news, at the top of NEWS.
local PLACEHOLDER = '\n(## [^\n]*%?%.%?[^\n]*\n)'

-- The first line of a rockspec, which sets the version it builds.
local MODREV = "^(local _MODREV, _SPECREV = ')[^']*(')"

-- The name of a development rockspec, around its version.
local DEVROCKSPEC = '^(.-%-)dev(%-%d+%.rockspec)$'


-- The tag that releases *version*, of *rock* if there is one, and the
-- branch that it is released on.  Rocks released from one repository
-- have versions of their own, so the tag names every rock but the
-- package of the lukefile.
local function names(rock, version)
   local tag = (rock ~= nil and rock .. '-' or '') .. 'v' .. version
   return tag, 'release-' .. tag
end


-- The name of the rock that the development rockspec *rockspec* is of.
local function rockname(rockspec)
   local name = basename(rockspec)
   return match(name, '^(.-)%-dev%-%d+%.rockspec$') or (gsub(name, '%.rockspec$', ''))
end


-- The development rockspecs that the release *rules* release, as a list:
-- `rockspec` is a path, or a list of them.
local function rockspecs(rules)
   return isstring(rules.rockspec) and {rules.rockspec} or rules.rockspec or {}
end


-- The development rockspec of *rockspecs* that a release is announced by:
-- the first that starts with *package*, or else the first.
local function main_rockspec(rockspecs, package)
   for i = 1, len(rockspecs) do
      if sub(basename(rockspecs[i]), 1, len(package)) == package then
         return rockspecs[i]
      end
   end
   return rockspecs[1]
end


-- The release tables of a *release* that has a table for each development
-- rockspec, by the name of its rock, each with its `rockspec`, or else nil.
local function release_tables(release)
   local r
   for k, v in next, release do
      if isstring(k) and match(k, '%.rockspec$') then
         r = r or {}
         r[rockname(k)] = merged(v, {rockspec = k})
      end
   end
   return r
end


-- The output of git with arguments *...*, without its trailing newline,
-- or nil if git fails.
local function git(env, ...)
   local status, err, out = spawn(env, 'git', ...)
   if status == 0 then
      return (gsub(out, '\n$', ''))
   end
end


-- Whether LuaRocks has every dependency of *rockspec* installed for
-- this Lua, writing any that are missing if not.  With no server to
-- search, `make --only-deps` installs nothing.
local function dependencies_installed(env, rockspec)
   local status, err, out = spawn(env, env.LUAROCKS or 'luarocks', '--lua-version=$LUA_VERSION',
      'make --only-deps --only-server=', shellword(rockspec))
   if status ~= 0 then
      stderr:write(match(out or '', '^(Missing dependencies.-)\n\n') or err or '', '\n')
   end
   return status == 0
end


-- Whether the first release header in NEWS *text* is the placeholder
-- for the next release, with some news before the header that follows.
local function has_placeholder(text)
   local header, body = match('\n' .. text, '\n(## [^\n]*\n)(.*)')
   if header == nil or match('\n' .. header, PLACEHOLDER) == nil then
      return false
   end
   return match(match(body, '^(.-)\n## ') or body, '%S') ~= nil
end


-- NEWS *text* with a header for *version*, released on *date*, between
-- the placeholder and the news it releases.
local function add_release_header(text, version, date)
   local header = format('## Noteworthy changes in release %s (%s) [stable]', version, date)
   return (gsub(text, PLACEHOLDER .. '\n*', '\n%1\n\n' .. header .. '\n\n', 1))
end


-- The news for release *version* in NEWS *text*, from its header up to
-- the header of the release before, if any.
local function release_news(text, version)
   local header = '\n(## Noteworthy changes in release ' .. gsub(version, '%p', '%%%0') .. ' %(.*)'
   local news = match('\n' .. text, header)
   if news ~= nil then
      return (gsub(match(news, '^(.-)\n## ') or news, '%s*$', ''))
   end
end


-- The variables that rockspec *text* sets, or else an empty table.
local function rockspec_fields(text)
   local r = {}
   local chunk = text and loadstring(text, 'rockspec', r)
   if chunk == nil or not pcall(chunk) then
      return {}
   end
   return r
end


-- The package name and announcement for release *version*: the project
-- summary and home page from *rockspec* text, the *news* for the
-- release, and how to install it with LuaRocks, as far as each is
-- known.  The name in *rockspec* wins over *package*.
local function announcement(package, version, news, rockspec, rocks)
   local fields = rockspec_fields(rockspec)
   local description = istable(fields.description) and fields.description or {}
   package = isstring(fields.package) and fields.package or package
   local lines = compact(flatten(list(
      isstring(description.summary) and {description.summary, ''} or {},
      format('I am happy to announce release %s of %s.', version, package), '',
      isstring(description.homepage) and {format("%s's home page is at %s", package, description.homepage), ''} or {},
      news and {news, ''} or {},
      rockspec and {'Install it with LuaRocks, using:', '', map(rocks or {package}, function(rock)
         return format('    luarocks install %s %s', rock, version)
      end)} or {}
   )))
   return package, match(concat(lines, '\n'), '^(.-)%s*$') .. '\n'
end


-- NEWS *text* without the placeholder, and the blank line after it.
local function remove_placeholder(text)
   return (gsub(text, PLACEHOLDER .. '\n?', '\n', 1))
end


-- Tag a release as *name* with the annotated message *notes*, written to
-- a temporary file for git to read as it is, keeping the '#' of each
-- Markdown header; return the exit status.
local function tag(L, env, name, notes)
   local filename = tmpname()
   with(File(filename, 'w'), function(h)
      h:write(notes)
   end)
   local status = run(L, env, {'git tag -a --cleanup=verbatim', name, '-F', filename})
   rm(filename)
   return status
end


-- Write the result of passing the content of *path* to *fn* to *dest*,
-- or else back to *path*; or with --dry-run only say so; return 0.
local function edit(L, path, fn, dest)
   dest = dest or path
   L.write((dest == path and 'updating ' or 'creating ') .. dest, '\n')
   if not L.dryrun then
      local content = fn(slurp(File(path)))
      with(File(dest, 'w'), function(h)
         h:write(content)
      end)
   end
   return 0
end


-- *text*, with every occurrence of each find string in the ordered map
-- *pairs* replaced, in the order written, as plain text rather than as
-- a pattern, by its replacement, filled from *substitute*.
local function replace(text, substitute, pairs)
   return foldl(pairs, text, function(r, pair)
      local find, replacement = destructure(pair)
      return (gsub(r, (gsub(find, '%p', '%%%0')), (gsub(expand(substitute, replacement), '%%', '%%%%'))))
   end)
end


-- The release rockspec for *version*, from development *rockspec*.
local function rockspec_name(rockspec, version)
   return (gsub(rockspec, DEVROCKSPEC, '%1' .. version .. '%2'))
end


-- Rockspec *text*, set to build *version*.
local function set_modrev(text, version)
   return (gsub(text, MODREV, '%1' .. version .. '%2', 1))
end


-- The command to replace what is at *path* on the branch checked out in
-- *worktree* with a copy of the file (or the contents of the directory)
-- *source* if any.  Remove what is there first except templates.
local function copy_command(source, worktree, path, optional)
   local dest = worktree .. '/' .. path
   local from, to = shellword(source), shellword(dest)
   local copy = format("git -C %s rm -r --quiet --ignore-unmatch -- %s ':(exclude)*.in'"
      .. ' && if test -d %s; then $MAKEDIRS %s && cp -R %s/. %s; else $MAKEDIRS %s && cp %s %s; fi',
      shellword(worktree), shellword(path), from, to, from, to, shellword(dirname(dest)), from, to)
   return choose(optional, format('if test -e %s; then %s; fi', from, copy), copy)
end


-- The steps for publishing each of *copies*, from a branch table in the
-- lukefile `release` table, in the order written, to the *worktree* of
-- that branch: copy its source there. A template is filled in place
-- without its '.in' suffix.  Then run its `command`, if any, there.
local function publish_steps(L, env, substitute, worktree, copies)
   return compact(flatten(list(map(copies, function(pair)
      local path, copy = destructure(pair)
      local source, optional = copy.source, copy.optional
      local dest = worktree .. '/' .. path
      local template = match(source, '%.in$') ~= nil
      return compact(flatten(list(
         choose(optional or not template, function()
            return bind(run, {L, env, {copy_command(source, worktree, path, optional)}})
         end),
         choose(template, function()
            return bind(edit, {L, choose(optional, dest, source), bind(expand, {substitute}),
               (gsub(dest, '%.in$', ''))})
         end)
      )))
   end), copies.command and bind(run, {L, env, {'cd', worktree, '&&', copies.command}}))))
end


-- The checks of the repository that must pass to release as *tag* on
-- *branch* from *main*, the branch checked out, as a description, a
-- predicate, and the command that undoes what a failed release did to
-- make it fail, if any.
local function repository_checks(env, tag, branch, main)
   local name = choose(main ~= nil, main, 'a branch')
   local checkout = format('git checkout --force %s', name)
   return {
      {'the working tree is clean', function()
         return git(env, 'status --porcelain') == ''
      end, checkout},
      -- Not detached, and after a failed release, still on *main*.
      {format('%s is checked out', name), function()
         return main ~= nil and git(env, 'symbolic-ref --short HEAD') == main
      end, checkout},
      {'origin can be fetched', function()
         return git(env, 'fetch --quiet origin') ~= nil
      end},
      {format('%s is up to date with origin', name), function()
         return git(env, 'rev-parse refs/heads/' .. main) == git(env, 'rev-parse origin/' .. main)
      end, format('git reset --hard origin/%s', name)},
      {format('branch %s is unused', branch), function()
         return git(env, 'rev-parse --verify --quiet refs/heads/' .. branch) == nil
      end, 'git branch -D ' .. branch},
      {format('tag %s is unused', tag), function()
         return git(env, 'rev-parse --verify --quiet refs/tags/' .. tag) == nil
      end, 'git tag -d ' .. tag},
   }
end


-- The checks that the news file of *release* has a placeholder header
-- to release *version* under, and no release of it yet.
local function news_checks(release, version)
   return choose(release.news ~= nil, function()
      local news = slurp(File(release.news))
      return {
         {format('%s has news under a placeholder header', release.news), function()
            return news ~= nil and has_placeholder(news)
         end},
         {format('%s has no %s release yet', release.news, version), function()
            return news ~= nil and find(news, 'release ' .. version .. ' (', 1, true) == nil
         end},
      }
   end, {})
end


-- The checks that each file that *release* replaces text in exists, and
-- has each text to replace, filled from *substitute*.
local function replacement_checks(release, substitute)
   return flatmap(release.replacements or {}, function(entry)
      local path, pairs = destructure(entry)
      local checks = {
         {format('%s exists', path), function()
            return exists(path)
         end},
      }
      -- Each find string is looked for in the text that the
      -- replacements before it leave.
      for i = 1, len(pairs) do
         local text, earlier = destructure(pairs[i]), list(unpack(pairs, 1, i - 1))
         append(checks, {format("%s contains '%s'", path, text), function()
            local content = slurp(File(path))
            return content ~= nil and find(replace(content, substitute, earlier), text, 1, true) ~= nil
         end})
      end
      return checks
   end)
end


-- The checks that each branch that *release* publishes to can be updated.
local function branch_checks(env, release)
   return flatmap(branches(release), function(pages)
      local copies = release[pages]
      -- TODO: the source of a copy under another name is not checked,
      -- as the build may make it, so a missing one fails only after the
      -- release is tagged.
      local templates = map(filter(ordered_keys(copies), function(path)
         return ordered_get(copies, path).optional and match(path, '%.in$') ~= nil
      end), function(template)
         return {format('%s or the release has %s', pages, template), function()
            return exists(template) or git(env, format('cat-file -e origin/%s:%s', pages, template)) ~= nil
         end}
      end)
      return {
         -- A branch that is only on origin, as in a fresh clone, or that
         -- is behind it, is set to origin's before the release adds its
         -- worktree; one with commits that origin lacks is diagnosed.
         {format('%s is not ahead of origin', pages), function()
            local ref, origin = git(env, 'rev-parse refs/heads/' .. pages), git(env, 'rev-parse origin/' .. pages)
            return origin ~= nil and (ref == nil or ref == origin
               or git(env, 'merge-base --is-ancestor', ref, origin) ~= nil)
         end, format('git branch -f %s origin/%s', pages, pages)},
         -- git checks out a branch in only one worktree at a time.
         {format('%s can be checked out in a new worktree', pages), function()
            local worktrees = git(env, 'worktree list --porcelain')
            return worktrees ~= nil
               and find('\n' .. worktrees .. '\n', '\nbranch refs/heads/' .. pages .. '\n', 1, true) == nil
         end},
         unpack(templates),
      }
   end)
end


-- The checks that the rockspec of *release* is a development one that
-- can be set to a version, and that its dependencies are installed, if
-- the release asks.
local function rockspec_checks(env, release)
   return flatmap(rockspecs(release), function(name)
      local rockspec = slurp(File(name))
      return reject(list(
         {format('%s is a development rockspec', name), function()
            return match(name, DEVROCKSPEC) ~= nil
         end},
         {format('%s sets _MODREV on its first line', name), function()
            return rockspec ~= nil and match(rockspec, MODREV) ~= nil
         end},
         choose(release.check_dependencies, {format('the dependencies of %s are installed', name), function()
            return dependencies_installed(env, name)
         end})
      ), nil)
   end)
end


-- Each check that must pass before cutting a release of *version* from
-- *main*, the branch checked out, as a description, a predicate, and
-- the command that undoes what a failed release did to make it fail,
-- if any.  Replacements are filled from *substitute*.
local function preconditions(env, release, tag, branch, version, main, substitute)
   return flatmap(list(
      repository_checks(env, tag, branch, main),
      news_checks(release, version),
      replacement_checks(release, substitute),
      branch_checks(env, release),
      rockspec_checks(env, release)
   ), id)
end


-- The undo command of each of *checks* that fails now, after a failed
-- release, in order and without repeats.
local function undo_commands(checks)
   return foldl(filter(checks, function(check)
      local _, predicate, undo = unpack(check)
      return undo ~= nil and not predicate()
   end), {}, function(r, check)
      choose(not contains(r, check[3]), bind(append, {r, check[3]}))
   end)
end


-- Every file that the build of *luke* generates, which is committed to
-- the release branch, so that the release needs no build to use: each
-- module filled from a template, and then the target of each generated
-- file.
local function generated(luke)
   local templates = map(luke.modules or {}, function(pair)
      local _, rules = destructure(pair)
      return map(filter(rules.sources or {}, function(source)
         return match(source, '%.in$') ~= nil
      end), function(source)
         return (gsub(source, '%.in$', ''))
      end)
   end)
   return flatten(list(templates, map(ordered_keys(luke.files), function(name)
      return script_target(name, ordered_get(luke.files, name))
   end)))
end


-- The number of each line of a .gitignore in the working tree that
-- ignores an untracked file beneath *paths*, by .gitignore path.  Git
-- names a .gitignore in the working tree by its relative path, and any
-- other source of ignore patterns, such as .git/info/exclude or a
-- global excludes file, which a release leaves alone, otherwise.
local function ignoring(env, paths)
   local files = {}
   local listed = git(env, 'ls-files --others --ignored --exclude-standard --', unpack(map(paths, shellword)))
   for file in gmatch(listed or '', '[^\n]+') do
      append(files, shellword(file))
   end
   local r = {}
   if not isempty(files) then
      local verbose = git(env, 'check-ignore --no-index --verbose --', unpack(files))
      for source, n in gmatch(verbose or '', '([^\n]-):(%d+):[^\n]*') do
         if match(source, '^[^/]') and match(source, '^%.git/') == nil and match(source, '%.gitignore$') then
            r[source] = r[source] or {}
            r[source][tonumber(n)] = true
         end
      end
   end
   return r
end


-- Remove each line of a .gitignore in the working tree that ignores a
-- file beneath *paths*, until none does, so that the release branch
-- ignores none of the files it tracks; return 0.
local function unignore(L, env, paths)
   repeat
      local lines = ignoring(env, paths)
      local sources = sorted(keys(lines))
      each(sources, function(source)
         edit(L, source, function(text)
            local n = 0
            return concat(filter(gmatch(text, '[^\n]*\n?'), function(line)
               n = n + 1
               return line ~= '' and not lines[source][n]
            end))
         end)
      end)
   until L.dryrun or isempty(sources)
   return 0
end


-- The description of the first of *checks* that fails, if any, saying
-- how each is going on `L.verbose`.
local function failed_check(L, checks)
   return firstof(checks, function(check)
      local description, predicate = unpack(check)
      L.verbose('checking whether ', description, '... ')
      local ok = predicate()
      L.verbose(ok and 'yes\n' or 'no\n')
      if not ok then
         return description
      end
   end)
end


-- The steps that cut a release, to run in order and stop at the first
-- to fail.  *plan* says what to release: its `version` and `main`
-- branch, the `rules` of the lukefile `release` table, the date `today`,
-- what to `add` and the `released` rockspec, the `pages` branches and
-- the `worktrees` for them, and the `substitute` environment.
local function release_steps(L, env, build, plan)
   local version, rules = plan.version, plan.rules
   local news, pages, worktrees = rules.news, plan.pages, plan.worktrees
   local tagname, branch = plan.tag, plan.branch
   -- TODO: before branching, rename any PACKAGE-git-1.rockspec to
   -- PACKAGE-dev-1.rockspec, setting its _MODREV from 'git' to 'dev'.
   return compact(flatten(list(
      news and {
         bind(edit, {L, news, bind(add_release_header, {[2]=version, [3]=plan.today})}),
         bind(run, {L, env, {'git commit', format("-m 'maint: update NEWS.md for %s.'", version), news}}),
      },
      bind(run, {L, env, {'git checkout -b', branch}}),
      news and bind(edit, {L, news, remove_placeholder}),
      map(rules.replacements or {}, function(entry)
         local path, pairs = destructure(entry)
         return bind(edit, {L, path, bind(replace, {[2]=plan.substitute, [3]=pairs})})
      end),
      build,
      map(rockspecs(rules), function(rockspec)
         return {
            bind(edit, {L, rockspec, bind(set_modrev, {[2]=version}), rockspec_name(rockspec, version)}),
            bind(run, {L, env, {'git rm --quiet', rockspec}}),
         }
      end),
      not isempty(plan.added) and {
         bind(unignore, {L, env, plan.added}),
         bind(run, {L, env, {'git add -f', unpack(plan.added)}}),
      } or nil,
      bind(run, {L, env, {format("git commit -a -m 'Release %s.'", tagname)}}),
      bind(tag, {L, env, tagname, plan.notes}),
      map(pages, function(branch)
         local worktree = worktrees[branch]
         return {
            git(env, 'rev-parse refs/heads/' .. branch) ~= git(env, 'rev-parse origin/' .. branch)
               and bind(run, {L, env, {'git branch --quiet --force', branch, 'origin/' .. branch}}) or {},
            bind(run, {L, env, {'git worktree add --quiet', worktree, branch}}),
            publish_steps(L, env, plan.substitute, worktree, rules[branch]),
            bind(run, {L, env, {'git -C', worktree, "add -A && git -C", worktree,
               format("commit -m '%s: update to $package %s.'", branch, version)}}),
            bind(run, {L, env, {'git worktree remove', worktree}}),
         }
      end),
      bind(run, {L, env, {'git checkout --quiet', plan.main}})
   )))
end


-- Say how to publish the release in *plan*, which is ready, by
-- announcing it as *package*.
local function ready_message(L, env, plan, package)
   local version, main, released = plan.version, plan.main, plan.released
   local pushed = compact(flatten(list(main, plan.branch, plan.tag, plan.pages)))
   L.write(format('\nRelease %s is ready.  To publish it:\n\n   git push origin %s\n',
      plan.tag, concat(pushed, ' ')))
   -- GH=true skips announcing the release on GitHub.
   local GH = env.GH or configure(L, env, {checkprog='GitHub CLI', progs={'gh', 'true'}})
   if GH ~= 'true' then
      L.write(format("   %s release create %s --verify-tag --latest --title '[ANN] %s v%s released' --notes-from-tag\n",
         GH, plan.tag, package, version))
   end
   if not isempty(released) then
      L.write(format('   git checkout %s\n%s   git checkout %s\n', plan.branch,
         concat(map(released, function(rockspec)
            return format('   luarocks upload %s\n', rockspec)
         end)), main))
   end
end


-- Say how to undo release *tag*, which failed, as far as the
-- *checks* that it passed before and fails now say.
local function failed_message(L, checks, tag)
   local undo = undo_commands(checks)
   choose(not isempty(undo), function()
      L.write(format('\nRelease %s failed.  To undo it before trying again:\n\n%s', tag,
         concat(map(undo, function(command)
            return '   ' .. command .. '\n'
         end))))
   end)
end


return {
   copy_command = copy_command,

   -- Cut a release of `L.release`, configured by the lukefile `release`
   -- table, calling *build* to build everything for that version.
   release = function(L, env, build)
      local version, main = L.release, git(env, 'symbolic-ref --short HEAD')
      local substitute = mkenv({version = version}, L.clidefs, L.luke.substitute, SHELLENV)

      -- Release the rock that `rock=NAME` asks for, or else the package of
      -- the lukefile, by the release table of that rock: its own, if the
      -- release table has a table for each development rockspec, or the
      -- release table itself, to release every rockspec in it together.
      local package = interpolate(env, L.luke.package)
      local rock = (L.clidefs or {}).rock or package
      local release = L.luke.release or {}
      local rules = (release_tables(release) or {[package] = release})[rock]
      if rules == nil then
         fatal("cannot release %s: no rock '%s' in the release table of the lukefile", version, rock)
         return 1
      end

      local tag, branch = names(choose(rock ~= package, rock), version)
      local checks = preconditions(env, rules, tag, branch, version, main, substitute)
      local failed = failed_check(L, checks)
      if failed ~= nil then
         fatal('cannot release %s: expected that %s', version, failed)
         return 1
      end

      local news, rocks = rules.news, rockspecs(rules)
      local released = map(rocks, function(rockspec)
         return rockspec_name(rockspec, version)
      end)
      local main_rock = main_rockspec(rocks, rock)
      local today = date '%Y-%m-%d'

      -- Compose the announcement before any step changes NEWS, so that
      -- --dry-run tags with the same message.
      local _, notes = announcement(rock, version,
         news and release_news(add_release_header(slurp(File(news)) or '', version, today), version),
         main_rock and slurp(File(main_rock)),
         len(rocks) > 1 and map(rocks, rockname) or nil)

      -- A temporary worktree for updating each branch that the release
      -- copies files to.
      local pages = branches(rules)
      local worktrees = tabulate(pages, function(branch)
         local worktree = tmpname()
         rm(worktree)
         return branch, worktree
      end)
      local plan = {
         version = version, tag = tag, branch = branch, main = main, rules = rules, today = today, notes = notes,
         added = compact(flatten(list(rules.add, generated(L.luke), released))), released = released,
         pages = pages, worktrees = worktrees, substitute = substitute,
      }

      local status = firstof(release_steps(L, env, build, plan), isnonzero, call) or 0

      -- Remove any worktree that a failed step leaves behind, with
      -- whatever was copied into it.
      choose(status ~= 0, function()
         each(filter(sorted(values(worktrees)), exists), function(worktree)
            run(L, env, {'git worktree remove --force', worktree})
         end)
      end)
      if status == 0 then
         ready_message(L, env, plan, rock)
      else
         -- Whatever the failed release left behind now fails the checks
         -- it passed before.
         failed_message(L, checks, plan.tag)
      end
      return status
   end,
}

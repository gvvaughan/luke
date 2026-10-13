--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke._base',
   'luke.compile',
   'luke.environment',
   'luke.functional',
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


-- The output of git with arguments *...*, without its trailing newline,
-- or nil if git fails.
local function git(env, ...)
   local status, err, out = spawn(env, 'git', ...)
   if status == 0 then
      return (gsub(out, '\n$', ''))
   end
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


-- NEWS *text* without the placeholder, and the blank line after it.
local function remove_placeholder(text)
   return (gsub(text, PLACEHOLDER .. '\n?', '\n', 1))
end


-- Write and run *...* as a shell command, or with --dry-run only write
-- it; return its exit status.
local function run(L, env, ...)
   local command = concat({...}, ' ')
   L.write(interpolate(env, command), '\n')
   if L.dryrun then
      return 0
   end
   local status, err = spawn(env, command)
   if status ~= 0 then
      stderr:write(err, '\n')
   end
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


-- The release rockspec for *version*, from development *rockspec*.
local function rockspec_name(rockspec, version)
   return (gsub(rockspec, DEVROCKSPEC, '%1' .. version .. '%2'))
end


-- Rockspec *text*, set to build *version*.
local function set_modrev(text, version)
   return (gsub(text, MODREV, '%1' .. version .. '%2', 1))
end


-- The command to replace *dest* with a copy of the file or directory
-- *source*, or when *optional*, only if there is a *source*.
local function copy_command(source, dest, optional)
   local from, to = shellword(source), shellword(dest)
   local copy = format('rm -rf %s && $MAKEDIRS %s && cp -R %s %s', to, shellword(dirname(dest)), from, to)
   return choose(optional, format('if test -e %s; then %s; fi', from, copy), copy)
end


-- The steps for publishing each of *copies*, from the lukefile
-- `gh-pages` table, to the gh-pages *worktree*: copy its source there,
-- then fill a template into place without its '.in' suffix, with values
-- from *substitute*.  A template under another name is filled straight
-- from the release, and an optional one from the copy on gh-pages,
-- whether or not the release has one to copy.
local function publish_steps(L, env, substitute, worktree, copies)
   return map(sorted(keys(copies)), function(path)
      local source, optional = copies[path].source, copies[path].optional
      local dest = worktree .. '/' .. path
      local template = match(source, '%.in$') ~= nil
      return except(list(
         choose(optional or not template, function()
            return bind(run, {L, env, copy_command(source, dest, optional)})
         end),
         choose(template, function()
            return bind(edit, {L, choose(optional, dest, source), bind(expand, {substitute}),
               (gsub(dest, '%.in$', ''))})
         end)
      ), nil)
   end)
end


-- Each check that must pass before cutting a release of *version*, as a
-- description and a predicate.
local function preconditions(env, release, version)
   local branch, tag = 'release-v' .. version, 'v' .. version
   local checks = {
      {'the working tree is clean', function()
         return git(env, 'status --porcelain') == ''
      end},
      {'master is checked out', function()
         return git(env, 'symbolic-ref --short HEAD') == 'master'
      end},
      {'master is up to date with origin', function()
         return git(env, 'fetch --quiet origin') ~= nil
            and git(env, 'rev-parse HEAD') == git(env, 'rev-parse origin/master')
      end},
      {format('branch %s is unused', branch), function()
         return git(env, 'rev-parse --verify --quiet refs/heads/' .. branch) == nil
      end},
      {format('tag %s is unused', tag), function()
         return git(env, 'rev-parse --verify --quiet refs/tags/' .. tag) == nil
      end},
   }

   if release.news ~= nil then
      local news = slurp(File(release.news))
      append(checks, {format('%s has news under a placeholder header', release.news), function()
         return news ~= nil and has_placeholder(news)
      end})
      append(checks, {format('%s has no %s release yet', release.news, version), function()
         return news ~= nil and find(news, 'release ' .. version .. ' (', 1, true) == nil
      end})
   end

   local ghpages = release['gh-pages']
   if ghpages ~= nil then
      append(checks, {'gh-pages is up to date with origin', function()
         local ref = git(env, 'rev-parse refs/heads/gh-pages')
         return ref ~= nil and ref == git(env, 'rev-parse origin/gh-pages')
      end})
      -- TODO: the source of a copy under another name is not checked,
      -- as the build may make it, so a missing one fails only after the
      -- release is tagged.
      map(filter(sorted(keys(ghpages)), function(path)
         return ghpages[path].optional and match(path, '%.in$') ~= nil
      end), function(template)
         append(checks, {format('gh-pages or the release has %s', template), function()
            return exists(template) or git(env, 'cat-file -e gh-pages:' .. template) ~= nil
         end})
      end)
   end

   if release.rockspec ~= nil then
      local rockspec = slurp(File(release.rockspec))
      append(checks, {format('%s is a development rockspec', release.rockspec), function()
         return match(release.rockspec, DEVROCKSPEC) ~= nil
      end})
      append(checks, {format('%s sets _MODREV on its first line', release.rockspec), function()
         return rockspec ~= nil and match(rockspec, MODREV) ~= nil
      end})
   end

   return checks
end


-- The targets of every generated file in *luke*, which are committed to
-- the release branch.
local function generated(luke)
   return map(sorted(keys(luke.files)), function(name)
      return script_target(name, luke.files[name])
   end)
end


return {
   -- Cut a release of `L.release`, configured by the lukefile `release`
   -- table, calling *build* to build everything for that version.
   release = function(L, env, build)
      local version = L.release
      local failed = dropuntil(preconditions(env, L.luke.release or {}, version), function(check)
         local description, predicate = unpack(check)
         L.verbose('checking whether ', description, '... ')
         local ok = predicate()
         L.verbose(ok and 'yes\n' or 'no\n')
         if not ok then
            return description
         end
      end)
      if failed ~= nil then
         fatal('cannot release %s: check failed: %s', version, failed)
         return 1
      end

      -- TODO: when a step fails after the NEWS commit on master, master
      -- is left ahead of origin, so a rerun fails the checks above until
      -- that commit is reset by hand.
      local rules = L.luke.release or {}
      local news, rockspec = rules.news, rules.rockspec
      local released = rockspec and rockspec_name(rockspec, version)
      local added = flatten(rules.add, generated(L.luke), released)
      local ghpages = rules['gh-pages']
      local worktree = tmpname()
      rm(worktree)

      -- TODO: before branching, rename any PACKAGE-git-1.rockspec to
      -- PACKAGE-dev-1.rockspec, setting its _MODREV from 'git' to 'dev'.
      local steps = flatten(
         news and {
            bind(edit, {L, news, bind(add_release_header, {[2]=version, [3]=date '%Y-%m-%d'})}),
            bind(run, {L, env, 'git commit', format("-m 'maint: update NEWS.md for %s.'", version), news}),
         },
         bind(run, {L, env, 'git checkout -b', 'release-v' .. version}),
         news and bind(edit, {L, news, remove_placeholder}),
         function()
            if L.dryrun then
               L.write(format('building with version=%s', version), '\n')
               return 0
            end
            return build()
         end,
         rockspec and {
            bind(edit, {L, rockspec, bind(set_modrev, {[2]=version}), released}),
            bind(run, {L, env, 'git rm --quiet', rockspec}),
         },
         not isempty(added) and bind(run, {L, env, 'git add -f', unpack(added)}) or nil,
         bind(run, {L, env, format("git commit -a -m 'Release v%s.'", version)}),
         bind(run, {L, env, 'git tag', 'v' .. version}),
         ghpages and {
            bind(run, {L, env, 'git worktree add --quiet', worktree, 'gh-pages'}),
            publish_steps(L, env, makeenv({version = version}, L.clidefs, L.luke.substitute, SHELLENV),
               worktree, ghpages),
            bind(run, {L, env, 'git -C', worktree, "add -A && git -C", worktree,
               format("commit -m 'gh-pages: update to $package %s.'", version)}),
            bind(run, {L, env, 'git worktree remove', worktree}),
         },
         bind(run, {L, env, 'git checkout --quiet master'})
      )

      local status = dropuntil(steps, isnonzero, call) or 0

      -- Remove the gh-pages worktree that a failed step leaves behind,
      -- with whatever was copied into it.
      choose(status ~= 0 and exists(worktree), function()
         run(L, env, 'git worktree remove --force', worktree)
      end)
      if status == 0 then
         local pushed = flatten('master', 'release-v' .. version, 'v' .. version, ghpages and 'gh-pages')
         L.write(format('\nRelease v%s is ready.  To publish it:\n\n   git push origin %s\n',
            version, concat(pushed, ' ')))
         if released ~= nil then
            L.write(format('   git checkout release-v%s\n   luarocks upload %s\n   git checkout master\n',
               version, released))
         end
      end
      return status
   end,
}

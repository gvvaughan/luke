--[[
 Use the source, Luke!
 Copyright (C) 2014-2026 Gary V. Vaughan
]]

local _ENV = require 'luke.normalize' {
   'luke._base',
   'luke.compile',
   'luke.functional',
   'type.context-manager',
}


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
   local header, body = match('\n' .. text, '\n(## [^\n]*)\n(.*)')
   if header == nil or find(header, '?.?', 1, true) == nil then
      return false
   end
   return match(match(body, '^(.-)\n## ') or body, '%S') ~= nil
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

   return checks
end


return {
   -- Cut a release of `L.release`, configured by the lukefile `release`
   -- table.
   release = function(L, env)
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
      return 0
   end,
}

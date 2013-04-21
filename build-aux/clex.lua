-- Replace common tokens in C files to reduce source size
--
-- Copyright (C) 2009, 2011 Gary V. Vaughan
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

local M = {}

local bessel = {
  j0 = true,  j1 = true,  jn = true,  y0 = true,  y1 = true,  yn = true,
  j0f = true, j1f = true, jnf = true, y0f = true, y1f = true, ynf = true,
  j0l = true, j1l = true, jnl = true, y0l = true, y1l = true, ynl = true,
}

local DEFINEOVERHEAD = 10

-- Helper functions --

-- Calculate the text of the next replacement short token.
function M.replacement (shortcount)
  local t1 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local lt1 = t1:len ()
  local t2 = "_0123456789"
  local lt2 = t2:len ()
  local t3 = t1 .. t2
  local lt3 = lt1 + lt2

  local s = {}
  local n = shortcount -1

  -- Extract the Nth character of S
  local function charof (s, n) return s:sub (n +1, n +1) end

  table.insert (s, charof (t1, n % lt1))
  if (n >= lt1) then
    n = (n / lt1) - 1
    table.insert (s, charof (t2, n % lt2))
    if (n >= lt2) then
      n = (n / lt2) - 1
      table.insert (s, charof (t3, n % lt3))
      while (n >= lt3) do
        n = (n / lt3) - 1
        table.insert (s, charof (t3, n % lt3))
      end
    end
  end
  shortcount = shortcount + 1

  return table.concat (s)
end

local function next_replacement (filter)
  local i, r = 0, nil
  return function ()
    repeat
      i = 1+ i
      r = M.replacement (i)
      -- do not use a replacement that is already a valid token!
    until not filter[r] and not bessel[r]
    return r
  end
end


-- Return an iterator over the tokens in SOURCE that appear in FILTER.
local function tokenize (source)
  local iter = M.strip (source):gmatch "(0?[%a_][%w_]*)"
  return function ()
    local r = iter ()
    while r and (r:find ('^0[xX]%x+') or r:find ('^%d+L')) do
      -- be careful to ignore numeric constants
      r = iter ()
    end
    return r
  end
end


-- Return a table indexed by tokens from iter. The volue stored at
-- each index is the weight of that token: freq * length.
local function weights (iter)
  local tokens = {}

  for token in iter do
    if not tokens[token] then tokens[token] = 0 end
    tokens[token] = tokens[token] + #token
  end

  return tokens
end


-- Return a list of all tokens sorted into ascending order by weight
-- (as given by a token's value in the tokens table).
local function sort (tokens)
  local order = {}

  for token in pairs (tokens) do
    order[1+ #order] = token
  end
  table.sort (order, function (p, q) return tokens[p] > tokens[q] end)

  return order
end


-- Do the heavy lifting of populating various tables according to
-- appearance of tokens in SOURCE and or FILTER.
-- @see M.tokenmap ()
local function tokens (source, delfilt, minfilt, definefilt, ignorefilt)
  local weight = weights (tokenize (source))
  local order = sort (weight, nil)
  local minimap, uglimap, unmap = {}, {}, {}
  local erase, unseen = {}, {}

  -- always assign replacement tokens in order of weight
  local iter = next_replacement (weight)
  local replace = iter ()
  for _, token in ipairs (order) do
    local freq = weight[token] / #token

    if minfilt[token] then
      if weight[token] and #token > #replace then
        -- only replace when the token will get smaller!
        minimap[token] = replace
        replace = iter ()
      end

    elseif definefilt[token] then
      if (#token - #replace -1) * (freq - 1)  > DEFINEOVERHEAD then
        -- tokens that would need a #define must save space too!
        uglimap[token] = replace
        replace = iter ()
      end

    elseif delfilt[token] then
      erase[token] = true

    elseif not ignorefilt[token] then
      if #token > 1 then
        -- otherwise note the weight of an unfiltered token
        unmap[token] = weight[token]
      end

    end -- if filter[token]
  end -- for _, token

  local function union (...)
    r = {}
    for _, t in pairs({...}) do
      for k, _ in pairs(t) do
        r[k] = t[k]
      end
    end
    return r
  end
  local filtered = union (delfilt, minfilt, definefilt, ignorefilt)

  for token in pairs (filtered) do
    if not weight[token] then
      -- list tokens from FILTER, but not seen in SOURCE
      unseen[1+ #unseen] = token
    end
  end

  return minimap, uglimap, erase, unmap, unseen
end


-- API functions

-- Strip out everything that will lead to tokenisation problems
-- like strings and preprocessor directives.
function M.strip (source)
  local s, _ =  ("\n" .. source):   -- so \n# on line 1 matches below
    gsub ("/%*.-%*/", ""):          -- strip C comments
    gsub ("\n#include[^\n]*", ""):  -- strip include directive lines
    gsub ("\n#line[^\n]*", ""):     -- strip line directive lines
    gsub ("\n#%a*", "\n"):          -- strip other cpp directives
    gsub ("\\\\", ""):              -- strip escaped double \
    gsub ('\\"', ""):               -- strip escaped double quotes
    gsub ("\\'", ""):               -- strip escaped single quotes
    gsub ("'[^']'", " "):           -- replace 'char' with a space
    gsub ('"[^"]-"', ' '):          -- replace "strings" with a space
    gsub ("\n+", "\n"):             -- squash whitespace
    gsub ("^%s+", "")               -- strip leading whitespace
  return s
end


--- Assign replacemnts for SOURCELINES tokens listed in TOKENFILE.
-- Replacements are generated to be as short as possible while still
-- unique, and assigned according to how much effect each replacement
-- will have on the overall length of SOURCELINES - that is, the
-- shortest replacments are assigned to the longest and most frequently
-- repeated SOURCELINES tokens
--
-- Return 4 tables:
--   * minify map: source token -> replacement token
--   * uglify map: source token -> replacement token also requiring #define
--   * unmapped: unreplaced token -> token weight
--   * list of tokens in FILTER not present in SOURCE
--
--  @param tokenfile A file listing tokens that can safely be replaced.
--  @param sourcelines A list of lines from the source text.
--  @return 4 tables: replacements, definitions, unchanged & unseen.
function M.tokenmap (tokenfile, sourcelines)
  local sourcestring = table.concat (sourcelines, '\n')

  local filters = assert (loadfile (tokenfile))

  return tokens (sourcestring, filters ())
end


return M

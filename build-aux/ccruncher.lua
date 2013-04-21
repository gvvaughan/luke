-- ccruncher.lua
--
-- © 2008 David Given.
-- Copyright (C) 2011 Gary V. Vaughan
-- This file is licensed under the MIT open source license.
--
-- Extracts whitespace and renames tokens in a C file.
--
-- David Given dg@cowlark.com

local M = {}

local map  = {}       -- replacement token lookup
local defs = {}       -- replacements requiring a #define
local dels = {}       -- delete tokens (replace with nothing)

local next_line = nil

local nl     = false
local ws     = false
local id     = false
local breaks = true

local function emit_nl ()    nl = true end
local function emit_ws ()    ws = true end
local function breaks_on ()  breaks = true end
local function breaks_off () breaks = false end

local function emit (s)
  local thisid = s:find "^[%w_]"

  if (thisid and id) or ws or nl then
    if nl or breaks then
      coroutine.yield "\n"
    else
      coroutine.yield " "
    end
    ws = false
    nl = false
  end

  if dels[s] then
    s = ""
  else
    local ss = map[s]
    if not ss then ss = defs[s] end
    if ss then s = ss end
  end

  coroutine.yield (s)

  id = s:find "[%w_]$"
end

local function process_string (s, pos, sep)
  local ss, se, sc1, sc2
  local rn = 2
  local r = {sep}

  pos = pos + 1
  if s:sub (-1) == "\\" then s = s .. "\n" end
  while true do
    ss, se, sc1, sc2 = s:find ("^([^\\" .. sep .. "]*)(.)", pos)
    while not ss do
      local m = next_line ()
      if not m then break end -- fall through to error below
      s = s .. m
      if s:sub (-1) == "\\" then s = s .. "\n" end
      ss, se, sc1, sc2 = s:find ("^([^\\" .. sep .. "]*)(.)", pos)
    end
    if not ss then
      error ("unterminated string or character constant in " .. s)
    end
    pos = se + 1

    r[rn] = sc1
    rn = rn + 1

    if sc2 == sep then
      r[rn] = sep
      break
    end

    if sc2 == "\\" then
      r[rn] = s:sub (se, se+1)
      rn = rn + 1
      pos = se + 2
    end
  end

  emit (table.concat (r))
  return pos, s
end

local function process_token (s, pos)
  local ss, se, sc1, sc2
  local len = #s

  ss = s:find ("^%s*$", pos)
  if ss then
    -- discard trailing whitespace
    return len+1
  end

  ss, se = s:find ("^(%s+)", pos)
  if ss then
    -- skip whitespace
    return se+1
  end

  ss, se = s:find ("^/%*.-%*/%s*", pos)
  if ss then
    -- skip one line C comments
    return se+1
  end

  ss, se = s:find ("^/%*", pos)
  if ss then
    -- skip multi-line C comments
    while true do
      s = next_line ()
      ss, se = s:find "%*/"
      if ss then
        return se+1, s
      end
    end
  end

  ss, se, sc1 = s:find ("^([\"'])", pos)
  if ss then
    -- output string or char constant
    return process_string (s, pos, sc1)
  end

  ss, se, sc1 = s:find ("^([%u%l_#][%w_#]*)", pos)
  if ss then
    emit (sc1)
    return se+1
  end

  ss, se, sc1 = s:find ("^(0[xX][%x]+)", pos)
  if ss then
    emit (sc1)
    return se+1
  end

  ss, se, sc1 = s:find ("^(%d+[lLuU]*)", pos)
  if ss then
    emit (sc1)
    return se+1
  end

  ss, se, sc1 = s:find ("^(%d*%.%d+[eE][-+]?%d+)", pos)
  if ss then
    emit (sc1)
    return se+1
  end

  ss, se, sc1 = s:find ("^(%d*%.%d+)", pos)
  if ss then
    emit (sc1)
    return se+1
  end

  ss, se, sc1 = s:find ("^([-()*,;.=<>/?:{}~+&|![%]%%^])", pos)
  if ss then
    emit (sc1)
    return se+1
  end

  error ("unrecognised token at " .. string.sub (s, pos))
end

local function process_normal_line (s)
  local pos = 1

  local token
  while pos <= #s do
    local news
    pos, news = process_token (s, pos)
    s = news or s
  end
end

local function process_preprocessor_directive (s)
  local ss, se, sc1, sc2, sc3
  local len = s:len ()

  -- Collapse continuations.

  while true do
    ss = s:find "\\$"
    if not ss then
      break
    end

    s = s:sub (1, ss-1) .. next_line ()
  end

  -- Eat #line statements.

  ss, se = s:find ("^%s*#line.*$", pos)
  if ss then
    return
  end

  ss, se, sc1 = s:find ('^%s*#%s*include%s+([<"].*[>"])%s*$', pos)
  if ss then
    emit_nl ()
    emit "#include"
    emit (sc1)
    emit_nl ()
    return
  end

  -- #define foo bar...

  ss, se, sc1, sc2 = s:find ("^%s*#%s*define%s+([%w_]+)%s+(.*)$", pos)
  if ss then
    if dels[sc1] then
      return
    end
    emit_nl ()
    emit "#define"
    process_normal_line (sc1)
    emit_ws ()
    process_normal_line (sc2)
    emit_nl ()
    return
  end

  -- #define foo(baz) bar...

  ss, se, sc1, sc2, sc3 = s:find ("^%s*#%s*define%s+([%w_]+)(%b())%s+(.*)$", pos)
  if ss then
    emit_nl ()
    emit "#define"
    process_normal_line (sc1)
    process_normal_line (sc2)
    emit_ws ()
    process_normal_line (sc3)
    emit_nl ()
    return
  end

  ss, se, sc1, sc2 = s:find ("^%s*#%s*([%u%l]+)%s*(.*)$", pos)
  if not ss then
    error ("malformed preprocessor directive in " .. s)
  end

  emit_nl ()
  emit ("#" .. sc1)
  process_normal_line (sc2)
  emit_nl ()
end

function byline (source)
  -- Split filename on "\n" and store in the lines table.
  local lines = {}
  source:gsub("([^\n]+)", function(s) lines[#lines+1] = s end)

  local lineno = 0
  return function ()
    lineno = lineno + 1
    if lines[lineno] then
      return lines[lineno]
    end
    lines = nil
    return nil
  end
end

function M.fetch (source, minimap, uglimap, erase)
  next_line = byline (source)
  map = minimap
  defs = uglimap
  dels = erase

  while true do
    local s = next_line ()
    if not s then
      break
    end

    if s:find "^%s*#" then
      breaks_off ()
      process_preprocessor_directive (s)
      breaks_on ()
    else
      process_normal_line (s)
    end

  end
end

return M

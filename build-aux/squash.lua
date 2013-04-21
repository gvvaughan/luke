-- Removes comments & whitespace and renames tokens in source files.
--
-- Copyright (C) 2011 Gary V. Vaughan
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

local ccruncher = require "ccruncher"
local llex      = require "llex"
local lparser   = require "lparser"
local optlex    = require "optlex"
local optparser = require "optparser"

local M = {}

--- Shorten, redefine or delete symbols in SOURCEFILE to shrink it.
-- This function is a wrapper for the ccruncher function from Prime-mover.
-- The process of selecting symbols for replacement is non-deterministic,
-- since the lexer does not understand the results of preprocessing, so
-- it will only operate on those symbols passed in its arguments, leaving
-- others unchanged.
--    @param sourcelines A list of lines in the file to be shrunk.
--    @param minimap A table for looking up replacments for safe symbols.
--    @param uglimap A similar table for symbols remapped with #defines.
--    @param erase   A list of symbols that will be removed entirely.A
-- @see ccruncher.lua
function M.cfile (sourcelines, minimap, uglimap, erase)
  local fetch = coroutine.wrap (function ()
    ccruncher.fetch (table.concat (sourcelines, "\n"), minimap, uglimap, erase)
  end)

  local lines = {}
  for k, v in pairs (uglimap) do
    lines[1+ #lines] = "#define " .. v .. " " .. k
  end
  current = ""
  while true do
    local token = fetch ()
    if not token then break end

    current = current .. token
    if current:sub (-1) == "\n" then
      lines[1+ #lines] = current:sub (1, -2)
      current = ""
    end
  end
  if current ~= "" then
    lines[1+ #lines] = current
  end

  return lines
end


--- Analyse and shrink the lua SOURCESTRING by several means.
-- This function is a wrapper for the relevant parts of LuaSrcDiet, which
-- is able to determine the optimal symbol replacements autonomously by
-- parsing the lua code in a first pass.
--    @param sourcestring A valid lua chunk as a string.
-- @see llex.lua
-- @see lparser.lua
function M.luafile (sourcestring)
  local option = {
    ["opt-locals"]     = true,
    ["opt-comments"]   = true,
    ["opt-entropy"]    = true,
    ["opt-whitespace"] = true,
    ["opt-emptylines"] = true,
    ["opt-eols"]       = true,
    ["opt-strings"]    = true,
    ["opt-numbers"]    = true,
  }

  llex.init (sourcestring)
  llex.llex ()
  local tok, seminfo, tokln = llex.tok, llex.seminfo, llex.tokln

  optparser.print = print
  lparser.init (tok, seminfo, tokln)
  local globalinfo, localinfo = lparser.parser ()
  optparser.optimize (option, tok, seminfo, globalinfo, localinfo)

  optlex.print = print
  tok, seminfo, tokln = optlex.optimize (option, tok, seminfo, tokln)

  local r = table.concat (seminfo)
  if r:find ("\r\n", 1, 1) or r:find ("\n\r", 1, 1) then
    optlex.warn.mixedeol = true
  end
  return r
end

return M

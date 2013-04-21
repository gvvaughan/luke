-- Bake a lua source file into a C header file.
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

local M = {}

local LINEMAX = 1024            -- linewrap column (including \n char)

--- Convert a lua source file into a C string.
-- The returned list of lines is a C SYMBOL definition, which contains
-- all of the lua source code, suitably escaped (and line wrapped) for
-- writing to a C header file.
--   @param luastring A valid lua chunk as a string
--   @param symbol The name of the C symbol
--   @return The list of all buffered lines
function M.lua2header (luastring, symbol)
  symbol= symbol or luastring:gsub ("[^%a]", "_")

  local buffer = "static const char " .. symbol .. '[] = "' ..
                  luastring:gsub ("\\", "\\\\"):
                            gsub ("\"", "\\\""):
                            gsub ("\t", "\\t"):
                            gsub ("\n", "\\n") ..
                  '";\n'

  local max   = LINEMAX -2      -- 2 char line ending "\\" "\n"
  local lines = {}
  local start = 1
  while start < #buffer do
    local eol = ""
    local finish = start + max
    if finish > #buffer then
      finish = #buffer
    else
      eol = "\\"
    end
    while buffer:byte (finish) == string.byte "\\" do
      -- don't break the line in the middle of an escape sequence
      finish = finish -1
    end
    lines[1+ #lines] = buffer:sub (start, finish) .. eol
    start = 1+ finish
  end

  return lines
end

return M

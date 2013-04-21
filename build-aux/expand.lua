-- Expand #include "..." directives to their contents inline.
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


-- Try to find a copy of the file content in the VFS table, or else
-- the real filesystem. Return a list of lines, with trailing newline
-- characters stripped.
local function filefetch (filename, paths, vfs)
  local content, pathname

  -- If FILENAME appears as a VFS key, we have content!
  if vfs[filename] then
    content = vfs[filename]
  end

  if not content then
    -- Otherwise, try prefixing each entry in PATHS for a VFS match.
    for _, v in ipairs (paths) do
      pathname = path.join (v, filename)
      if vfs[pathname] then
        content = vfs[pathname]
        break
      end
    end
  end

  if not content then
    -- Nothing found in the VFS, search the real filesystem.
    for _, v in ipairs (paths) do
      pathname = path.join (v, filename)
      local file = io.open (pathname, "r")
      if file then
        content = file:read "*a"
        break
      end
    end
  end

  if content then
    -- Massage the content into a table of lines, and return.
    local l = {}
    if type (content) == "string" then
      if content:sub (-1) ~= "\n" then content = content .. "\n" end
      content:gsub ("([^\n]*)\n", function (s) l[1+ #l] = s end)
    elseif type (content) == "table" then
      l = content
    else
      error ("Unknown content type '" .. type (content) ..
             "' in '" .. pathname .. "'.")
    end

    return l
  end

  -- Unable to find a match.
  return nil
end


--- Return the contents of a file as a table of lines.
-- Starting with FILENAME, convert the contents into a table of lines,
-- with newlines stripped, while recursively expanding local include
-- files (#include "somefile") inline on first sighting. Appropriate
-- #line markers are injected along the way, so that compilation error
-- messages will point back to the original source file.
--
-- If you have the contents of any unexpanded files in memory already,
-- then pass them in as VFS with the filename as a key, and the file
-- contents as the value (a string or list of lines will both work),
-- and that will be used in preference to searching the actual file
-- system.
--
-- Note that system includes (#include <someheader.h>) are not expanded.
--
--   @param filename The top-level file to begin expanded
--   @param paths A list of directories to search for include files
--   @param vfs The virtual file table, keyed on filename
--   @param seen A table of header names already encountered
--   @return A table of lines after recursive #include expansion.
--   @see list.lua
function M.file (filename, paths, vfs, seen)
  local file = nil

  paths = paths or {}
  vfs   = vfs   or {}
  seen  = seen  or {}

  local linesin = filefetch (filename, paths, vfs)
  if not linesin then
    error ("could not find file '" .. filename .. "'. Tried '" ..
      table.concat (paths, "', '") .. "'.")
  end

  local linesout = {}
  local lineno   = 0
  for _, line in ipairs (linesin) do
    local s, _, name = string.find (line, '^#include "(.*)"$')
    if s then
      if not seen[name] then
        seen[name] = true
        for _, v in ipairs (M.file (name, paths, vfs, seen)) do
          linesout[1+ #linesout] = v
        end
      else
        linesout[1+ #linesout] = ""
      end
    else
      linesout[1+ #linesout] = line
    end

    lineno = 1+ lineno
  end

  return linesout
end

return M

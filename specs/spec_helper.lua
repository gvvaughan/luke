--[[
 Use the source, Luke!
 Copyright (C) 2014-2023 Gary V. Vaughan
]]

package.path = getenv 'LUA_PATH'

pack = table.pack or function(...) return {n=select('#', ...), ...} end

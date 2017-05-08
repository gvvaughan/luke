package.path = getenv 'LUA_PATH'

pack = table.pack or function(...) return {n=select('#', ...), ...} end
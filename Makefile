LUA  = lua

LUA_ENV = LUA_PATH=`pwd`'/lib/?.lua;;'


lib_SOURCES =				\
	lib/luke/_base.lua		\
	lib/luke/cli.lua		\
	lib/luke/compile.lua		\
	lib/luke/configure.lua		\
	lib/luke/environment.lua	\
	lib/luke/init.lua		\
	lib/luke/lukefile.lua		\
	lib/luke/platforms.lua		\
	lib/std/functional.lua		\
	lib/std/normalize.lua		\
	lib/type/context-manager.lua	\
	lib/type/dict.lua		\
	$(NOTHING_ELSE)

DESTDIR = .

build-aux/luke: $(lib_SOURCES)
	env $(LUA_ENV) $(LUA) lib/smush/init.lua $(lib_SOURCES) > $(DESTDIR)/build-aux/luke

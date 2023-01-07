# Use the source, Luke!
# Copyright (C) 2014-2023 Gary V. Vaughan

LUA_PATH = `pwd`'/lib/?.lua;'`pwd`'/lib/?/init.lua'
LUA_ENV  = LUA_PATH=$(LUA_PATH)';;'

LUA  = lua
SMUSH = env $(LUA_ENV) $(LUA) build-aux/smush


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
	lib/type/path.lua		\
	$(NOTHING_ELSE)

DESTDIR = .

build-aux/luke: $(lib_SOURCES)
	$(SMUSH) $(lib_SOURCES) > $(DESTDIR)/$@
	-chmod 755 $(DESTDIR)/$@


BUSTED_ENV = LUA_PATH=`pwd`'/?.lua;'$(LUA_PATH)';;'

noinst_spec_CHECKS =			\
	spec/cli_spec.lua		\
	spec/compile_spec.lua		\
	spec/configure_spec.lua		\
	spec/context-manager_spec.lua	\
	spec/environment_spec.lua	\
	spec/functional_spec.lua	\
	spec/normalize_spec.lua		\
	spec/platform_spec.lua		\
	$(NOTHING_ELSE)

check:
	env $(BUSTED_ENV) busted $(BUSTED_OPTS) -o TAP $(noinst_spec_CHECKS)

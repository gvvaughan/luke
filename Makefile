# Use the source, Luke!
# Copyright (C) 2014-2026 Gary V. Vaughan

LUA_PATH = `pwd`'/lib/?.lua;'`pwd`'/lib/?/init.lua'
LUA_ENV  = LUA_PATH=$(LUA_PATH)';;'

VERSION = 0.3

CHMOD = chmod
LUA  = lua
SED  = sed
SMUSH = env $(LUA_ENV) $(LUA) build-aux/smush


lib_SOURCES =				\
	lib/luke/_base.lua		\
	lib/luke/cli.lua		\
	lib/luke/compile.lua		\
	lib/luke/configure.lua		\
	lib/luke/environment.lua	\
	lib/luke/functional.lua		\
	lib/luke/init.lua		\
	lib/luke/lukefile.lua		\
	lib/luke/normalize.lua		\
	lib/luke/platforms.lua		\
	lib/luke/version.lua		\
	lib/type/context-manager.lua	\
	lib/type/dict.lua		\
	lib/type/path.lua		\
	$(NOTHING_ELSE)

DESTDIR = .

build-aux/luke: $(lib_SOURCES)
	$(SMUSH) $(lib_SOURCES) > $(DESTDIR)/$@
	-$(CHMOD) 755 $(DESTDIR)/$@

lib/luke/version.lua: lib/luke/version.lua.in Makefile
	@$(SED) -e 's,@VERSION@,$(VERSION),' '$<' > '$@T';		\
	if cmp -s '$@' '$@T'; then					\
	    rm -f '$@T';						\
	else								\
	    echo "$(SED) -e 's,@VERSION@,$(VERSION),' '$<' > '$@T'";	\
	    rm -f '$@';							\
	    mv -f '$@T' '$@';						\
	    $(CHMOD) 444 '$@';						\
	fi


SPECL = specl
SPECL_OPTS = -vfreport

noinst_spec_CHECKS =			\
	spec/cli_spec.yaml		\
	spec/compile_spec.yaml		\
	spec/configure_spec.yaml	\
	spec/context-manager_spec.yaml	\
	spec/environment_spec.yaml	\
	spec/functional_spec.yaml	\
	spec/normalize_spec.yaml	\
	spec/platform_spec.yaml		\
	$(NOTHING_ELSE)

check: lib/luke/version.lua
	$(SPECL) $(SPECL_OPTS) $(noinst_spec_CHECKS)

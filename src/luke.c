#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define luaall_c

#include "lapi.c"
#include "lcode.c"
#include "ldebug.c"
#include "ldo.c"
#include "ldump.c"
#include "lfunc.c"
#include "lgc.c"
#include "llex.c"
#include "lmem.c"
#include "lobject.c"
#include "lopcodes.c"
#include "lparser.c"
#include "lstate.c"
#include "lstring.c"
#include "ltable.c"
#include "ltm.c"
#include "lundump.c"
#include "lvm.c"
#include "lzio.c"

#include "lauxlib.c"
#include "lbaselib.c"
#include "ldblib.c"
#include "liolib.c"
#include "loadlib.c"
#include "loslib.c"
#include "lstrlib.c"
#include "ltablib.c"
#include "lpathlib.c"

#include "md5.c"
#include "md5lib.c"

#include "lua.h"

#include "lauxlib.h"
#include "lualib.h"
#include "luke.h"


static lua_State *globalL = NULL;

static const char *progname = LUA_PROGNAME;

static const luaL_Reg lualibs[] = {
    {"", luaopen_base},
    {LUA_LOADLIBNAME, luaopen_package},
    {LUA_TABLIBNAME, luaopen_table},
    {LUA_IOLIBNAME, luaopen_io},
    {LUA_OSLIBNAME, luaopen_os},
    {LUA_STRLIBNAME, luaopen_string},
    {LUA_DBLIBNAME, luaopen_debug},
    {"md5", luaopen_md5_core},
    {"os.path", luaopen_path},
    {NULL, NULL}
};


static void
lstop (lua_State *L, lua_Debug *ar)
{
    (void)ar;  /* unused arg. */
    lua_sethook (L, NULL, 0, 0);
    luaL_error (L, "interrupted!");
}


static void
laction (int i)
{
    signal (i, SIG_DFL); /* if another SIGINT happens before lstop,
                           terminate process (default action) */
    lua_sethook (globalL, lstop, LUA_MASKCALL|LUA_MASKRET|LUA_MASKCOUNT, 1);
}


static void
l_message (const char *pname, const char *msg)
{
    if (pname)
        fprintf (stderr, "%s: ", pname);
    fprintf (stderr, "%s\n", msg);
    fflush (stderr);
}


static int
report (lua_State *L, int status)
{
    if (status && !lua_isnil (L, -1))
      {
        const char *msg = lua_tostring (L, -1);
        if (msg == NULL)
            msg = "(error object is not a string)";
        l_message (progname, msg);
        lua_pop (L, 1);
      }
    return status;
}


static int
traceback (lua_State *L)
{
    if (!lua_isstring (L, 1))  /* 'message' not a string? */
        return 1;  /* keep it intact */
    lua_getfield (L, LUA_GLOBALSINDEX, "debug");
    if (!lua_istable (L, -1))
      {
        lua_pop (L, 1);
        return 1;
      }
    lua_getfield (L, -1, "traceback");
    if (!lua_isfunction (L, -1))
      {
        lua_pop (L, 2);
        return 1;
      }
    lua_pushvalue (L, 1);  /* pass error message */
    lua_pushinteger (L, 2);  /* skip this function and traceback */
    lua_call (L, 2, 1);  /* call debug.traceback */
    return 1;
}


static int
docall (lua_State *L, int narg, int clear)
{
    int status;
    int base = lua_gettop (L) - narg;  /* function index */
    lua_pushcfunction (L, traceback);  /* push traceback function */
    lua_insert (L, base);  /* put it under chunk and args */
    signal (SIGINT, laction);
    status = lua_pcall (L, narg, (clear ? 0 : LUA_MULTRET), base);
    signal (SIGINT, SIG_DFL);
    lua_remove (L, base);  /* remove traceback function */
    /* force a complete garbage collection in case of errors */
    if (status != 0)
        lua_gc (L, LUA_GCCOLLECT, 0);
    return status;
}


static int
getargs (lua_State *L, char **argv)
{
    int narg;
    int i;
    int argc = 0;
    while (argv[argc])
        argc++;  /* count total number of arguments */
    narg = argc - 1;  /* number of arguments to the script */
    luaL_checkstack (L, narg + 3, "too many arguments to script");
    lua_pushstring (L, "luke.lua");
    for (i=1; i < argc; i++)
        lua_pushstring (L, argv[i]);
    lua_createtable (L, narg, 2);
    for (i=0; i < argc; i++)
      {
        lua_pushstring (L, argv[i]);
        lua_rawseti (L, -2, i);
      }
    return narg;
}


static int
handle_script (lua_State *L, char **argv)
{
    int status;
    const char *fname;
    int narg = getargs (L, argv);  /* collect arguments */
    lua_setglobal (L, "arg");
#ifndef DEBUG
    status = luaL_loadstring (L, lukebuf);
#else
    status = luaL_loadfile (L, NULL);
#endif
    lua_insert (L, -(narg+1));
    if (status == 0)
        status = docall (L, narg, 0);
    else
        lua_pop (L, narg);
    return report (L, status);
}


struct Smain {
  int argc;
  char **argv;
};


static int
pmain (lua_State *L)
{
    struct Smain *s = (struct Smain *)lua_touserdata (L, 1);
    char **argv = s->argv;
    const luaL_Reg *lib;

    globalL = L;
    if (argv[0] && argv[0][0]) progname = argv[0];
    lua_gc (L, LUA_GCSTOP, 0);  /* stop collector during initialization */
    for (lib = lualibs; lib->func; lib++)
      {
        lua_pushcfunction (L, lib->func);
        lua_pushstring (L, lib->name);
        lua_call (L, 1, 0);
      }
    lua_gc (L, LUA_GCRESTART, 0);
    return handle_script (L, argv);
}


int
main (int argc, char **argv)
{
    int status;
    struct Smain s;
    lua_State *L = lua_open ();  /* create state */
    if (L == NULL)
      {
        l_message (argv[0], "cannot create state: not enough memory");
        return EXIT_FAILURE;
      }
    s.argc = argc; s.argv = argv;
    status = lua_cpcall (L, &pmain, &s);
    report (L, status);
    lua_close (L);

    return status ? EXIT_FAILURE : EXIT_SUCCESS;
}

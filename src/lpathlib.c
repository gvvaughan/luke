/* lpathlib - lua path operations for Lua 5.1

   A selection of operations on file paths expressed as strings.
   (C) 2011 Gary V. Vaughan

   lpathlib is licensed under the MIT open source license. To get the
   full license text, see the COPYING file.
*/

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#ifndef _AIX
# define _FILE_OFFSET_BITS 64 /* Linux, Solaris and HP-UX */
#else
# define _LARGE_FILES 1 /* AIX */
#endif

#define _LARGEFILE64_SOURCE


/* MANIFEST CONSTANTS */

#ifndef PATH_VERSION
#  define PATH_VERSION "unknown"
#endif
#define PATH_NAME "path"
#define PATH_FULL_VERSION PATH_NAME "-" PATH_VERSION " for " LUA_VERSION


/* HELPER FUNCTIONS */

/* File mode translation between octal codes and `rwxrwxrwx' strings,
   and between octal masks and `ugoa+-=rwx' strings. */

typedef void (*path_Selector) (lua_State *L, int i, const void *data);

static int
path_doselection (lua_State *L, int i, int n, const char *const selection[],
    path_Selector func, const void *data)
{
    if (lua_isnone (L, i) || lua_istable (L, i))
      {
        int j;
        if (lua_isnone (L, i))
            lua_createtable (L,0,n);
        else
            lua_settop (L, i);
        for (j = 0; selection[j] != NULL; j++)
          {
            func (L, j, data);
            lua_setfield (L, -2, selection[j]);
          }
        return 1;
      }
    else
      {
        int k, n = lua_gettop (L);
        for (k = i; k <= n; k++)
          {
            int j = luaL_checkoption (L, k, NULL, selection);
            func (L, j, data);
            lua_replace (L, k);
          }
        return 1+ n - i;
      }
}

#define path_doselection(L, i, selection, func, data) \
  (path_doselection) ((L), (i), sizeof(selection)/sizeof(*selection)-1, (selection), (func), (data))

static int
path_pusherror (lua_State *L, const char *info)
{
    lua_pushnil(L);
    if (info)
        lua_pushfstring(L, "%s: %s", info, strerror(errno));
    else
        lua_pushstring(L, strerror(errno));
    return 2;
}

static int
path_pushresult (lua_State *L, int result, const char *info)
{
    if (result < 0)
        return path_pusherror (L, info);
    lua_pushboolean (L, 1);
    return 1;
}


/* ====================================================== *
 * path.attributes (path [, attributename])               *
 * path.attributes (path, {attribute1, [...attributeN,]}) *
 * ====================================================== */

#include <sys/stat.h>

static const char *const
path_Sattributes[] = {
    "ino", "dev", "nlink", "uid", "gid",
    "size", "atime", "mtime", "ctime", "type",
    NULL
};

static const char *
path_filetype (mode_t m)
{
    if (S_ISREG(m)) return "file";
    else if (S_ISLNK(m)) return "link";
    else if (S_ISDIR(m)) return "directory";
    else if (S_ISCHR(m)) return "character device";
    else if (S_ISBLK(m)) return "block device";
    else if (S_ISFIFO(m)) return "fifo";
    else if (S_ISSOCK(m)) return "socket";
    else return "other";
}

static void
path_Fattributes (lua_State *L, int i, const void *data)
{
    const struct stat *s=data;
    switch (i)
      {
        case 0: lua_pushinteger (L, s->st_ino); break;
        case 1: lua_pushinteger (L, s->st_dev); break;
        case 2: lua_pushinteger (L, s->st_nlink); break;
        case 3: lua_pushinteger (L, s->st_uid); break;
        case 4: lua_pushinteger (L, s->st_gid); break;
        case 5: lua_pushinteger (L, s->st_size); break;
        case 6: lua_pushinteger (L, s->st_atime); break;
        case 7: lua_pushinteger (L, s->st_mtime); break;
        case 8: lua_pushinteger (L, s->st_ctime); break;
        case 9: lua_pushstring (L, path_filetype (s->st_mode)); break;
      }
}

static int
Pattributes (lua_State *L)
{
    struct stat s;
    const char *path = luaL_checkstring (L, 1);
    if (lstat(path,&s) == -1)
        return path_pusherror( L, path);
    return path_doselection (L, 2, path_Sattributes, path_Fattributes, &s);
}


/* ==================== *
 * path.basename (path) *
 * ==================== */

#include <libgen.h>

static int
Pbasename (lua_State *L)
{
    char buf[PATH_MAX];
    size_t len;
    const char *path = luaL_checklstring (L, 1, &len);
    if (len >= sizeof (buf))
        luaL_argerror (L, 1, "too long");
    lua_pushstring (L, basename (strcpy (buf, path)));
    return 1;
}


/* ============== *
 * path.cd (path) *
 * ============== */

/* This function changes the current working directory. */
static int
Pcd (lua_State *L)
{
    const char *path = luaL_checkstring (L, 1);
    char buf[PATH_MAX];

    /* Where are we *before* changing directories? */
    if (getcwd (buf, sizeof (buf)) == NULL)
        return path_pusherror (L, ".");

    /* Unless we're there already, change directory into path. */
    if (strcmp (path, ".") != 0)
        if (chdir (path) < 0)
            return path_pusherror (L, path);

    /* Return the previous absolute path. */
    lua_pushstring (L, buf);
    return 1;
}


/* =============== *
 * path.dir (path) *
 * =============== */

#include <dirent.h>

#define PATH_DIR_METATABLE PATH_NAME ".dir metatable"

typedef struct {
  int closed;
  DIR *dir;
} DIR_data;

/* Directory iterator. */
static int
path_dir_iter (lua_State *L)
{
    struct dirent *entry;
    DIR_data *d = luaL_checkudata (L, 1, PATH_DIR_METATABLE);

    luaL_argcheck (L, d->closed == 0, 1, "closed directory");

    while ((entry = readdir (d->dir)) != NULL)
      {
        if (!(strcmp (".", entry->d_name) && strcmp ("..", entry->d_name)))
            continue;
        lua_pushstring (L, entry->d_name);
        return 1;
      }

    /* no more entries => close directory */
    closedir (d->dir);
    d->closed = 1;
    return 0;
}


/* Closes directory iterators. */
static int
path_dir_close (lua_State *L)
{
    DIR_data *d = lua_touserdata (L, 1);

    if (!d->closed && d->dir)
        closedir (d->dir);
    d->closed = 1;
    return 0;
}


static int
path_create_dirmeta (lua_State *L)
{
    luaL_newmetatable (L, PATH_DIR_METATABLE);
    lua_pushstring (L, "__index");
    lua_newtable(L);
    lua_pushstring (L, "next");
    lua_pushcfunction (L, path_dir_iter);
    lua_settable(L, -3);
    lua_pushstring (L, "close");
    lua_pushcfunction (L, path_dir_close);
    lua_settable(L, -3);
    lua_settable (L, -3);
    lua_pushstring (L, "__gc");
    lua_pushcfunction (L, path_dir_close);
    lua_settable (L, -3);
    return 1;
}

/* Factory of directory iterators */
static int
Pdir (lua_State *L)
{
    const char *path = luaL_optstring (L, 1, ".");
    DIR_data *d;

    lua_pushcfunction (L, path_dir_iter);
    d = lua_newuserdata (L, sizeof (*d));
    d->closed = 0;
    luaL_getmetatable (L, PATH_DIR_METATABLE);
    lua_setmetatable (L, -2);

    d->dir = opendir (path);
    if (d->dir == NULL)
        return path_pusherror (L, path);

    return 2;
}


/* =================== *
 * path.dirname (path) *
 * =================== */

#include <libgen.h>

static int
Pdirname (lua_State *L)
{
    char buf[PATH_MAX];
    size_t len;
    const char *path = luaL_checklstring (L, 1, &len);
    if (len >= sizeof (buf))
        luaL_argerror (L, 1, "too long");
    lua_pushstring (L, dirname (strcpy (buf, path)));
    return 1;
}


/* ================================= *
 * path.link (old, new [, symbolic]) *
 * ================================= */

static int
Plink (lua_State *L)
{
    const char *oldpath = luaL_checkstring (L, 1);
    const char *newpath = luaL_checkstring (L, 2);
    return path_pushresult (L, 
        (lua_toboolean (L, 3) ? symlink : link) (oldpath, newpath), NULL);
}


/* ================= *
 * path.mkdir (path) *
 * ================= */

static int
Pmkdir (lua_State *L)
{
    const char *path = luaL_checkstring (L, 1);
    return path_pushresult (L, mkdir (path, 0777), path);
}


/* ==================== *
 * path.readlink (path) *
 * ==================== */

static int
Preadlink (lua_State *L)
{
    char buf[PATH_MAX];
    const char *path = luaL_checkstring (L, 1);
    int n = readlink (path, buf, sizeof (buf));

    if (n < 0)
        return path_pusherror (L, path);

    lua_pushlstring (L, buf, n);
    return 1;
}


/* =================== *
 * Register extensions *
 * =================== */

static const struct luaL_reg
lpathlib[] = {
    { "attributes", Pattributes},
    { "basename", Pbasename },
    { "cd", Pcd },
    { "dir", Pdir },
    { "dirname", Pdirname },
    { "link", Plink },
    { "mkdir", Pmkdir },
    { "readlink", Preadlink },
    { NULL, NULL },
};

LUALIB_API int
luaopen_path (lua_State *L)
{
    path_create_dirmeta (L);
    luaL_register( L, PATH_NAME, lpathlib);
    lua_pushliteral (L, PATH_FULL_VERSION);
    lua_setfield (L, -2, "_VERSION");
    return 1;
}

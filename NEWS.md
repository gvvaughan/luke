# Luke NEWS - User visible changes.

## Noteworthy changes in release ?.? (????-??-??) [?]

### New features:

  - `luarocks-build-luke` is a LuaRocks build backend for luke, released
    as a rock of its own, so that a rockspec with `build = {type = 'luke',
    ...}` builds from the recipe in its `build` table: the modules, the
    probes of `external_dependencies` and the rest of what a lukefile
    says, and the rock needs no `lukefile` or `build-aux/luke` of its own.
    The backend is one file that needs nothing else installed.

  - `smush`, which bundles luke into the single file `build-aux/luke`,
    also bundles the modules that it finds in the Lua path, by name, and
    can write a module for the bundle to return, rather than a program.

  - A repository can release more than one rock.  A `rockspec` that is a
    list releases them together, at one version.  Otherwise, a `release`
    table with a table, or just the name, for each development rockspec,
    releases them separately, each with versions of its own: `luke release
    rock=NAME version=X.Y` releases the rock NAME, to the branch
    `release-NAME-vX.Y` and the tag `NAME-vX.Y`, so that releases of
    rocks from one repository do not meet, where the `package` has
    `release-vX.Y` and `vX.Y`.

  - `smush` also bundles `NAME=PATH`, a file as the module NAME, rather
    than the module that its path makes.

  - `smush` warns of a module that a bundled module names, which is in
    the Lua path but is not bundled, such as a dependency left off the
    list, rather than leaving it to fail when the bundle runs.  A module
    that is only asked for with `pcall(require, 'name')` is optional, and
    `--external=NAME` says that the program that runs the bundle provides
    NAME.

  - What `smush` bundles is private to the file: it is found by its own
    `require`, and not in `package.preload` or `package.loaded`, and does
    not meet a module of the same name that the host program loads.

  - Templates can fill in `@LUA_VERSION@`, the version of the Lua running
    Luke, such as `5.4`, to find the directories of the modules for it.

  - The variable that holds that version is now spelled `LUA_VERSION`,
    as LuaRocks spells it.  `LUAVERSION` still works, as an alias.

  - Luke has a man page, `doc/luke.1`, which the build generates from
    `luke --help` when help2man is installed, and `luke release`
    commits.

### Bug fixes:

  - A build command that fails has its error output written once, with
    no blank line after it, where it used to be followed by one, and a
    command that fails without saying anything writes no blank line.

  - The build runs `luke --help` for the man page with the Lua that it
    builds for, rather than with whichever `lua` is first on the `PATH`,
    which may not be there at all, and so fails the install when
    help2man is installed.

  - `luke release` says why it cannot release in words that read as
    a reason, "expected that the dependencies of X are installed",
    rather than "check failed: the dependencies of X are installed",
    which read as if the check itself had failed.

  - A probe with both a singular and a plural key, such as `prog` and
    `progs`, merges them into the plural, rather than leaving the list
    with references to itself in place of the singular value.

  - A variable that refers to itself, directly or through others, is
    diagnosed when luke expands it, rather than expanding for ever.


## Noteworthy changes in release 0.6 (2026-10-20) [stable]

### New features:

  - With `check_dependencies = true` in the lukefile `release` table,
    `luke release` first checks that LuaRocks has every dependency in
    `rockspec` installed, and lists any that are missing, rather than
    failing later when the build needs one.

  - `luke release` accepts a major version number alone, such as
    `version=4`, as well as X.Y and X.Y.Z.

  - A branch table in the lukefile `release` table can have a `command`
    to run on that branch after copying, such as to remove files from
    a copied directory that should not be published.

  - `luke release` creates a local branch to publish to, such as
    `gh-pages`, from origin when there is none, as in a fresh clone,
    and fast-forwards one that is behind origin, rather than failing
    its check that the branch matches origin.


## Noteworthy changes in release 0.5 (2026-10-15) [stable]

### New features:

  - Like the rockspec `build.install.bin` table, an `install.bin` table
    maps the name of each script to install to its source, which Luke
    fills if it is a template, makes executable, and `luke install`
    copies beneath `$INST_BINDIR`.  A top-level `bin` table does the
    same for scripts that are only for use in the source tree.

  - A table entry in `bin` or `install.bin` builds a program, either by
    running its `command` with `$sources`, `$target` and its `env`, or
    by compiling and linking its C `sources`.

  - A top-level `files` table builds generated files that are neither
    executable nor installed, such as a man page made with `help2man`.

  - `luke release version=X.Y[.Z]` cuts a release, as configured by the
    lukefile `release` table: it adds the release to `NEWS.md` on the
    branch checked out, then on a new `release-vX.Y` branch, it builds
    everything, writes the release rockspec, commits generated files,
    tags the release, and copies files to each branch that the table
    names, such as `gh-pages`, filling any templates there.  `--dry-run`
    prints what it would do, and after a failed step, Luke prints the
    commands to undo the release so far.

  - Each copy to a branch named in the `release` table replaces what the
    branch has at that path, apart from its templates, so that a file
    the release no longer has goes too, and copying a directory to `.`
    publishes its contents at the root, as for LDoc output on
    `gh-pages`.

  - `--dry-run` works for every target, printing the commands that
    Luke would run and the templates it would fill, without running or
    filling any, so that `luke --dry-run install` shows where everything
    would go.

  - The `luke` rock installs `build-aux/luke` as the `luke` command,
    so that a project can run it, or copy it from the rock directory
    into place, without cloning the Luke repository.

  - `luke release` tags each release with an announcement: the
    project's summary and home page from the rockspec, the release's
    news, and how to install it with LuaRocks.  When `gh` is on the
    `PATH`, Luke also prints the `gh release create` command that
    publishes the tag as the latest GitHub release, with that
    announcement as its notes.

  - A `variables` entry can be a build-time probe, such as a
    `checkprog` that falls back to `true`, so that a release builds
    without the tool that made a committed generated file.

  - `luke release` also commits each module filled from a template,
    such as `version.lua`, so that a release can be used, or its files
    copied by hand, without building it; and removes each `.gitignore`
    line that ignores a file the release commits.

  - A `replacements` list in the `release` table edits files on the
    release branch alone, replacing each text as written with a
    template filled with the release `@version@`, in the order written,
    such as to point README badges at `release-vX.Y` rather than
    `master`.  Each file must exist and contain each text it replaces
    before the release starts.

  - `$gitref` is the abbreviated hash of the commit checked out, and
    `$abs_top_srcdir` the absolute path of the source tree, so that
    `version = '$USER/$gitref'` identifies who built an unreleased
    copy, and from which commit.

  - Wherever the lukefile takes a list of strings, such as `sources`,
    `incdirs` or `libraries`, a single string is a list of one.

### Incompatible changes:

  - A lukefile must name the format of its syntax, as `luke_format = 0`,
    which goes up by one with each incompatible change.  Luke reads
    only its own format, and stops with "lukefile format 1 needs a
    newer luke; this one reads format 0", for example, instead of
    diagnosing syntax it doesn't know.  Without `luke_format`, Luke
    diagnoses a lukefile for Luke 0.4 or earlier, whose syntax format 0
    replaces.

  - Luke checks the whole lukefile as it reads it, and diagnoses a
    malformed value at its path, as in `bad bin.prog: no sources`,
    rather than ignoring it or failing later.

  - Luke normalizes every path in the lukefile, so that `./doc/api/`
    and `doc/api` are the same, and diagnoses two entries for the same
    path spelled differently, or an empty path.

  - The list entries of the `platforms` tables that apply follow those
    of the list itself, least specific platform first, and a setting
    for a more specific platform now always replaces the same setting
    for a less specific one, or for no platform.

  - `defines` is a list, like the rockspec `defines` array, so that
    Luke passes definitions to the compiler in the order written, the
    same on every run.  Each entry is a rockspec style `'NAME'` or
    `'NAME=value'` string, or a table pairing one name with its value or
    probe, such as `{HAVE_STATVFS = {checkfunc = 'statvfs'}}`.  Luke
    diagnoses the old keyed form, and a macro defined twice in one list,
    for every platform rather than only the one it runs on.

  - `modules` is a list of tables that each pair a module name with its
    source, as in `{{['stack'] = 'lib/stack/init.lua'}}`, so that Luke
    builds and installs modules in the order written.  Luke diagnoses
    the old keyed form, and a module listed twice.

  - `bin`, `install.bin` and `files` are lists, like `modules`, of
    tables that each pair a name with its source or rules, or of
    sources on their own, so that Luke builds them in the order written.
    Luke diagnoses the old keyed form, and a name listed twice.

  - `external_dependencies` is a list, like `modules`, of tables that
    each pair a dependency name with its settings, so that Luke adds
    their compiler and linker flags in the order written.

  - A branch table in `release` is a list, like `modules`, of tables
    that each pair a path on the branch with its source, or of paths on
    their own, so that Luke copies them in the order written.

### Bug fixes:

  - Luke builds and installs in the same order on every run: modules,
    then scripts, installable scripts and generated files, which may
    run them, each in the order written.

  - Probes of the same kind run in the order they are written, the same
    on every run, after all the probes of the kinds that run before
    them.

  - A template that is a source of both a module and a script, such
    as a `version.lua.in` bundled into a single-file program, is filled
    once per run, rather than once for each.

  - A lone '@' in a template, such as in an email address, no longer
    removes the text up to the next '@'.  As with `$NAME` variables,
    only names made of word characters are expanded in `@NAME@`.

  - The hint to try `--help` after a bad option names the program
    correctly on Lua 5.1.

  - A lukefile without `package` or `version` is diagnosed, rather
    than crashing Luke.

  - A program `env` value, a define, or a release copy path containing a
    single quote, or other characters special to the shell, is quoted
    correctly in the commands Luke runs.

  - Two entries in `bin`, `install.bin`, `files` or a release branch
    table for the same name, such as an array entry named for its
    source and a key with that name, are diagnosed, rather than one
    being dropped.

  - When a `luke release` step fails while updating a branch such as
    `gh-pages`, Luke removes the temporary worktree it was updating.

  - On Lua 5.1, a message that includes nil, a boolean or a table, such
    as a diagnostic naming a missing value, no longer fails with "bad
    argument to 'format'", as Luke formats such values as later Luas
    do.

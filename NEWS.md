# Luke NEWS - User visible changes.

## Noteworthy changes in release ?.? (????-??-??) [?]

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

  - `$gitref` is the abbreviated hash of the commit checked out, and
    `$abs_top_srcdir` the absolute path of the source tree, so that
    `version = '$USER/$gitref'` identifies who built an unreleased
    copy, and from which commit.

  - Wherever the lukefile takes a list of strings, such as `sources`,
    `incdirs` or `libraries`, a single string is a list of one.

### Incompatible changes:

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

### Bug fixes:

  - Luke builds and installs in the same order on every run: modules
    in name order, and scripts before installable scripts before
    generated files, which may run them, each in name order.

  - Probes of the same kind run in the order they are written, the same
    on every run, after all the probes of the kinds that run before
    them.

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

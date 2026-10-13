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
    lukefile `release` table: it adds the release to `NEWS.md` on
    master, then on a new `release-vX.Y` branch, it builds everything,
    writes the release rockspec, commits generated files, tags the
    release, and copies files to the `gh-pages` branch, filling any
    templates there.  `--dry-run` prints what it would do.

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

### Bug fixes:

  - A lone '@' in a template, such as in an email address, no longer
    removes the text up to the next '@'.  As with `$NAME` variables,
    only names made of word characters are expanded in `@NAME@`.

  - The hint to try `--help` after a bad option names the program
    correctly on Lua 5.1.

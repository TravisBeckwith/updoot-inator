# Changelog

## [1.4.0] - 2026-07-04

### Removed
- **Deleted `update-all.sh`** — this was the old, broken v1.2.0 script (CRLF
  line endings that prevented it from even parsing, plus the escaped-`$` bugs
  fixed in 1.3.0). It was shipped alongside the fixed script by mistake.
- Merged `release-notes.md` into this file — one changelog, one source of truth.

### Fixed
- **`--check` now actually checks.** Previously `-c/--check` was just an alias
  for `--dry-run`, which only *printed* commands. Check mode now queries each
  manager for real (`apt list --upgradable`, `snap refresh --list`,
  `flatpak remote-ls --updates`, `brew outdated`, `conda update --dry-run`,
  `pip list --outdated`, `npm outdated -g`, `rustup check`,
  `cargo install-update --list`, `fwupdmgr get-updates`) without installing
  anything. `--dry-run` remains purely print-only.
- **Reliable exit statuses.** `run_cmd` no longer builds command strings and
  `eval`s them; commands are executed as argument vectors. The npm update in
  particular was piped through `grep -v EBADENGINE`, so success/failure was
  reported based on *grep's* exit code, not npm's — npm could fail and be
  reported as success, or succeed and be reported as failure. The filter now
  preserves npm's real status.
- **No more `eval` on interpolated names.** pip package names and conda
  environment paths are passed as quoted arguments, never re-parsed by the
  shell.
- **PEP 668 awareness for pip.** On externally-managed system Pythons
  (Debian 12+, Ubuntu 23.04+, Fedora 38+), pip updates are skipped with an
  explanation instead of failing on every package (or worse, being forced and
  breaking OS-managed packages). Virtualenvs and conda environments are still
  updated normally, with a note when a conda env's pip is the active one.
- **Robust conda environment enumeration.** Environments are read from
  `conda env list --json` and updated by prefix (`-p`), so path-based envs and
  prefixes containing spaces work. Base is excluded by prefix comparison —
  the old `grep -v '^base'` also wrongly excluded any env whose name started
  with "base" (e.g. `baseline`).
- **Dry-run is now side-effect-free.** `fwupdmgr refresh --force` no longer
  runs during `--dry-run`, and check mode no longer self-upgrades pip.
- **npm uses sudo only when needed.** Sudo is applied only if the global npm
  prefix isn't writable by the current user (e.g. nvm installs never sudo).
- pip self-upgrade failures now produce a warning instead of being silently
  swallowed by `|| true`.
- `print_summary` no longer assigns to `SECONDS` (a bash special variable).
- Help text and examples now say `updoot-inator`, not `update-all.sh`.
- `.gitignore` and `Changelog.md` converted to LF line endings;
  `.gitattributes` now sets `* text=auto` in addition to `*.sh text eol=lf`.

### Changed
- `install.sh` now **copies** the script to `/usr/local/bin` instead of
  symlinking into the clone directory, so deleting or moving the repo no
  longer breaks the installed command. Re-run `install.sh` after `git pull`
  to update.

## [1.3.0] - 2026-06-04

### Fixed
- **Install**: `install.sh` was looking for `updoot-inator` instead of
  `updoot-inator.sh`, causing every fresh install to fail
- **Argument parsing**: `case "\$1"` was matching the literal string `$1`
  instead of the actual argument, causing every option (`--dry-run`,
  `--help`, etc.) to return "Unknown option"
- **Variable references**: Escaped `\$` throughout functions, local
  variables, and awk commands caused broken output (e.g. `[DRY-RUN] $1`
  instead of actual descriptions)
- **Conda env detection**: `for env in $(...)` loop was glob-expanding `*`
  from conda's active-env marker into filenames in the current directory,
  causing the script to attempt updating repo files as conda environments
- **Conda path-based envs**: Environments stored by full path now use `-p`
  instead of `-n`
- **npm permissions**: `npm update -g` runs with `sudo` and suppresses
  non-actionable `EBADENGINE` warnings
- **pip failure message**: now correctly indicates the failure could be a
  build error, dependency conflict, or missing system libraries
- **CRLF line endings**: main script converted from Windows to Unix line
  endings, which was breaking shebangs on Linux
- **Execute permissions**: shell scripts now have correct execute bit set

### Other
- Added `.gitattributes` to enforce LF line endings for shell scripts
- Improved README install instructions

## [1.2.0] - 2025-07-19

### Features
- Initial public release 🎺
- Support for apt, snap, flatpak, brew, conda, pip, npm, cargo, firmware
- Dry-run mode
- Interactive mode
- Verbose output
- Logging to file
- Package list backups
- Disk usage tracking
- Reboot check
- Filter by --only and --skip
- Colorized output with --no-color option

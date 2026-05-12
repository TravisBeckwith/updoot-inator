# updoot-inator v1.3.0

## Bug Fixes

- **Fixed install**: `install.sh` was looking for `updoot-inator` instead of `updoot-inator.sh`, causing every fresh install to fail
- **Fixed argument parsing**: `case "\$1"` was matching the literal string `$1` instead of the actual argument, causing every option (`--dry-run`, `--help`, etc.) to return "Unknown option"
- **Fixed variable references**: Escaped `\$` throughout functions, local variables, and awk commands caused broken output (e.g. `[DRY-RUN] $1` instead of actual descriptions)
- **Fixed conda env detection**: `for env in $(...)` loop was glob-expanding `*` from conda's active-env marker into filenames in the current directory, causing the script to attempt updating repo files as conda environments
- **Fixed conda path-based envs**: Environments stored by full path now use `-p` instead of `-n`, fixing update failures for envs like `/home/user/miniforge3/envs/myenv`
- **Fixed npm permissions**: `npm update -g` now runs with `sudo` and suppresses non-actionable `EBADENGINE` warnings
- **Fixed pip failure message**: "dependency conflict?" was misleading — message now correctly indicates the failure could be a build error, dependency conflict, or missing system libraries
- **Fixed CRLF line endings**: All shell scripts converted from Windows to Unix line endings, which was breaking shebangs on Linux
- **Fixed execute permissions**: Shell scripts now have correct execute bit set in git

## Other Changes

- Added `.gitattributes` to enforce LF line endings for all shell scripts going forward
- Improved README install instructions

# updoot-inator v1.5.0

## Removed

- **Deleted stale `update-all.sh`**: a leftover copy of the old, broken v1.2.0 script (CRLF line endings, escaped-`$` argument-parsing bugs) had crept back into a distributed copy of the repo despite being removed in v1.4.0. `updoot-inator.sh` remains the single entry point.

## New Features

- **`--pip-exclude <pkgs>`**: comma-separated list of pip packages to skip when upgrading
- **`--no-pip-exclude-defaults`**: disables the built-in skip list below
- **Default pip skip list (`wxPython`)**: packages that routinely have no prebuilt wheel for the local platform/Python and fall back to a from-source build requiring system dev headers (e.g. GTK+ for wxPython) are now skipped by default instead of failing — and burning several minutes compiling — on every run
- **Pre-upgrade conflict check**: before upgrading each outdated pip package, `update_pip` now inspects installed packages' declared requirements to detect whether the upgrade would violate another package's pin (e.g. upgrading `docutils`/`rsa` breaking `awscli`'s pins). Conflicting upgrades are skipped and reported instead of silently applied
- **`pip check` summary**: after the pip run, any outstanding broken requirements are surfaced as a warning
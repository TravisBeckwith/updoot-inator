# updoot-inator

*"Behold, the Updoot-inator! It updoots ALL your packages!"*

![Version](https://img.shields.io/badge/version-1.6.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
[![DOI](https://zenodo.org/badge/1218353675.svg)](https://doi.org/10.5281/zenodo.20140580)

> **This is the final release of updoot-inator.** It has been merged with
> its companion, [del-doot-inator](https://github.com/TravisBeckwith/del-doot-inator),
> into [maintainctl](https://github.com/TravisBeckwith/maintainctl), which
> covers both updating and cleaning in one tool. This repo will stay up
> as-is for anyone who wants the update-only script standalone, but new
> development happens in maintainctl.

A single command to update everything on your system — apt, snap, flatpak, brew, conda, pip, npm, cargo, and firmware.

## Install

```bash
git clone https://github.com/TravisBeckwith/updoot-inator.git
cd updoot-inator
bash ./install.sh
```

Or manually:

```bash
git clone https://github.com/TravisBeckwith/updoot-inator.git
cd updoot-inator
chmod +x updoot-inator.sh
sudo install -m 0755 updoot-inator.sh /usr/local/bin/updoot-inator
```

## Usage

```bash
# Update everything
updoot-inator

# Print the commands that would run (nothing executed)
updoot-inator --dry-run

# Query each manager for available updates without installing
updoot-inator --check

# Interactive mode — prompt before each manager
updoot-inator --interactive

# Only update specific managers
updoot-inator --only apt,pip

# Skip specific managers
updoot-inator --skip conda,npm

# Skip pip packages that need a native/source build (wxPython is skipped
# by default; add more of your own)
updoot-inator --pip-exclude wxPython,some-other-package

# Full update with backups, disk usage, and reboot check
updoot-inator --backup --show-sizes --reboot-check

# Log output to file
updoot-inator --log ~/update.log

# Log with timestamp
updoot-inator --log ~/updoot-$(date +%Y-%m-%d).log

# List detected package managers
updoot-inator --list
```

## Options

| Option | Description |
| --- | --- |
| `-h, --help` | Show help message |
| `-v, --version` | Show version |
| `-n, --dry-run` | Print the commands that would run, without executing anything |
| `-i, --interactive` | Prompt before each package manager |
| `-V, --verbose` | Show detailed command output |
| `-l, --log <file>` | Log output to a file |
| `-o, --only <list>` | Only update specified managers (comma-separated) |
| `-s, --skip <list>` | Skip specified managers (comma-separated) |
| `-L, --list` | List detected package managers |
| `-c, --check` | Check for updates without installing |
| `-b, --backup` | Save package lists before updating |
| `--backup-dir <dir>` | Custom backup directory |
| `--reboot-check` | Check if reboot is needed after updates |
| `--show-sizes` | Show disk usage before/after |
| `--no-color` | Disable colored output |
| `--pip-exclude <pkgs>` | Comma-separated pip packages to skip upgrading |
| `--no-pip-exclude-defaults` | Don't skip the built-in list of pip packages known to require a native source build (currently: `wxPython`) |

## Supported Package Managers

| Manager | What it does |
| --- | --- |
| apt | update, upgrade, autoremove, autoclean |
| snap | snap refresh |
| flatpak | flatpak update |
| brew | update, upgrade, cleanup |
| conda | Updates base + all named and path-based environments |
| pip | Upgrades outdated packages individually, skipping any that would conflict with another installed package's pinned requirements or that are in the native-build exclude list (skipped on PEP 668 externally-managed system Pythons) |
| npm | npm update -g |
| cargo | rustup update + cargo install-update |
| firmware | fwupdmgr check + update |

## Uninstall

```bash
bash ./uninstall.sh
```

## Updating

```bash
cd updoot-inator
git pull
bash ./install.sh   # re-copies the new version into /usr/local/bin
```

## Release Notes

**Fixed**
- **Repeated sudo prompts**: apt, snap, and (conditionally) npm each called
  `sudo` cold, with nothing keeping the cached sudo timestamp alive in
  between. A long non-sudo step in the same run (conda solving an
  environment, pip upgrading packages one at a time) could run past sudo's
  default `timestamp_timeout`, so a later sudo-gated step prompted for the
  password again even though you'd already authenticated earlier in the
  same run. `updoot-inator` now authenticates once at the start of a run
  and refreshes the cached credential in the background for the run's
  lifetime, so this only happens once. Skipped entirely in `--dry-run`.

See [Changelog.md](Changelog.md) for the full version history.

## Successor

This repo is no longer under active development. Its functionality — and
del-doot-inator's — now lives in
[maintainctl](https://github.com/TravisBeckwith/maintainctl):

```bash
maintainctl update   # replaces: updoot-inator
maintainctl clean    # replaces: del-doot-inator
maintainctl all      # replaces: updoot-inator && del-doot-inator
```

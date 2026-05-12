# updoot-inator

*"Behold, the Updoot-inator! It updoots ALL your packages!"*

![Version](https://img.shields.io/badge/version-1.3.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20140581.svg)](https://doi.org/10.5281/zenodo.20140581)

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
sudo ln -sf "$(pwd)/updoot-inator.sh" /usr/local/bin/updoot-inator
```

## Usage

```bash
# Update everything
updoot-inator

# See what would be updated (no changes)
updoot-inator --dry-run

# Interactive mode — prompt before each manager
updoot-inator --interactive

# Only update specific managers
updoot-inator --only apt,pip

# Skip specific managers
updoot-inator --skip conda,npm

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
| `-n, --dry-run` | Show what would happen without making changes |
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

## Supported Package Managers

| Manager | What it does |
| --- | --- |
| apt | update, upgrade, autoremove, autoclean |
| snap | snap refresh |
| flatpak | flatpak update |
| brew | update, upgrade, cleanup |
| conda | Updates base + all named and path-based environments |
| pip | Upgrades all outdated packages individually |
| npm | npm update -g |
| cargo | rustup update + cargo install-update |
| firmware | fwupdmgr check + update |

## Uninstall

```bash
bash ./uninstall.sh
```

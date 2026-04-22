# updoot-inator

*"Behold, the Updoot-inator! It updoots ALL your packages!"*

A single command to update everything on your system — apt, snap, flatpak, brew, conda, pip, npm, cargo, and firmware.

## Install

```bash
git clone https://github.com/YOUR_USERNAME/updoot-inator.git
sudo ln -s $(pwd)/updoot-inator/updoot-inator /usr/local/bin/updoot-inator

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

# List detected package managers
updoot-inator --list

Options
Option	Description
-h, --help	Show help message
-v, --version	Show version
-n, --dry-run	Show what would happen without making changes
-i, --interactive	Prompt before each package manager
-V, --verbose	Show detailed command output
-l, --log <file>	Log output to a file
-o, --only <list>	Only update specified managers (comma-separated)
-s, --skip <list>	Skip specified managers (comma-separated)
-L, --list	List detected package managers
-c, --check	Check for updates without installing
-b, --backup	Save package lists before updating
--backup-dir <dir>	Custom backup directory
--reboot-check	Check if reboot is needed after updates
--show-sizes	Show disk usage before/after
--no-color	Disable colored output
Supported Package Managers
Manager	What it does
 apt	update, upgrade, autoremove, autoclean
 snap	snap refresh
 flatpak	flatpak update
 brew	update, upgrade, cleanup
 conda	Updates base + all named environments
 pip	Upgrades all outdated packages individually
 npm	npm update -g
 cargo	rustup update + cargo install-update
 firmware	fwupdmgr check + update
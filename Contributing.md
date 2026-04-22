# Contributing to updoot-inator 

Thanks for wanting to help improve the updoot-inator!

## How to Contribute

1. Fork the repo
2. Create a feature branch: `git checkout -b my-feature`
3. Make your changes
4. Test on your system: `./updoot-inator --dry-run`
5. Commit: `git commit -m "Add my feature"`
6. Push: `git push origin my-feature`
7. Open a Pull Request

## Ideas for Contributions

- Add support for more package managers (e.g., pacman, dnf, zypper, nix, gem, go)
- Improve error handling
- Add notification support (e.g., desktop notification when done)
- Scheduled/cron setup helper
- Shell completion (bash/zsh/fish)

## Guidelines

- Keep it POSIX-friendly where possible
- Test with `--dry-run` before submitting
- Update the README if adding new options or managers

## Bug Reports

Please include:
- Your OS and version
- Output of `updoot-inator --list`
- The full error output (use `--verbose --log debug.log`)
# updoot-inator v1.6.0 (final release)

This is the last release of updoot-inator as a standalone tool. Its functionality has been merged with del-doot-inator into [maintainctl](https://github.com/TravisBeckwith/maintainctl) (`maintainctl update`). This repo remains available for anyone who wants the update-only script on its own; no new features will land here.

## Fixed

- **Repeated sudo prompts**: apt, snap, and (conditionally) npm each called `sudo` cold, with nothing keeping the cached sudo timestamp alive between calls. A long non-sudo step in the same run (conda solving an environment, pip upgrading packages one at a time) could outlast sudo's default `timestamp_timeout`, causing a later sudo-gated step to prompt for the password again. Added an up-front `sudo -v` plus a background refresh every 60s for the run's lifetime (torn down on exit). Skipped entirely in `--dry-run`, since nothing is actually executed there.

## Removed

- **Deleted `update-all.sh` (again, for real this time)**: the stale orphaned copy of the old v1.2.0 script had crept back into distributed archives of the repo despite being removed in 1.4.0 and again in 1.5.0. It was never referenced by `install.sh`. `updoot-inator.sh` remains the one and only entry point.

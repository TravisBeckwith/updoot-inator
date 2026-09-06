#!/bin/bash

# =============================================================================
# updoot-inator — System-Wide Update Script
# =============================================================================

VERSION="1.6.0"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Defaults
DRY_RUN=false
CHECK_MODE=false
VERBOSE=false
LOG_FILE=""
INTERACTIVE=false
ONLY=()
SKIP=()
REBOOT_CHECK=false
SHOW_SIZES=false
BACKUP_LIST=false
BACKUP_DIR="$HOME/.update-backups"
PIP_EXCLUDE=()
# Packages that commonly require a native/source build (e.g. GUI toolkits
# needing system dev headers like GTK+) and have no prebuilt wheel on many
# platforms. Skipped by default to avoid multi-minute failing compiles;
# add more with --pip-exclude, or disable this list with
# --no-pip-exclude-defaults.
PIP_EXCLUDE_DEFAULTS=(wxPython)
USE_PIP_EXCLUDE_DEFAULTS=true

# Track results
UPDATED=()
SKIPPED=()
FAILED=()
WARNINGS=()
START_TIME=$(date +%s)

# =============================================================================
# HELP / USAGE
# =============================================================================
usage() {
    cat << 'EOF'

  ╔═══════════════════════════════════════════════════════════════════╗
  ║                          updoot-inator                            ║
  ╚═══════════════════════════════════════════════════════════════════╝

  USAGE:
      updoot-inator [OPTIONS]

  OPTIONS:
      -h, --help              Show this help message
      -v, --version           Show script version
      -n, --dry-run           Print the commands that would run (no changes,
                              nothing is executed)
      -c, --check             Actually query each manager for available
                              updates without installing anything (may
                              refresh package metadata, e.g. 'apt update')
      -i, --interactive       Prompt before each package manager update
      -V, --verbose           Show detailed output for each command
      -l, --log <file>        Log all output to a file
      -o, --only <managers>   Only update specified managers (comma-separated)
      -s, --skip <managers>   Skip specified managers (comma-separated)
      -L, --list              List all available package managers detected
      -b, --backup            Save list of installed packages before updating
      --backup-dir <dir>      Directory for backup files (default: ~/.update-backups)
      --reboot-check          Check if a reboot is required after updates
      --show-sizes            Show disk usage before and after updates
      --no-color              Disable colored output
      --pip-exclude <pkgs>    Comma-separated pip packages to skip upgrading
      --no-pip-exclude-defaults
                               Don't skip the built-in list of pip packages
                               known to require a native source build
                               (currently: wxPython)

  AVAILABLE MANAGERS:
      apt, snap, flatpak, brew, conda, pip, npm, cargo, firmware

  EXAMPLES:
      updoot-inator                           # Update everything
      updoot-inator --dry-run                 # Print what would run
      updoot-inator --check                   # Query for available updates
      updoot-inator --only apt,pip            # Only update apt and pip
      updoot-inator --skip conda,npm          # Skip conda and npm
      updoot-inator --interactive             # Ask before each manager
      updoot-inator --log ~/update.log        # Log output to file
      updoot-inator --backup --only apt       # Backup apt packages then update
      updoot-inator -n -V                     # Dry run with verbose output

EOF
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            echo "updoot-inator version $VERSION"
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -c|--check)
            CHECK_MODE=true
            shift
            ;;
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        -V|--verbose)
            VERBOSE=true
            shift
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -o|--only)
            IFS=',' read -ra ONLY <<< "$2"
            shift 2
            ;;
        -s|--skip)
            IFS=',' read -ra SKIP <<< "$2"
            shift 2
            ;;
        -L|--list)
            echo "Detected package managers:"
            for mgr in apt snap flatpak brew conda pip npm cargo firmware; do
                if command -v "$mgr" &> /dev/null || \
                   { [ "$mgr" = "firmware" ] && command -v fwupdmgr &> /dev/null; } || \
                   { [ "$mgr" = "cargo" ] && command -v rustup &> /dev/null; }; then
                    echo -e "  ${GREEN}✔ ${mgr}${NC}"
                else
                    echo -e "  ${RED}✘ ${mgr}${NC} (not installed)"
                fi
            done
            exit 0
            ;;
        -b|--backup)
            BACKUP_LIST=true
            shift
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --reboot-check)
            REBOOT_CHECK=true
            shift
            ;;
        --show-sizes)
            SHOW_SIZES=true
            shift
            ;;
        --no-color)
            GREEN='' YELLOW='' RED='' BLUE='' CYAN='' BOLD='' NC=''
            shift
            ;;
        --pip-exclude)
            IFS=',' read -ra _pip_exclude_extra <<< "$2"
            PIP_EXCLUDE+=("${_pip_exclude_extra[@]}")
            shift 2
            ;;
        --no-pip-exclude-defaults)
            USE_PIP_EXCLUDE_DEFAULTS=false
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Dry-run wins if both are given (it is the more conservative mode)
if $DRY_RUN && $CHECK_MODE; then
    CHECK_MODE=false
fi

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================
divider() {
    echo ""
    echo -e "${BLUE}=================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}=================================================================${NC}"
    echo ""
}

success()  { echo -e "${GREEN}✔ $1${NC}"; }
warn()     { echo -e "${YELLOW}⚠ $1${NC}"; WARNINGS+=("$1"); }
error()    { echo -e "${RED}✘ $1${NC}"; }
info()     { echo -e "${CYAN}ℹ $1${NC}"; }
dry_info() { echo -e "${YELLOW}[DRY-RUN] $1${NC}"; }

# Log output to file if specified
log() {
    if [ -n "$LOG_FILE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    fi
}

# Run a command (passed as separate arguments, NOT a string — no eval, so
# package/environment names can never be interpreted as shell syntax),
# or show what would run in dry-run mode.
run_cmd() {
    local description="$1"
    shift

    if $VERBOSE; then
        info "Running: $*"
    fi
    log "Running: $*"

    if $DRY_RUN; then
        dry_info "$description"
        dry_info "  → $*"
        return 0
    fi

    if $VERBOSE; then
        "$@" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"
        return "${PIPESTATUS[0]}"
    elif [ -n "$LOG_FILE" ]; then
        "$@" >> "$LOG_FILE" 2>&1
    else
        "$@"
    fi
}

# Check if a manager should be processed
should_update() {
    local manager="$1"

    # Check --only filter
    if [ ${#ONLY[@]} -gt 0 ]; then
        local found=false
        for o in "${ONLY[@]}"; do
            if [ "$o" = "$manager" ]; then
                found=true
                break
            fi
        done
        if ! $found; then
            return 1
        fi
    fi

    # Check --skip filter
    for s in "${SKIP[@]}"; do
        if [ "$s" = "$manager" ]; then
            SKIPPED+=("$manager (user skipped)")
            return 1
        fi
    done

    return 0
}

# Prompt user in interactive mode
confirm() {
    local manager="$1"
    if $INTERACTIVE; then
        echo -ne "${BOLD}Update ${manager}? [Y/n/q] ${NC}"
        read -r answer
        case "$answer" in
            [nN]) SKIPPED+=("$manager (user declined)"); return 1 ;;
            [qQ]) echo "Quitting."; exit 0 ;;
            *) return 0 ;;
        esac
    fi
    return 0
}

# Get disk usage of root filesystem
get_disk_usage() {
    df -h / | awk 'NR==2 {print $3 " used / " $2 " total (" $5 " used)"}'
}

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================
backup_packages() {
    if ! $BACKUP_LIST; then return; fi

    divider "Backing up package lists"
    mkdir -p "$BACKUP_DIR"

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')

    if command -v apt &> /dev/null; then
        dpkg --get-selections > "$BACKUP_DIR/apt_packages_$timestamp.txt" 2>/dev/null
        success "APT package list saved → $BACKUP_DIR/apt_packages_$timestamp.txt"
    fi

    if command -v snap &> /dev/null; then
        snap list > "$BACKUP_DIR/snap_packages_$timestamp.txt" 2>/dev/null
        success "Snap package list saved → $BACKUP_DIR/snap_packages_$timestamp.txt"
    fi

    if command -v flatpak &> /dev/null; then
        flatpak list > "$BACKUP_DIR/flatpak_packages_$timestamp.txt" 2>/dev/null
        success "Flatpak package list saved → $BACKUP_DIR/flatpak_packages_$timestamp.txt"
    fi

    if command -v brew &> /dev/null; then
        brew list --versions > "$BACKUP_DIR/brew_packages_$timestamp.txt" 2>/dev/null
        success "Brew package list saved → $BACKUP_DIR/brew_packages_$timestamp.txt"
    fi

    if command -v conda &> /dev/null; then
        conda list --export > "$BACKUP_DIR/conda_packages_$timestamp.txt" 2>/dev/null
        success "Conda package list saved → $BACKUP_DIR/conda_packages_$timestamp.txt"
    fi

    if command -v pip &> /dev/null; then
        pip freeze > "$BACKUP_DIR/pip_packages_$timestamp.txt" 2>/dev/null
        success "Pip package list saved → $BACKUP_DIR/pip_packages_$timestamp.txt"
    fi

    if command -v npm &> /dev/null; then
        npm list -g --depth=0 > "$BACKUP_DIR/npm_packages_$timestamp.txt" 2>/dev/null
        success "NPM package list saved → $BACKUP_DIR/npm_packages_$timestamp.txt"
    fi

    if command -v cargo &> /dev/null; then
        cargo install --list > "$BACKUP_DIR/cargo_packages_$timestamp.txt" 2>/dev/null
        success "Cargo package list saved → $BACKUP_DIR/cargo_packages_$timestamp.txt"
    fi

    echo ""
    info "All backups saved to: $BACKUP_DIR"
}

# =============================================================================
# DISK USAGE CHECK
# =============================================================================
check_disk_before() {
    if $SHOW_SIZES; then
        divider "Disk Usage (Before)"
        DISK_BEFORE=$(get_disk_usage)
        echo -e "  ${CYAN}$DISK_BEFORE${NC}"
    fi
}

check_disk_after() {
    if $SHOW_SIZES; then
        divider "Disk Usage (After)"
        DISK_AFTER=$(get_disk_usage)
        echo -e "  Before: ${YELLOW}$DISK_BEFORE${NC}"
        echo -e "  After:  ${GREEN}$DISK_AFTER${NC}"
    fi
}

# =============================================================================
# HELPER WRAPPERS
# (run_cmd executes argument vectors, so anything needing pipes or
#  redirections lives in a small named function with explicit exit status)
# =============================================================================

apt_list_upgradable() {
    apt list --upgradable 2>/dev/null
}

# npm needs sudo only when the global prefix is not writable by this user
npm_needs_sudo() {
    local prefix
    prefix=$(npm config get prefix 2>/dev/null)
    [ -n "$prefix" ] && [ ! -w "$prefix/lib/node_modules" ]
}

# Update global npm packages, hiding non-actionable EBADENGINE warnings
# while preserving npm's own exit status (the old pipe-through-grep
# approach returned grep's status instead).
npm_global_update() {
    local out status
    if npm_needs_sudo; then
        out=$(sudo npm update -g 2>&1)
    else
        out=$(npm update -g 2>&1)
    fi
    status=$?
    if [ -n "$out" ]; then
        printf '%s\n' "$out" | grep -v 'EBADENGINE' || true
    fi
    return $status
}

# npm outdated exits 1 whenever outdated packages exist; for a listing
# that is not a failure.
npm_list_outdated() {
    npm outdated -g || true
}

# Detect PEP 668 externally-managed Python (Debian 12+, Ubuntu 23.04+,
# Fedora 38+ …). In those environments 'pip install --upgrade' into the
# system interpreter is refused and force-overriding it can break the OS.
pip_is_externally_managed() {
    python3 - <<'PY' 2>/dev/null
import os, sys, sysconfig
# Inside a virtualenv → pip is safe to use
if sys.prefix != getattr(sys, "base_prefix", sys.prefix):
    sys.exit(1)
# Inside a conda env → pip belongs to conda, not the OS
if os.environ.get("CONDA_PREFIX"):
    sys.exit(1)
marker = os.path.join(sysconfig.get_path("stdlib"), "EXTERNALLY-MANAGED")
sys.exit(0 if os.path.exists(marker) else 1)
PY
}

# Enumerate conda environment prefixes (excluding base) via JSON.
# Parsing 'conda env list' text output broke on path-based envs and on
# any prefix containing spaces; JSON + python (which conda guarantees
# to exist) is robust. Base is excluded by prefix comparison instead of
# 'grep -v ^base', which also wrongly excluded envs like 'baseline'.
conda_env_prefixes() {
    local base
    base=$(conda info --base 2>/dev/null)
    conda env list --json 2>/dev/null | python3 -c '
import json, sys
base = sys.argv[1]
for p in json.load(sys.stdin).get("envs", []):
    if p and p != base:
        print(p)
' "$base" 2>/dev/null
}

fwupd_refresh() {
    fwupdmgr refresh --force 2>/dev/null || true
}

# =============================================================================
# SUDO CREDENTIAL KEEP-ALIVE
#
# apt, snap, and (conditionally) npm each call sudo cold, with nothing
# keeping the cached sudo timestamp alive in between. Non-sudo steps in the
# same run — conda solving environments, pip upgrading packages one at a
# time — can easily run longer than sudo's default timestamp_timeout
# (5-15 min depending on distro), so a later sudo call prompts for the
# password again even though you already authenticated earlier in the run.
#
# Fix: prompt once up front, then refresh the cached credential every 60s
# in the background for the lifetime of the run. Skipped entirely in
# --dry-run, since nothing is actually executed there.
# =============================================================================
SUDO_KEEPALIVE_PID=""

sudo_keepalive_start() {
    $DRY_RUN && return
    command -v sudo &> /dev/null || return

    # If this fails (no tty, no cached credential, passwordless sudo not
    # configured), just continue — individual sudo calls will prompt or
    # fail on their own, exactly as before this fix existed.
    sudo -v 2>/dev/null || return

    ( while true; do sudo -n -v 2>/dev/null; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'sudo_keepalive_stop' EXIT
}

sudo_keepalive_stop() {
    if [ -n "$SUDO_KEEPALIVE_PID" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null
        SUDO_KEEPALIVE_PID=""
    fi
}

# =============================================================================
# PACKAGE MANAGER UPDATES
# =============================================================================

update_apt() {
    if ! command -v apt &> /dev/null; then SKIPPED+=("apt"); return; fi
    if ! should_update "apt"; then return; fi
    if ! confirm "apt"; then return; fi

    divider "Updating APT packages"

    if $DRY_RUN; then
        run_cmd "Update APT package lists" sudo apt update
        run_cmd "List upgradable packages" apt_list_upgradable
        run_cmd "Upgrade APT packages" sudo apt upgrade -y
        run_cmd "Remove unused packages" sudo apt autoremove -y
        run_cmd "Clean APT cache" sudo apt autoclean
        UPDATED+=("apt (dry-run)")
    elif $CHECK_MODE; then
        run_cmd "Update APT package lists" sudo apt update
        echo -e "${CYAN}Upgradable APT packages:${NC}"
        run_cmd "List upgradable packages" apt_list_upgradable
        UPDATED+=("apt (checked)")
    else
        if run_cmd "Update APT package lists" sudo apt update && \
           run_cmd "Upgrade APT packages" sudo apt upgrade -y && \
           run_cmd "Remove unused packages" sudo apt autoremove -y && \
           run_cmd "Clean APT cache" sudo apt autoclean; then
            UPDATED+=("apt")
            success "APT update complete"
            log "APT update complete"
        else
            FAILED+=("apt")
            error "APT update failed"
            log "APT update failed"
        fi
    fi
}

update_snap() {
    if ! command -v snap &> /dev/null; then SKIPPED+=("snap"); return; fi
    if ! should_update "snap"; then return; fi
    if ! confirm "snap"; then return; fi

    divider "Updating Snap packages"

    if $DRY_RUN; then
        run_cmd "Refresh snap packages" sudo snap refresh
        UPDATED+=("snap (dry-run)")
    elif $CHECK_MODE; then
        run_cmd "List pending snap updates" snap refresh --list
        UPDATED+=("snap (checked)")
    else
        if run_cmd "Refresh snap packages" sudo snap refresh; then
            UPDATED+=("snap")
            success "Snap update complete"
        else
            FAILED+=("snap")
            error "Snap update failed"
        fi
    fi
}

update_flatpak() {
    if ! command -v flatpak &> /dev/null; then SKIPPED+=("flatpak"); return; fi
    if ! should_update "flatpak"; then return; fi
    if ! confirm "flatpak"; then return; fi

    divider "Updating Flatpak packages"

    if $DRY_RUN; then
        run_cmd "Update flatpak packages" flatpak update -y
        UPDATED+=("flatpak (dry-run)")
    elif $CHECK_MODE; then
        run_cmd "Check flatpak updates" flatpak remote-ls --updates
        UPDATED+=("flatpak (checked)")
    else
        if run_cmd "Update flatpak packages" flatpak update -y; then
            UPDATED+=("flatpak")
            success "Flatpak update complete"
        else
            FAILED+=("flatpak")
            error "Flatpak update failed"
        fi
    fi
}

update_brew() {
    if ! command -v brew &> /dev/null; then SKIPPED+=("brew"); return; fi
    if ! should_update "brew"; then return; fi
    if ! confirm "brew"; then return; fi

    divider "Updating Homebrew packages"

    if $DRY_RUN; then
        run_cmd "Update Homebrew" brew update
        run_cmd "List outdated formulae" brew outdated
        run_cmd "Upgrade Homebrew packages" brew upgrade
        run_cmd "Cleanup Homebrew" brew cleanup
        UPDATED+=("brew (dry-run)")
    elif $CHECK_MODE; then
        run_cmd "Update Homebrew" brew update
        echo -e "${CYAN}Outdated Homebrew formulae:${NC}"
        run_cmd "List outdated formulae" brew outdated
        UPDATED+=("brew (checked)")
    else
        if run_cmd "Update Homebrew" brew update && \
           run_cmd "Upgrade Homebrew packages" brew upgrade && \
           run_cmd "Cleanup Homebrew" brew cleanup; then
            UPDATED+=("brew")
            success "Homebrew update complete"
        else
            FAILED+=("brew")
            error "Homebrew update failed"
        fi
    fi
}

update_conda() {
    if ! command -v conda &> /dev/null; then SKIPPED+=("conda"); return; fi
    if ! should_update "conda"; then return; fi
    if ! confirm "conda"; then return; fi

    divider "Updating Conda environments"

    if $DRY_RUN; then
        run_cmd "Update conda itself" conda update -n base conda -y --dry-run
        run_cmd "Update all base packages" conda update -n base --all -y --dry-run
        UPDATED+=("conda-base (dry-run)")

        while IFS= read -r env; do
            run_cmd "Update conda env '$(basename "$env")'" conda update -p "$env" --all -y --dry-run
            UPDATED+=("conda-$(basename "$env") (dry-run)")
        done < <(conda_env_prefixes)
    elif $CHECK_MODE; then
        run_cmd "Check conda base updates" conda update -n base --all -y --dry-run
        UPDATED+=("conda-base (checked)")

        while IFS= read -r env; do
            run_cmd "Check conda env '$(basename "$env")'" conda update -p "$env" --all -y --dry-run
            UPDATED+=("conda-$(basename "$env") (checked)")
        done < <(conda_env_prefixes)
    else
        # Update conda itself
        if run_cmd "Update conda" conda update -n base conda -y; then
            success "Conda self-update complete"
        else
            warn "Conda self-update had issues"
        fi

        # Update base environment
        if run_cmd "Update base packages" conda update -n base --all -y; then
            UPDATED+=("conda-base")
            success "Conda base environment update complete"
        else
            FAILED+=("conda-base")
            error "Conda base environment update failed"
        fi

        # Update other environments (by prefix, so path-based envs and
        # prefixes containing spaces are handled correctly)
        while IFS= read -r env; do
            local name
            name=$(basename "$env")
            echo -e "${YELLOW}Updating conda env: ${name} (${env})${NC}"
            if $INTERACTIVE; then
                echo -ne "${BOLD}Update conda env '${name}'? [Y/n] ${NC}"
                read -r answer
                if [[ "$answer" =~ ^[nN] ]]; then
                    SKIPPED+=("conda-$name (user declined)")
                    continue
                fi
            fi
            if run_cmd "Update conda env '$name'" conda update -p "$env" --all -y; then
                UPDATED+=("conda-$name")
                success "Conda env '$name' updated"
            else
                FAILED+=("conda-$name")
                error "Conda env '$name' update failed"
            fi
        done < <(conda_env_prefixes)
    fi
}

is_pip_excluded() {
    local pkg="$1" excluded
    for excluded in "${PIP_EXCLUDE[@]}"; do
        [[ "${pkg,,}" == "${excluded,,}" ]] && return 0
    done
    if $USE_PIP_EXCLUDE_DEFAULTS; then
        for excluded in "${PIP_EXCLUDE_DEFAULTS[@]}"; do
            [[ "${pkg,,}" == "${excluded,,}" ]] && return 0
        done
    fi
    return 1
}

# Checks whether upgrading pkg ($1) to version ($2) would violate another
# installed package's pinned requirement, without installing anything.
# pip's own "dependency resolver" conflict warning only appears *after* it
# has already performed the upgrade, which is too late to prevent it — so
# this inspects installed packages' declared requirements directly instead.
# Prints the conflicting requirement line(s) on stdout.
# Exit codes: 0 = no conflict, 1 = conflict found, 2 = could not determine
# (e.g. no usable requirement-parsing library available) — callers should
# treat 2 the same as "no conflict" rather than blocking the upgrade.
pip_would_conflict() {
    local pkg="$1" target="$2"
    python3 - "$pkg" "$target" <<'PYEOF'
import sys
try:
    from importlib import metadata
except ImportError:
    sys.exit(2)
try:
    from packaging.requirements import Requirement
    from packaging.utils import canonicalize_name
except ImportError:
    try:
        from pip._vendor.packaging.requirements import Requirement
        from pip._vendor.packaging.utils import canonicalize_name
    except ImportError:
        sys.exit(2)

pkg, target = sys.argv[1], sys.argv[2]
pkg_norm = canonicalize_name(pkg)
conflicts = []
for dist in metadata.distributions():
    try:
        name = dist.metadata['Name']
        reqs = dist.requires or []
    except Exception:
        continue
    if not name:
        continue
    for r in reqs:
        try:
            req = Requirement(r)
        except Exception:
            continue
        if req.marker is not None:
            try:
                if not req.marker.evaluate():
                    continue
            except Exception:
                pass
        if canonicalize_name(req.name) == pkg_norm and req.specifier and not req.specifier.contains(target, prereleases=True):
            conflicts.append(f"{name} requires {pkg}{req.specifier}, but you have {pkg} {target} which is incompatible.")

if conflicts:
    print("\n".join(conflicts))
    sys.exit(1)
sys.exit(0)
PYEOF
}

update_pip() {
    if ! command -v pip &> /dev/null; then SKIPPED+=("pip"); return; fi
    if ! should_update "pip"; then return; fi
    if ! confirm "pip"; then return; fi

    divider "Updating pip packages"

    # PEP 668: refuse to fight the OS package manager for its Python
    if pip_is_externally_managed; then
        warn "System Python is externally managed (PEP 668) — skipping pip."
        info "Use a virtualenv, pipx, or your distro's packages instead."
        SKIPPED+=("pip (externally-managed environment)")
        return
    fi

    if [ -n "$CONDA_PREFIX" ]; then
        info "Note: a conda environment is active — 'pip' here operates inside '$CONDA_PREFIX'."
    fi

    if $DRY_RUN; then
        run_cmd "Upgrade pip" pip install --upgrade pip
        dry_info "Would list outdated pip packages and upgrade each one"
        if $USE_PIP_EXCLUDE_DEFAULTS && [ ${#PIP_EXCLUDE_DEFAULTS[@]} -gt 0 ]; then
            dry_info "Would skip (default excludes): ${PIP_EXCLUDE_DEFAULTS[*]}"
        fi
        [ ${#PIP_EXCLUDE[@]} -gt 0 ] && dry_info "Would skip (--pip-exclude): ${PIP_EXCLUDE[*]}"
        UPDATED+=("pip (dry-run)")
        return
    fi

    # Upgrade pip itself (skipped in check mode — check installs nothing)
    if ! $CHECK_MODE; then
        if ! run_cmd "Upgrade pip" pip install --upgrade pip; then
            warn "pip self-upgrade failed — continuing with current version"
        fi
    fi

    # Get outdated packages (name + latest available version)
    OUTDATED=$(pip list --outdated --format=columns 2>/dev/null | awk 'NR>2 {print $1, $3}')

    if [ -z "$OUTDATED" ]; then
        success "All pip packages are up to date"
        UPDATED+=("pip")
        return
    fi

    echo -e "${CYAN}Outdated pip packages:${NC}"
    pip list --outdated --format=columns 2>/dev/null
    echo ""

    if $CHECK_MODE; then
        UPDATED+=("pip (checked)")
        return
    fi

    PIP_FAILED=0
    PIP_SUCCESS=0
    PIP_SKIPPED=0
    while IFS=' ' read -r pkg target; do
        [ -z "$pkg" ] && continue

        if is_pip_excluded "$pkg"; then
            info "Skipped $pkg (excluded — often needs a native/source build; use --no-pip-exclude-defaults or --pip-exclude to change this)"
            PIP_SKIPPED=$((PIP_SKIPPED + 1))
            continue
        fi

        if $INTERACTIVE; then
            echo -ne "${BOLD}Upgrade ${pkg}? [Y/n] ${NC}"
            read -r answer
            if [[ "$answer" =~ ^[nN] ]]; then
                info "Skipped $pkg"
                continue
            fi
        fi

        if [ -n "$target" ]; then
            conflict_report=$(pip_would_conflict "$pkg" "$target")
            conflict_rc=$?
            if [ $conflict_rc -eq 1 ]; then
                warn "Skipping $pkg: upgrading to $target would break an installed package's requirements"
                echo -e "${YELLOW}${conflict_report}${NC}"
                PIP_FAILED=$((PIP_FAILED + 1))
                continue
            fi
        fi

        echo -e "${YELLOW}Upgrading: ${pkg}${NC}"
        if run_cmd "Upgrade $pkg" pip install --upgrade "$pkg"; then
            success "$pkg upgraded"
            PIP_SUCCESS=$((PIP_SUCCESS + 1))
        else
            warn "Failed to upgrade $pkg (build error, dependency conflict, or missing system libs — run: pip install --upgrade $pkg for details)"
            PIP_FAILED=$((PIP_FAILED + 1))
        fi
    done <<< "$OUTDATED"

    # Catch anything still broken after the run (e.g. from prior upgrades
    # outside this script).
    local check_output
    if ! check_output=$(pip check 2>&1); then
        warn "pip check reports outstanding dependency problems:"
        echo -e "${YELLOW}${check_output}${NC}"
    fi

    if [ $PIP_FAILED -eq 0 ]; then
        UPDATED+=("pip ($PIP_SUCCESS upgraded, $PIP_SKIPPED skipped)")
        success "All eligible pip packages upgraded ($PIP_SKIPPED skipped)"
    else
        UPDATED+=("pip ($PIP_SUCCESS upgraded, $PIP_SKIPPED skipped, $PIP_FAILED failed/conflicting)")
        warn "Some pip packages failed or were skipped due to conflicts ($PIP_FAILED)"
    fi
}

update_npm() {
    if ! command -v npm &> /dev/null; then SKIPPED+=("npm"); return; fi
    if ! should_update "npm"; then return; fi
    if ! confirm "npm"; then return; fi

    divider "Updating global NPM packages"

    if $DRY_RUN; then
        run_cmd "Update global NPM packages" npm update -g
        UPDATED+=("npm (dry-run)")
    elif $CHECK_MODE; then
        echo -e "${CYAN}Outdated global NPM packages:${NC}"
        run_cmd "List outdated global NPM packages" npm_list_outdated
        UPDATED+=("npm (checked)")
    else
        if run_cmd "Update global NPM packages" npm_global_update; then
            UPDATED+=("npm")
            success "NPM global update complete"
        else
            FAILED+=("npm")
            error "NPM global update failed"
        fi
    fi
}

update_cargo() {
    if ! command -v cargo &> /dev/null && ! command -v rustup &> /dev/null; then
        SKIPPED+=("cargo")
        return
    fi
    if ! should_update "cargo"; then return; fi
    if ! confirm "cargo"; then return; fi

    divider "Updating Rust toolchain"

    if command -v rustup &> /dev/null; then
        if $DRY_RUN; then
            run_cmd "Update Rust toolchain" rustup update
            UPDATED+=("rustup (dry-run)")
        elif $CHECK_MODE; then
            run_cmd "Check Rust toolchain updates" rustup check
            UPDATED+=("rustup (checked)")
        else
            if run_cmd "Update Rust toolchain" rustup update; then
                UPDATED+=("rustup")
                success "Rust toolchain updated"
            else
                FAILED+=("rustup")
                error "Rust toolchain update failed"
            fi
        fi
    fi

    if command -v cargo &> /dev/null; then
        if command -v cargo-install-update &> /dev/null; then
            if $DRY_RUN; then
                run_cmd "Update cargo packages" cargo install-update -a
                UPDATED+=("cargo (dry-run)")
            elif $CHECK_MODE; then
                run_cmd "Check cargo package updates" cargo install-update -a --list
                UPDATED+=("cargo (checked)")
            else
                if run_cmd "Update cargo packages" cargo install-update -a; then
                    UPDATED+=("cargo")
                    success "Cargo packages updated"
                else
                    FAILED+=("cargo")
                fi
            fi
        else
            warn "Install 'cargo-update' for auto-updates: cargo install cargo-update"
            SKIPPED+=("cargo-packages (cargo-update not installed)")
        fi
    fi
}

update_firmware() {
    if ! command -v fwupdmgr &> /dev/null; then SKIPPED+=("firmware"); return; fi
    if ! should_update "firmware"; then return; fi
    if ! confirm "firmware"; then return; fi

    divider "Checking for firmware updates"

    if $DRY_RUN; then
        run_cmd "Refresh firmware metadata" fwupd_refresh
        run_cmd "Check firmware updates" fwupdmgr get-updates
        UPDATED+=("firmware (dry-run)")
    elif $CHECK_MODE; then
        fwupd_refresh
        if run_cmd "Check firmware updates" fwupdmgr get-updates; then
            warn "Firmware updates available. Run manually: sudo fwupdmgr update"
        else
            success "Firmware is up to date"
        fi
        UPDATED+=("firmware (checked)")
    else
        fwupd_refresh
        if fwupdmgr get-updates 2>/dev/null; then
            echo ""
            if $INTERACTIVE; then
                echo -ne "${BOLD}Install firmware updates? [y/N] ${NC}"
                read -r answer
                if [[ "$answer" =~ ^[yY] ]]; then
                    run_cmd "Install firmware" sudo fwupdmgr update
                else
                    info "Firmware update skipped by user"
                fi
            else
                warn "Firmware updates available. Run manually: sudo fwupdmgr update"
            fi
            UPDATED+=("firmware (checked)")
        else
            success "Firmware is up to date"
            UPDATED+=("firmware")
        fi
    fi
}

# =============================================================================
# REBOOT CHECK
# =============================================================================
check_reboot() {
    if ! $REBOOT_CHECK; then return; fi

    divider "Reboot Check"

    if [ -f /var/run/reboot-required ]; then
        warn "A system reboot is required!"
        if [ -f /var/run/reboot-required.pkgs ]; then
            echo -e "${YELLOW}Packages requiring reboot:${NC}"
            cat /var/run/reboot-required.pkgs
        fi
    else
        success "No reboot required"
    fi
}

# =============================================================================
# SUMMARY
# =============================================================================
print_summary() {
    local end_time elapsed mins secs
    end_time=$(date +%s)
    elapsed=$((end_time - START_TIME))
    mins=$((elapsed / 60))
    secs=$((elapsed % 60))

    divider "UPDATE SUMMARY"

    if $DRY_RUN; then
        echo -e "  ${YELLOW}${BOLD}*** DRY RUN — No changes were made ***${NC}"
        echo ""
    elif $CHECK_MODE; then
        echo -e "  ${YELLOW}${BOLD}*** CHECK MODE — Nothing was installed ***${NC}"
        echo ""
    fi

    if [ ${#UPDATED[@]} -gt 0 ]; then
        echo -e "${GREEN}${BOLD}Updated:${NC}"
        for item in "${UPDATED[@]}"; do
            echo -e "  ${GREEN}✔ ${item}${NC}"
        done
        echo ""
    fi

    if [ ${#SKIPPED[@]} -gt 0 ]; then
        echo -e "${YELLOW}${BOLD}Skipped:${NC}"
        for item in "${SKIPPED[@]}"; do
            echo -e "  ${YELLOW}– ${item}${NC}"
        done
        echo ""
    fi

    if [ ${#FAILED[@]} -gt 0 ]; then
        echo -e "${RED}${BOLD}Failed:${NC}"
        for item in "${FAILED[@]}"; do
            echo -e "  ${RED}✘ ${item}${NC}"
        done
        echo ""
    fi

    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo -e "${YELLOW}${BOLD}Warnings:${NC}"
        for item in "${WARNINGS[@]}"; do
            echo -e "  ${YELLOW}⚠ ${item}${NC}"
        done
        echo ""
    fi

    echo -e "${CYAN}Time elapsed: ${mins}m ${secs}s${NC}"

    if [ -n "$LOG_FILE" ]; then
        echo -e "${CYAN}Full log saved to: ${LOG_FILE}${NC}"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}All done!${NC}"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    if $DRY_RUN; then
        echo ""
        echo -e "${YELLOW}${BOLD}══════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}${BOLD}  DRY RUN MODE — No changes will be made${NC}"
        echo -e "${YELLOW}${BOLD}══════════════════════════════════════════════════${NC}"
    elif $CHECK_MODE; then
        echo ""
        echo -e "${YELLOW}${BOLD}══════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}${BOLD}  CHECK MODE — Querying for updates, installing nothing${NC}"
        echo -e "${YELLOW}${BOLD}══════════════════════════════════════════════════${NC}"
    fi

    if [ -n "$LOG_FILE" ]; then
        echo "Update started at $(date)" > "$LOG_FILE"
        info "Logging to: $LOG_FILE"
    fi

    # Prime + keep the sudo credential alive for the whole run so a long
    # non-sudo step (conda solving, pip upgrading packages one at a time)
    # can't let the timestamp expire and force a second password prompt.
    sudo_keepalive_start

    check_disk_before
    backup_packages

    update_apt
    update_snap
    update_flatpak
    update_brew
    update_conda
    update_pip
    update_npm
    update_cargo
    update_firmware

    sudo_keepalive_stop

    check_disk_after
    check_reboot
    print_summary
}

main

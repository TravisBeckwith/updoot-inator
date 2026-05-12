#!/bin/bash

# =============================================================================
# System-Wide Update Script
# =============================================================================

VERSION="1.2.0"

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
VERBOSE=false
LOG_FILE=""
INTERACTIVE=false
ONLY=()
SKIP=()
PARALLEL=false
REBOOT_CHECK=false
SHOW_SIZES=false
BACKUP_LIST=false
BACKUP_DIR="$HOME/.update-backups"

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
  ║                   System-Wide Update Script                      ║
  ╚═══════════════════════════════════════════════════════════════════╝

  USAGE:
      update-all.sh [OPTIONS]

  OPTIONS:
      -h, --help              Show this help message
      -v, --version           Show script version
      -n, --dry-run           Show what would be updated without making changes
      -i, --interactive       Prompt before each package manager update
      -V, --verbose           Show detailed output for each command
      -l, --log <file>        Log all output to a file
      -o, --only <managers>   Only update specified managers (comma-separated)
      -s, --skip <managers>   Skip specified managers (comma-separated)
      -L, --list              List all available package managers detected
      -c, --check             Check for updates without installing (like dry-run)
      -b, --backup            Save list of installed packages before updating
      --backup-dir <dir>      Directory for backup files (default: ~/.update-backups)
      --reboot-check          Check if a reboot is required after updates
      --show-sizes            Show disk usage before and after updates
      --no-color              Disable colored output

  AVAILABLE MANAGERS:
      apt, snap, flatpak, brew, conda, pip, npm, cargo, firmware

  EXAMPLES:
      update-all.sh                           # Update everything
      update-all.sh --dry-run                 # See what would be updated
      update-all.sh --only apt,pip            # Only update apt and pip
      update-all.sh --skip conda,npm          # Skip conda and npm
      update-all.sh --interactive             # Ask before each manager
      update-all.sh --log ~/update.log        # Log output to file
      update-all.sh --backup --only apt       # Backup apt packages then update
      update-all.sh -n -V                     # Dry run with verbose output
      update-all.sh --check                   # Just check what's outdated

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
            echo "update-all.sh version $VERSION"
            exit 0
            ;;
        -n|--dry-run|--check|-c)
            DRY_RUN=true
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
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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

# Run a command or show what would run in dry-run mode
run_cmd() {
    local description="$1"
    shift
    local cmd="$*"

    if $VERBOSE; then
        info "Running: $cmd"
    fi
    log "Running: $cmd"

    if $DRY_RUN; then
        dry_info "$description"
        dry_info "  → $cmd"
        return 0
    else
        if $VERBOSE; then
            eval "$cmd" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"
        elif [ -n "$LOG_FILE" ]; then
            eval "$cmd" >> "$LOG_FILE" 2>&1
        else
            eval "$cmd" 2>&1
        fi
        return ${PIPESTATUS[0]}
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

# Get disk usage of common paths
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
# PACKAGE MANAGER UPDATES
# =============================================================================

update_apt() {
    if ! command -v apt &> /dev/null; then SKIPPED+=("apt"); return; fi
    if ! should_update "apt"; then return; fi
    if ! confirm "apt"; then return; fi

    divider "Updating APT packages"

    if $DRY_RUN; then
        run_cmd "Update APT package lists" "sudo apt update"
        run_cmd "List upgradable packages" "apt list --upgradable 2>/dev/null"
        run_cmd "Upgrade APT packages" "sudo apt upgrade -y"
        run_cmd "Remove unused packages" "sudo apt autoremove -y"
        run_cmd "Clean APT cache" "sudo apt autoclean"
        UPDATED+=("apt (dry-run)")
    else
        if run_cmd "Update APT package lists" "sudo apt update" && \
           run_cmd "Upgrade APT packages" "sudo apt upgrade -y" && \
           run_cmd "Remove unused packages" "sudo apt autoremove -y" && \
           run_cmd "Clean APT cache" "sudo apt autoclean"; then
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
        run_cmd "Refresh snap packages" "sudo snap refresh"
        UPDATED+=("snap (dry-run)")
    else
        if run_cmd "Refresh snap packages" "sudo snap refresh"; then
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
        run_cmd "Check flatpak updates" "flatpak remote-ls --updates"
        UPDATED+=("flatpak (dry-run)")
    else
        if run_cmd "Update flatpak packages" "flatpak update -y"; then
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
        run_cmd "Update Homebrew" "brew update"
        run_cmd "List outdated formulae" "brew outdated"
        run_cmd "Upgrade Homebrew packages" "brew upgrade"
        run_cmd "Cleanup Homebrew" "brew cleanup"
        UPDATED+=("brew (dry-run)")
    else
        if run_cmd "Update Homebrew" "brew update" && \
           run_cmd "Upgrade Homebrew packages" "brew upgrade" && \
           run_cmd "Cleanup Homebrew" "brew cleanup"; then
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

    divider "Updating Conda (base environment)"

    if $DRY_RUN; then
        run_cmd "Update conda itself" "conda update -n base conda -y --dry-run"
        run_cmd "Update all base packages" "conda update -n base --all -y --dry-run"
        UPDATED+=("conda-base (dry-run)")

        while IFS= read -r env; do
            run_cmd "Update conda env '$env'" "conda update -n $env --all -y --dry-run"
            UPDATED+=("conda-$env (dry-run)")
        done < <(conda env list | grep -v '^#' | grep -v '^base' | grep -v '^ *[*]' | awk '{print $1}' | grep -v '^$')
    else
        # Update conda itself
        if run_cmd "Update conda" "conda update -n base conda -y"; then
            success "Conda self-update complete"
        else
            warn "Conda self-update had issues"
        fi

        # Update base environment
        if run_cmd "Update base packages" "conda update -n base --all -y"; then
            UPDATED+=("conda-base")
            success "Conda base environment update complete"
        else
            FAILED+=("conda-base")
            error "Conda base environment update failed"
        fi

        # Update other environments
        while IFS= read -r env; do
            echo -e "${YELLOW}Updating conda env: ${env}${NC}"
            if $INTERACTIVE; then
                echo -ne "${BOLD}Update conda env '${env}'? [Y/n] ${NC}"
                read -r answer
                if [[ "$answer" =~ ^[nN] ]]; then
                    SKIPPED+=("conda-$env (user declined)")
                    continue
                fi
            fi
            if run_cmd "Update conda env '$env'" "conda update -n $env --all -y"; then
                UPDATED+=("conda-$env")
                success "Conda env '$env' updated"
            else
                FAILED+=("conda-$env")
                error "Conda env '$env' update failed"
            fi
        done < <(conda env list | grep -v '^#' | grep -v '^base' | grep -v '^ *[*]' | awk '{print $1}' | grep -v '^$')
    fi
}

update_pip() {
    if ! command -v pip &> /dev/null; then SKIPPED+=("pip"); return; fi
    if ! should_update "pip"; then return; fi
    if ! confirm "pip"; then return; fi

    divider "Updating pip packages"

    # Upgrade pip itself
    run_cmd "Upgrade pip" "pip install --upgrade pip" 2>/dev/null || true

    # Get outdated packages
    OUTDATED=$(pip list --outdated --format=columns 2>/dev/null | awk 'NR>2 {print $1}')

    if [ -z "$OUTDATED" ]; then
        success "All pip packages are up to date"
        UPDATED+=("pip")
        return
    fi

    echo -e "${CYAN}Outdated pip packages:${NC}"
    pip list --outdated --format=columns 2>/dev/null
    echo ""

    if $DRY_RUN; then
        for pkg in $OUTDATED; do
            dry_info "Would upgrade: $pkg"
        done
        UPDATED+=("pip (dry-run)")
        return
    fi

    PIP_FAILED=0
    PIP_SUCCESS=0
    for pkg in $OUTDATED; do
        if $INTERACTIVE; then
            echo -ne "${BOLD}Upgrade ${pkg}? [Y/n] ${NC}"
            read -r answer
            if [[ "$answer" =~ ^[nN] ]]; then
                info "Skipped $pkg"
                continue
            fi
        fi

        echo -e "${YELLOW}Upgrading: ${pkg}${NC}"
        if run_cmd "Upgrade $pkg" "pip install --upgrade $pkg"; then
            success "$pkg upgraded"
            PIP_SUCCESS=$((PIP_SUCCESS + 1))
        else
            warn "Failed to upgrade $pkg (dependency conflict?)"
            PIP_FAILED=$((PIP_FAILED + 1))
        fi
    done

    if [ $PIP_FAILED -eq 0 ]; then
        UPDATED+=("pip ($PIP_SUCCESS packages)")
        success "All pip packages upgraded"
    else
        UPDATED+=("pip ($PIP_SUCCESS upgraded, $PIP_FAILED failed)")
        warn "Some pip packages failed ($PIP_FAILED failures)"
    fi
}

update_npm() {
    if ! command -v npm &> /dev/null; then SKIPPED+=("npm"); return; fi
    if ! should_update "npm"; then return; fi
    if ! confirm "npm"; then return; fi

    divider "Updating global NPM packages"

    if $DRY_RUN; then
        run_cmd "List outdated global NPM packages" "npm outdated -g"
        UPDATED+=("npm (dry-run)")
    else
        if run_cmd "Update global NPM packages" "npm update -g"; then
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
            run_cmd "Update Rust toolchain" "rustup check"
            UPDATED+=("rustup (dry-run)")
        else
            if run_cmd "Update Rust toolchain" "rustup update"; then
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
                run_cmd "Check cargo package updates" "cargo install-update -a --list"
                UPDATED+=("cargo (dry-run)")
            else
                if run_cmd "Update cargo packages" "cargo install-update -a"; then
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

    fwupdmgr refresh --force 2>/dev/null || true

    if $DRY_RUN; then
        run_cmd "Check firmware updates" "fwupdmgr get-updates 2>/dev/null || echo 'No firmware updates available'"
        UPDATED+=("firmware (dry-run)")
    else
        if fwupdmgr get-updates 2>/dev/null; then
            echo ""
            if $INTERACTIVE; then
                echo -ne "${BOLD}Install firmware updates? [y/N] ${NC}"
                read -r answer
                if [[ "$answer" =~ ^[yY] ]]; then
                    run_cmd "Install firmware" "sudo fwupdmgr update"
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
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    MINUTES=$((ELAPSED / 60))
    SECONDS=$((ELAPSED % 60))

    divider "UPDATE SUMMARY"

    if $DRY_RUN; then
        echo -e "  ${YELLOW}${BOLD}*** DRY RUN — No changes were made ***${NC}"
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

    echo -e "${CYAN}Time elapsed: ${MINUTES}m ${SECONDS}s${NC}"

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
    fi

    if [ -n "$LOG_FILE" ]; then
        echo "Update started at $(date)" > "$LOG_FILE"
        info "Logging to: $LOG_FILE"
    fi

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

    check_disk_after
    check_reboot
    print_summary
}

main
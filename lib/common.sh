# Shared helpers for dotfiles setup scripts.
# Source this file: . "<dotfiles>/lib/common.sh"

# --- Colored logging --------------------------------------------------------
# Colors only when stdout is a terminal and NO_COLOR is unset.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$(printf '\033[0m')
    C_BOLD=$(printf '\033[1m')
    C_GREEN=$(printf '\033[32m')
    C_CYAN=$(printf '\033[36m')
    C_YELLOW=$(printf '\033[33m')
    C_DIM=$(printf '\033[2m')
else
    C_RESET= C_BOLD= C_GREEN= C_CYAN= C_YELLOW= C_DIM=
fi

section()  { echo; echo "${C_BOLD}${C_CYAN}==> $1${C_RESET}"; }
log_ok()   { echo "${C_GREEN}ok:${C_RESET}   $1"; }
log_link() { echo "${C_CYAN}link:${C_RESET} $1"; }
log_move() { echo "${C_YELLOW}move:${C_RESET} $1"; }
log_skip() { echo "${C_DIM}skip: $1${C_RESET}"; }
log_warn() { echo "${C_YELLOW}warn:${C_RESET} $1"; }

# --- Symlinking -------------------------------------------------------------
# Create a symlink dest -> src, backing up any existing target first.
link() {
    src="$1"
    dest="$2"

    if [ ! -e "$src" ]; then
        log_skip "$src does not exist in dotfiles"
        return
    fi

    if [ -L "$dest" ]; then
        current="$(readlink "$dest")"
        if [ "$current" = "$src" ]; then
            log_ok "$dest -> $src (already linked)"
            return
        fi
        ts="$(date +%Y%m%d-%H%M%S)"
        log_move "existing symlink $dest -> $current => $dest.backup.$ts"
        mv "$dest" "$dest.backup.$ts"
    elif [ -e "$dest" ]; then
        ts="$(date +%Y%m%d-%H%M%S)"
        log_move "existing $dest => $dest.backup.$ts"
        mv "$dest" "$dest.backup.$ts"
    fi

    ln -s "$src" "$dest"
    log_link "$dest -> $src"
}

# --- Packages ---------------------------------------------------------------
# Version of an installed package; empty when it is not installed, including
# when only its config files remain (where dpkg -s still succeeds).
pkg_version() {
    dpkg-query -W -f='${db:Status-Status} ${Version}' "$1" 2>/dev/null \
        | sed -n 's/^installed //p'
}

# Refresh the apt lists unless apt touched its cache in the last 10 minutes,
# so a full setup run does not repeat this for every module (needs sudo).
apt_update() {
    if [ -n "$(find /var/cache/apt/pkgcache.bin -mmin -10 2>/dev/null)" ]; then
        return
    fi
    sudo apt-get update
}

apt_versions() {
    for pkg in "$@"; do
        printf '%s=%s ' "$pkg" "$(pkg_version "$pkg")"
    done
}

# Install the given apt packages and move the installed ones to the newest
# version in the apt sources (needs sudo).
ensure_apt_packages() {
    apt_update
    before="$(apt_versions "$@")"
    sudo apt-get install -y "$@"
    after="$(apt_versions "$@")"
    if [ "$before" = "$after" ]; then
        log_ok "$* (already newest)"
    else
        log_ok "now ${after% }"
    fi
}

# --- PATH -------------------------------------------------------------------
# Make sure ~/.local/bin exists and is on PATH for this process. CLI installers
# check PATH and otherwise append their own export lines to ~/.bashrc, which is
# a symlink into this repo. ~/.profile already adds ~/.local/bin at login.
ensure_local_bin_in_path() {
    mkdir -p "$HOME/.local/bin"
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;
    esac
}

# --- Debian packages --------------------------------------------------------
# Install pkg from the .deb at url with apt (which resolves dependencies).
# With latest given, an installed pkg is upgraded when it is older than that;
# without it, an installed pkg is left alone. The download is made
# world-readable so apt's sandboxed _apt user can open it.
install_deb_from_url() {
    deb_pkg="$1"
    deb_url="$2"
    deb_latest="${3:-}"
    deb_installed="$(pkg_version "$deb_pkg")"
    if [ -n "$deb_installed" ]; then
        if [ -z "$deb_latest" ]; then
            log_ok "$deb_pkg $deb_installed (already installed)"
            return
        fi
        if dpkg --compare-versions "$deb_installed" ge "$deb_latest"; then
            log_ok "$deb_pkg $deb_installed (already newest)"
            return
        fi
    fi
    # ensure_apt_packages reuses the global pkg variable, hence deb_* names.
    ensure_apt_packages ca-certificates curl
    tmpdir="$(mktemp -d)"
    chmod 755 "$tmpdir"
    curl -fsSL "$deb_url" -o "$tmpdir/$deb_pkg.deb"
    chmod 644 "$tmpdir/$deb_pkg.deb"
    sudo apt-get install -y "$tmpdir/$deb_pkg.deb"
    rm -rf "$tmpdir"
    log_ok "$deb_pkg $(pkg_version "$deb_pkg")${deb_installed:+ (was $deb_installed)}"
}

# --- Snaps ------------------------------------------------------------------
# Remove the snap of an app that is installed from a .deb instead.
remove_snap() {
    name="$1"
    if ! command -v snap >/dev/null 2>&1 || ! snap list "$name" >/dev/null 2>&1; then
        log_skip "snap $name not installed"
        return
    fi
    sudo snap remove "$name"
    log_ok "removed snap $name"
}

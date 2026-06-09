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

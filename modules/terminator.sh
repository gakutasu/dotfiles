#!/bin/sh
# Terminator terminal emulator with its config (transparent background,
# infinite scrollback) linked from this repo. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

install_packages() {
    section "Installing terminator"
    ensure_apt_packages terminator
}

link_config() {
    section "Linking terminator config"
    mkdir -p "$HOME/.config/terminator"
    link "$DOTFILES_DIR/.config/terminator/config" "$HOME/.config/terminator/config"
}

main() {
    install_packages
    link_config
}

main "$@"

#!/bin/sh
# Command-line tools used from the shell: fzf (its key bindings are sourced by
# .bashrc), the silver searcher (ag) and ifmetric. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

install_packages() {
    section "Installing CLI tools"
    ensure_apt_packages fzf silversearcher-ag ifmetric
}

main() {
    install_packages
}

main "$@"

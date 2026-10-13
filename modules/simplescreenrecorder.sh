#!/bin/sh
# SimpleScreenRecorder for screen capture. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

install_packages() {
    section "Installing SimpleScreenRecorder"
    ensure_apt_packages simplescreenrecorder
}

main() {
    install_packages
}

main "$@"

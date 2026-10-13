#!/bin/sh
# VLC, with ffmpeg (used by the togif function in .bashrc) and
# ffmpegthumbnailer for video thumbnails in the file manager. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

install_packages() {
    section "Installing VLC"
    ensure_apt_packages vlc ffmpeg ffmpegthumbnailer
}

main() {
    install_packages
}

main "$@"

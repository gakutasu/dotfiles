#!/bin/sh
# Google Chrome from the official .deb. Its postinst registers the Google apt
# source and keyring (google-chrome.sources), so no repository is set up here
# and re-running moves to the newest version in that source. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

DEB_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"

install_chrome() {
    section "Installing Google Chrome (requires sudo)"
    install_deb_from_url google-chrome-stable "$DEB_URL"
    ensure_apt_packages google-chrome-stable
}

main() {
    install_chrome
}

main "$@"

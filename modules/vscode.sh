#!/bin/sh
# Visual Studio Code from the Microsoft apt repository (deb822 source, and the
# keyring path VS Code's own postinst uses), plus python3-venv for the Python
# extension. The one-line vscode.list written by ubuntu_setup is removed so apt
# does not see the source twice. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

KEYRING="/usr/share/keyrings/microsoft.gpg"
SOURCES="/etc/apt/sources.list.d/vscode.sources"
LEGACY_LIST="/etc/apt/sources.list.d/vscode.list"
REPO_URL="https://packages.microsoft.com/repos/code"

add_microsoft_repo() {
    section "Adding Microsoft apt repository (requires sudo)"
    if [ -f "$SOURCES" ] && grep -qx "URIs: $REPO_URL" "$SOURCES" && [ ! -f "$LEGACY_LIST" ]; then
        log_ok "$SOURCES (already set)"
        return
    fi
    ensure_apt_packages ca-certificates curl gnupg
    key="$(mktemp)"
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o "$key"
    sudo gpg --dearmor --yes -o "$KEYRING" "$key"
    rm -f "$key"
    sudo tee "$SOURCES" >/dev/null <<SRC
Types: deb
URIs: $REPO_URL
Suites: stable
Components: main
Architectures: amd64
Signed-By: $KEYRING
SRC
    if [ -f "$LEGACY_LIST" ]; then
        sudo rm -f "$LEGACY_LIST"
        log_move "removed legacy $LEGACY_LIST"
    fi
    sudo apt-get update
    log_ok "$SOURCES"
}

install_code() {
    section "Installing VS Code"
    ensure_apt_packages code python3-venv
}

main() {
    add_microsoft_repo
    install_code
}

main "$@"

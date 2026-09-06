#!/bin/sh
# Node.js LTS from the NodeSource apt repository.
# Needed at runtime by Claude Code plugin hooks (e.g. genshijin runs node) and
# by npm/npx based MCP servers. Bump NODE_MAJOR when a new LTS line ships:
# https://nodejs.org/en/about/previous-releases . Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

NODE_MAJOR=24
KEYRING="/etc/apt/keyrings/nodesource.gpg"
SOURCES="/etc/apt/sources.list.d/nodesource.sources"

installed_node_major() {
    command -v node >/dev/null 2>&1 || return 1
    node -v | sed 's/^v\([0-9]*\).*/\1/'
}

add_nodesource_repo() {
    section "Adding NodeSource apt repository (requires sudo)"
    if [ -f "$SOURCES" ] && grep -q "node_${NODE_MAJOR}\.x" "$SOURCES"; then
        log_ok "$SOURCES (already set to Node.js $NODE_MAJOR)"
        return
    fi
    ensure_apt_packages ca-certificates curl gnupg
    key="$(mktemp)"
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o "$key"
    sudo mkdir -p /etc/apt/keyrings
    sudo gpg --dearmor --yes -o "$KEYRING" "$key"
    rm -f "$key"
    sudo tee "$SOURCES" >/dev/null <<SRC
Types: deb
URIs: https://deb.nodesource.com/node_${NODE_MAJOR}.x/
Suites: nodistro
Components: main
Signed-By: $KEYRING
SRC
    sudo apt-get update
    log_ok "$SOURCES -> Node.js $NODE_MAJOR"
}

install_nodejs() {
    section "Installing Node.js"
    if [ "$(installed_node_major || true)" = "$NODE_MAJOR" ]; then
        log_ok "node $(node -v) (already installed)"
        return
    fi
    sudo apt-get install -y nodejs
    log_ok "node $(node -v), npm $(npm -v)"
}

main() {
    add_nodesource_repo
    install_nodejs
}

main "$@"

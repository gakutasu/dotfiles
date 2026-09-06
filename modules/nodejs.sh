#!/bin/sh
# Node.js LTS from the NodeSource apt repository.
# Needed at runtime by Claude Code plugin hooks (e.g. genshijin runs node) and
# by npm/npx based MCP servers. The LTS major is resolved from nodejs.org on
# every run, so re-running after a new LTS line ships (October of even years)
# moves to it; patch releases within a line arrive through apt upgrade.
# Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

NODE_MAJOR_FALLBACK=24
RELEASE_INDEX="https://nodejs.org/dist/index.json"
KEYRING="/etc/apt/keyrings/nodesource.gpg"
SOURCES="/etc/apt/sources.list.d/nodesource.sources"

installed_node_major() {
    command -v node >/dev/null 2>&1 || return 1
    node -v | sed 's/^v\([0-9]*\).*/\1/'
}

# Major of the newest release whose "lts" field is set (a codename for LTS
# lines, false for Current lines). The index is ordered newest first.
latest_lts_major() {
    python3 - "$RELEASE_INDEX" <<'PY'
import json, sys, urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=15) as response:
    for release in json.load(response):
        if release.get("lts"):
            print(release["version"].lstrip("v").split(".")[0])
            break
PY
}

resolve_node_major() {
    section "Resolving Node.js LTS"
    if NODE_MAJOR="$(latest_lts_major 2>/dev/null)" && [ -n "$NODE_MAJOR" ]; then
        log_ok "latest LTS is Node.js $NODE_MAJOR"
        return
    fi
    NODE_MAJOR="$(installed_node_major || echo "$NODE_MAJOR_FALLBACK")"
    log_warn "could not reach nodejs.org; keeping Node.js $NODE_MAJOR"
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
    resolve_node_major
    add_nodesource_repo
    install_nodejs
}

main "$@"

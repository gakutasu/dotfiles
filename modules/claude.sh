#!/bin/sh
# Claude Code: install the native CLI, link .claude/ into ~/.claude/, then
# register the marketplaces and install the plugins declared in settings.json.
# Claude Code records enabledPlugins / extraKnownMarketplaces in settings.json
# but does not install them on a new machine by itself, so without this step
# the plugins are enabled yet silently missing. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

CLAUDE_DOTFILES_DIR="$DOTFILES_DIR/.claude"
CLAUDE_HOME="$HOME/.claude"
SETTINGS="$CLAUDE_DOTFILES_DIR/settings.json"

# Native installer: ~/.local/bin/claude -> ~/.local/share/claude/versions/*.
# It auto-updates in the background; `claude update` forces a check.
install_claude() {
    section "Installing Claude Code"
    ensure_local_bin_in_path
    if command -v claude >/dev/null 2>&1; then
        log_ok "$(claude --version) (already installed)"
        return
    fi
    ensure_apt_packages curl
    curl -fsSL https://claude.ai/install.sh | bash
    log_ok "$(claude --version)"
}

link_configs() {
    section "Linking Claude Code config"
    mkdir -p "$CLAUDE_HOME"
    for item in CLAUDE.md settings.json skills; do
        link "$CLAUDE_DOTFILES_DIR/$item" "$CLAUDE_HOME/$item"
    done
}

# One "name<TAB>source" line per extraKnownMarketplaces entry, where source is
# what `claude plugin marketplace add` accepts (owner/repo, git URL, or path).
marketplace_sources() {
    python3 - "$SETTINGS" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1]))
for name, entry in settings.get("extraKnownMarketplaces", {}).items():
    src = entry.get("source", {})
    arg = {"github": "repo", "git": "url", "url": "url", "directory": "path"}.get(src.get("source"))
    if arg and src.get(arg):
        print(f"{name}\t{src[arg]}")
PY
}

# One "plugin@marketplace" line per enabled plugin.
enabled_plugins() {
    python3 - "$SETTINGS" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1]))
for name, enabled in settings.get("enabledPlugins", {}).items():
    if enabled:
        print(name)
PY
}

# Log the last line of CLI output, minus its "Doing X..." progress prefix.
log_cli_result() {
    log_ok "$(printf '%s\n' "$1" | tail -n 1 | sed 's/^.*…//; s/^.*\.\.\.//')"
}

log_cli_failure() {
    log_warn "$1"
    printf '%s\n' "$2" | sed 's/^/      /'
}

add_marketplaces() {
    section "Registering plugin marketplaces"
    tab="$(printf '\t')"
    marketplace_sources | while IFS="$tab" read -r name source; do
        if out="$(claude plugin marketplace add "$source" 2>&1)"; then
            log_cli_result "$out"
        else
            log_cli_failure "marketplace $name ($source)" "$out"
        fi
    done
}

install_plugins() {
    section "Installing enabled plugins"
    for plugin in $(enabled_plugins); do
        if out="$(claude plugin install "$plugin" 2>&1)"; then
            log_cli_result "$out"
        else
            log_cli_failure "plugin $plugin" "$out"
        fi
    done
    log_ok "restart Claude Code (or run /reload-plugins) to load new plugins"
}

main() {
    install_claude
    link_configs
    add_marketplaces
    install_plugins
}

main "$@"

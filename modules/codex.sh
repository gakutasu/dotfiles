#!/bin/sh
# Codex CLI: install the standalone binary (no Node.js needed) and reuse the
# Claude Code config. Codex reads global instructions from ~/.codex/AGENTS.md
# and supports the same Agent Skills format (SKILL.md). ~/.codex/skills also
# holds Codex-managed system skills (.system), so link each skill individually
# instead of replacing the whole directory. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

CODEX_HOME="$HOME/.codex"

# Installs to ~/.local/bin/codex. To update, re-run the installer:
#   curl -fsSL https://chatgpt.com/codex/install.sh | sh
install_codex() {
    section "Installing Codex CLI"
    ensure_local_bin_in_path
    if command -v codex >/dev/null 2>&1; then
        log_ok "$(codex --version) (already installed)"
        return
    fi
    ensure_apt_packages curl
    # CODEX_NON_INTERACTIVE skips prompts. ~/.local/bin is already on PATH, so
    # the installer does not write a PATH block into ~/.bashrc.
    curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
    log_ok "$(codex --version)"
}

link_configs() {
    section "Linking Codex config"
    mkdir -p "$CODEX_HOME/skills"
    link "$DOTFILES_DIR/.claude/CLAUDE.md" "$CODEX_HOME/AGENTS.md"
    for skill in "$DOTFILES_DIR/.claude/skills"/*; do
        [ -d "$skill" ] || continue
        link "$skill" "$CODEX_HOME/skills/$(basename "$skill")"
    done
}

show_login_status() {
    section "Codex login"
    # `codex login status` reports on stderr and exits non-zero when logged out.
    if status="$(codex login status 2>&1)"; then
        log_ok "$status"
    else
        log_warn "not logged in; run: codex login"
    fi
}

main() {
    install_codex
    link_configs
    show_login_status
}

main "$@"

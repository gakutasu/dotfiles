#!/bin/sh
# Codex CLI: install the standalone binary (no Node.js needed) and mirror the
# Claude Code setup into it, one way (Claude -> Codex). ~/.codex/AGENTS.md links
# to the shared CLAUDE.md; lib/codex_sync.py regenerates skills, hooks,
# permission rules and native plugins from the current Claude state. Run after
# the claude module, whose installed plugins it reads. Safe to re-run;
# re-running updates the CLI and picks up skills, hooks or plugins added to
# Claude Code since the last run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

CODEX_HOME="$HOME/.codex"

# Installs to ~/.local/bin/codex. The installer runs on every pass: it skips
# the download when the latest release is already in place and switches to the
# new release otherwise, so re-running also updates.
install_codex() {
    section "Installing Codex CLI"
    ensure_local_bin_in_path
    command -v curl >/dev/null 2>&1 || ensure_apt_packages curl
    before="$(codex --version 2>/dev/null || true)"
    # CODEX_NON_INTERACTIVE skips prompts. ~/.local/bin is already on PATH, so
    # the installer does not write a PATH block into ~/.bashrc.
    curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
    after="$(codex --version)"
    if [ "$before" = "$after" ]; then
        log_ok "$after (already newest)"
    else
        log_ok "$after${before:+ (was $before)}"
    fi
}

link_configs() {
    section "Linking Codex config"
    mkdir -p "$CODEX_HOME"
    link "$DOTFILES_DIR/.claude/CLAUDE.md" "$CODEX_HOME/AGENTS.md"
}

sync_from_claude() {
    section "Syncing Claude Code skills, hooks, rules and plugins"
    tab="$(printf '\t')"
    status=0
    out="$(python3 "$DOTFILES_DIR/lib/codex_sync.py" "$DOTFILES_DIR")" || status=$?
    printf '%s\n' "$out" | while IFS="$tab" read -r level msg; do
        [ -n "$level" ] || continue
        case "$level" in
            ok) log_ok "$msg" ;;
            link) log_link "$msg" ;;
            move) log_move "$msg" ;;
            skip) log_skip "$msg" ;;
            *) log_warn "$msg" ;;
        esac
    done
    return "$status"
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
    sync_from_claude
    show_login_status
}

main "$@"

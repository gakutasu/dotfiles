#!/bin/sh
# Codex: reuse the Claude Code config. Codex reads global instructions from
# ~/.codex/AGENTS.md and supports the same Agent Skills format (SKILL.md).
# ~/.codex/skills also holds Codex-managed system skills (.system), so link
# each skill individually instead of replacing the whole directory.
# Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

CODEX_HOME="$HOME/.codex"

link_configs() {
    section "Linking Codex config"
    mkdir -p "$CODEX_HOME/skills"
    link "$DOTFILES_DIR/.claude/CLAUDE.md" "$CODEX_HOME/AGENTS.md"
    for skill in "$DOTFILES_DIR/.claude/skills"/*; do
        [ -d "$skill" ] || continue
        link "$skill" "$CODEX_HOME/skills/$(basename "$skill")"
    done
}

main() {
    link_configs
}

main "$@"

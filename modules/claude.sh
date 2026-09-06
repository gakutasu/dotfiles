#!/bin/sh
# Claude Code: link .claude/ (CLAUDE.md, settings.json, skills) into ~/.claude/.
# Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

CLAUDE_DOTFILES_DIR="$DOTFILES_DIR/.claude"
CLAUDE_HOME="$HOME/.claude"

link_configs() {
    section "Linking Claude Code config"
    mkdir -p "$CLAUDE_HOME"
    for item in CLAUDE.md settings.json skills; do
        link "$CLAUDE_DOTFILES_DIR/$item" "$CLAUDE_HOME/$item"
    done
}

main() {
    link_configs
}

main "$@"

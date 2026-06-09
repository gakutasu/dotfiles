#!/bin/sh
# Symlink Claude Code settings from this dotfiles repo to ~/.claude/.
# Existing files at the destination are renamed to *.backup.<timestamp> before
# the symlink is created, so existing settings are never silently overwritten.

set -eu

CLAUDE_DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="$HOME/.claude"

. "$CLAUDE_DOTFILES_DIR/../lib/common.sh"

ITEMS="CLAUDE.md settings.json commands skills"

mkdir -p "$CLAUDE_HOME"

for item in $ITEMS; do
    link "$CLAUDE_DOTFILES_DIR/$item" "$CLAUDE_HOME/$item"
done

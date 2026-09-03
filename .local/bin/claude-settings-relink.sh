#!/bin/sh
# Keep ~/.claude/settings.json symlinked to the dotfiles copy.
# Claude Code saves settings atomically (write temp file, then rename), which
# replaces the symlink with a regular file. When that happens, copy the new
# content back into dotfiles (newest content wins) and restore the symlink.
# Invoked by claude-settings-relink.path (systemd user unit).
set -eu

DOTFILES_COPY="$HOME/dotfiles/.claude/settings.json"
TARGET="$HOME/.claude/settings.json"

[ -e "$TARGET" ] || exit 0

# Still a symlink pointing at dotfiles: nothing to do.
if [ -L "$TARGET" ] && [ "$(readlink "$TARGET")" = "$DOTFILES_COPY" ]; then
    exit 0
fi

cp "$TARGET" "$DOTFILES_COPY"
ln -sf "$DOTFILES_COPY" "$TARGET"
echo "restored symlink: $TARGET -> $DOTFILES_COPY"

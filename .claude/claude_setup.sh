#!/bin/sh
# Symlink Claude Code settings from this dotfiles repo to ~/.claude/.
# Existing files at the destination are renamed to *.backup.<timestamp> before
# the symlink is created, so existing settings are never silently overwritten.

set -eu

CLAUDE_DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="$HOME/.claude"

ITEMS="CLAUDE.md settings.json commands skills"

mkdir -p "$CLAUDE_HOME"

timestamp="$(date +%Y%m%d-%H%M%S)"

link_one() {
    name="$1"
    src="$CLAUDE_DOTFILES_DIR/$name"
    dest="$CLAUDE_HOME/$name"

    if [ ! -e "$src" ]; then
        echo "skip: $src does not exist in dotfiles"
        return
    fi

    if [ -L "$dest" ]; then
        current="$(readlink "$dest")"
        if [ "$current" = "$src" ]; then
            echo "ok:   $dest -> $src (already linked)"
            return
        fi
        echo "move: existing symlink $dest -> $current => $dest.backup.$timestamp"
        mv "$dest" "$dest.backup.$timestamp"
    elif [ -e "$dest" ]; then
        echo "move: existing $dest => $dest.backup.$timestamp"
        mv "$dest" "$dest.backup.$timestamp"
    fi

    ln -s "$src" "$dest"
    echo "link: $dest -> $src"
}

for item in $ITEMS; do
    link_one "$item"
done

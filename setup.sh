#!/bin/sh

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

symlink_dotfiles() {
    section "Linking home dotfiles"
    FILES_TO_LINK=".bashrc cyclonedds.xml ros2_alias.sh"
    for fname in $FILES_TO_LINK; do
        link "$DOTFILES_DIR/$fname" "$HOME/$fname"
    done
}

link_cyclone_sysctl_conf() {
    section "Linking cyclone sysctl conf (requires sudo)"
    src="$DOTFILES_DIR/etc/sysctl.d/10-cyclone-max.conf"
    dest="/etc/sysctl.d/10-cyclone-max.conf"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        log_ok "$dest -> $src (already linked)"
        return
    fi
    sudo ln -sf "$src" "$dest"
    log_link "$dest -> $src"
    sudo sysctl -q --system
    log_ok "sysctl reloaded"
}

# For claude code japanese input
# Fix missing GTK_IM_MODULE on GNOME so IME preedit shows in VTE terminals
link_ime_conf() {
    section "Linking IME conf"
    mkdir -p "$HOME/.config/environment.d"
    link "$DOTFILES_DIR/.config/environment.d/ime.conf" "$HOME/.config/environment.d/ime.conf"
}

setup_claude() {
    section "Setting up Claude Code"
    sh "$DOTFILES_DIR/.claude/setup.sh"
}

# Reuse Claude Code settings for Codex CLI.
# Codex reads global instructions from ~/.codex/AGENTS.md and supports the
# same Agent Skills format (SKILL.md). ~/.codex/skills also holds
# Codex-managed system skills (.system), so link each skill individually
# instead of replacing the whole directory.
setup_codex() {
    section "Setting up Codex"
    CODEX_HOME="$HOME/.codex"
    mkdir -p "$CODEX_HOME/skills"
    link "$DOTFILES_DIR/.claude/CLAUDE.md" "$CODEX_HOME/AGENTS.md"
    for skill in "$DOTFILES_DIR/.claude/skills"/*; do
        [ -d "$skill" ] || continue
        link "$skill" "$CODEX_HOME/skills/$(basename "$skill")"
    done
}

main() {
    symlink_dotfiles
    link_cyclone_sysctl_conf
    link_ime_conf
    setup_claude
    setup_codex
    section "Done"
}

main "$@"

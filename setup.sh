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

main() {
    symlink_dotfiles
    link_cyclone_sysctl_conf
    link_ime_conf
    setup_claude
    section "Done"
}

main "$@"

#!/bin/sh

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

symlink_dotfiles() {
    FILES_TO_LINK=".bashrc cyclonedds.xml ros2_alias.sh"
    for fname in $FILES_TO_LINK; do
        src="$DOTFILES_DIR/$fname"
        dest="$HOME/$fname"
        ln -sf "$src" "$dest"
    done
}

link_cyclone_sysctl_conf() {
    sudo ln -sf "$DOTFILES_DIR/etc/sysctl.d/10-cyclone-max.conf" /etc/sysctl.d/10-cyclone-max.conf
    sudo sysctl -q --system
}

# For claude code japanese input
# Fix missing GTK_IM_MODULE on GNOME so IME preedit shows in VTE terminals
link_ime_conf() {
    mkdir -p "$HOME/.config/environment.d"
    ln -sf "$DOTFILES_DIR/.config/environment.d/ime.conf" "$HOME/.config/environment.d/ime.conf"
}

setup_claude() {
    sh "$DOTFILES_DIR/.claude/claude_setup.sh"
}

main() {
    symlink_dotfiles
    link_cyclone_sysctl_conf
    link_ime_conf
    setup_claude
}

main "$@"

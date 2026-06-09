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

setup_claude() {
    sh "$DOTFILES_DIR/.claude/claude_setup.sh"
}

main() {
    symlink_dotfiles
    link_cyclone_sysctl_conf
    setup_claude
}

main "$@"

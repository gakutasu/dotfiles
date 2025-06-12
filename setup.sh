#!/bin/sh

symlink_dotfiles() {
    DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
    FILES_TO_LINK="
        .bashrc
        10-cyclone-max.conf
        cyclonedds.xml
        ros2_alias.sh"
    
    for fname in $FILES_TO_LINK; do
        src="$DOTFILES_DIR/$fname"
        dest="$HOME/$fname"
        ln -sf "$src" "$dest"
    done
}

main() {
    symlink_dotfiles
}

main "$@"

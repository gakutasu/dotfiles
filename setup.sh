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

add_sysctl_conf() {
    CONF_FILE="$DOTFILES_DIR/10-cyclone-max.conf"
    if [ -f "$CONF_FILE" ]; then
        echo "Adding $CONF_FILE to /etc/sysctl.conf ..."
        sudo tee -a /etc/sysctl.conf < "$CONF_FILE"
        echo "Applying sysctl settings ..."
        sudo sysctl -p
    else
        echo "$CONF_FILE not found."
        return 1
    fi
}

main() {
    symlink_dotfiles
    add_sysctl_conf
}

main "$@"

#!/bin/sh
# ROS 2 / CycloneDDS: link the sysctl tuning (large UDP buffers) into
# /etc/sysctl.d and apply it. ~/cyclonedds.xml and ~/ros2_alias.sh are linked
# by setup.sh together with the other home dotfiles. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

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

main() {
    link_cyclone_sysctl_conf
}

main "$@"

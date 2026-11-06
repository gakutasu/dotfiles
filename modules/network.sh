#!/bin/sh
# Turn off Wi-Fi power save for every NetworkManager connection. Power save
# makes the radio doze between beacons, adding up to ~100 ms to sparse traffic
# (ping, SSH, DDS discovery multicast). Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

link_wifi_powersave_conf() {
    section "Disabling Wi-Fi power save (requires sudo)"
    if ! command -v nmcli >/dev/null 2>&1; then
        log_skip "NetworkManager not installed"
        return
    fi
    src="$DOTFILES_DIR/etc/NetworkManager/conf.d/wifi-powersave-off.conf"
    dest="/etc/NetworkManager/conf.d/wifi-powersave-off.conf"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        log_ok "$dest -> $src (already linked)"
        return
    fi
    sudo ln -sf "$src" "$dest"
    log_link "$dest -> $src"
    sudo nmcli general reload conf
    log_ok "NetworkManager config reloaded (applies from the next Wi-Fi connection)"
}

main() {
    link_wifi_powersave_conf
}

main "$@"

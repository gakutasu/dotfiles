#!/bin/sh
# Make GRUB preselect the entry that was booted last time, so a dual-booted
# Windows stays selected once chosen until Ubuntu is chosen again. Sets
# GRUB_DEFAULT=saved and GRUB_SAVEDEFAULT=true in /etc/default/grub and
# regenerates grub.cfg only when one of them changed. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

GRUB_CONF=/etc/default/grub

# Set key=value in /etc/default/grub, replacing an existing assignment or
# appending one. Returns 1 when the value was already set.
set_grub_var() {
    key="$1"
    value="$2"
    if grep -qx "$key=$value" "$GRUB_CONF"; then
        log_ok "$key=$value (already set)"
        return 1
    fi
    if grep -q "^$key=" "$GRUB_CONF"; then
        sudo sed -i "s|^$key=.*|$key=$value|" "$GRUB_CONF"
    else
        echo "$key=$value" | sudo tee -a "$GRUB_CONF" >/dev/null
    fi
    log_ok "$key=$value"
}

remember_last_boot() {
    section "Making GRUB remember the last booted entry (requires sudo)"
    changed=""
    set_grub_var GRUB_DEFAULT saved && changed=1
    set_grub_var GRUB_SAVEDEFAULT true && changed=1
    if [ -z "$changed" ]; then
        return
    fi
    sudo update-grub
    log_ok "grub.cfg regenerated"
}

main() {
    remember_last_boot
}

main "$@"

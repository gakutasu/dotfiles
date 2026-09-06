#!/bin/sh
# systemd user units: link the units under .config/systemd/user/ and the
# scripts they run under .local/bin/, then enable timers and path units.
# Any *.service/*.timer/*.path added there is picked up automatically; timers
# and path units are enabled, plain services are only linked. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

UNIT_SRC="$DOTFILES_DIR/.config/systemd/user"
UNIT_DEST="$HOME/.config/systemd/user"

link_scripts() {
    section "Linking unit scripts"
    mkdir -p "$HOME/.local/bin"
    for script in "$DOTFILES_DIR/.local/bin"/*; do
        [ -f "$script" ] || continue
        link "$script" "$HOME/.local/bin/$(basename "$script")"
    done
}

link_units() {
    section "Linking systemd user units"
    mkdir -p "$UNIT_DEST"
    for unit in "$UNIT_SRC"/*.service "$UNIT_SRC"/*.timer "$UNIT_SRC"/*.path; do
        [ -f "$unit" ] || continue
        link "$unit" "$UNIT_DEST/$(basename "$unit")"
    done
    systemctl --user daemon-reload
}

enable_units() {
    section "Enabling timers and path units"
    for unit in "$UNIT_SRC"/*.timer "$UNIT_SRC"/*.path; do
        [ -f "$unit" ] || continue
        name="$(basename "$unit")"
        if systemctl --user enable --now "$name"; then
            log_ok "enabled $name"
        else
            log_warn "failed to enable $name"
        fi
    done
}

main() {
    link_scripts
    link_units
    enable_units
}

main "$@"

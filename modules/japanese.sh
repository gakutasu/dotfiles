#!/bin/sh
# Japanese input (ibus + Mozc) for GNOME on Wayland and X11.
# The jp layout is declared in ~/.config/mozc/ibus_config.textproto instead of
# setxkbmap, which never reaches native Wayland clients. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

in_graphical_session() {
    [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]
}

install_packages() {
    section "Installing ibus-mozc"
    missing=""
    for pkg in ibus-mozc mozc-utils-gui; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
    done
    if [ -z "$missing" ]; then
        log_ok "ibus-mozc mozc-utils-gui (already installed)"
        return
    fi
    sudo apt-get update
    # shellcheck disable=SC2086
    sudo apt-get install -y $missing
    log_ok "installed$missing"
}

link_configs() {
    section "Linking IME configs"
    mkdir -p "$HOME/.config/mozc" "$HOME/.config/environment.d"
    link "$DOTFILES_DIR/.config/mozc/ibus_config.textproto" "$HOME/.config/mozc/ibus_config.textproto"
    link "$DOTFILES_DIR/.config/environment.d/ime.conf" "$HOME/.config/environment.d/ime.conf"
}

# /etc/default/keyboard: used by GDM and non-GNOME X11 sessions.
set_system_keymap() {
    section "Setting system keyboard layout (requires sudo)"
    if localectl status 2>/dev/null | grep -q 'X11 Layout: jp$'; then
        log_ok "X11 layout is jp (already set)"
        return
    fi
    sudo localectl set-x11-keymap jp pc105
    log_ok "X11 layout set to jp"
}

# For non-GNOME X11 sessions; GNOME manages ibus itself.
set_im_framework() {
    section "Selecting ibus via im-config"
    if ! command -v im-config >/dev/null 2>&1; then
        log_skip "im-config not installed"
        return
    fi
    if grep -qs '^run_im ibus' "$HOME/.xinputrc"; then
        log_ok "im-config already set to ibus"
        return
    fi
    im-config -n ibus
    log_ok "im-config set to ibus (~/.xinputrc)"
}

set_gnome_input_sources() {
    section "Setting GNOME input sources"
    if ! command -v gsettings >/dev/null 2>&1; then
        log_skip "gsettings not available"
        return
    fi
    if ! in_graphical_session; then
        log_skip "no graphical session; run again from the desktop"
        return
    fi
    want="[('ibus', 'mozc-jp')]"
    current="$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || echo '?')"
    if [ "$current" = "$want" ]; then
        log_ok "input sources: $want (already set)"
        return
    fi
    gsettings set org.gnome.desktop.input-sources sources "$want"
    log_ok "input sources: $current -> $want"
}

# Layout the running ibus-daemon advertises for mozc-jp; empty if unavailable.
running_mozc_layout() {
    python3 - 2>/dev/null <<'PY'
import gi
gi.require_version("IBus", "1.0")
from gi.repository import IBus
IBus.init()
bus = IBus.Bus()
if bus.is_connected():
    for e in bus.list_engines():
        if e.get_name() == "mozc-jp":
            print(e.get_layout())
PY
}

# Restart ibus only when the running daemon does not yet advertise the wanted layout.
reload_ibus() {
    section "Reloading ibus"
    if ! command -v ibus >/dev/null 2>&1; then
        log_skip "ibus not installed"
        return
    fi
    want="$(sed -n 's/^ *layout *: *"\([^"]*\)".*/\1/p' "$DOTFILES_DIR/.config/mozc/ibus_config.textproto")"
    if ! in_graphical_session || ! pgrep -x ibus-daemon >/dev/null 2>&1; then
        ibus write-cache >/dev/null 2>&1
        log_skip "ibus-daemon not running; cache rebuilt, takes effect at next login"
        return
    fi
    if [ "$(running_mozc_layout)" = "$want" ]; then
        log_ok "ibus-daemon already advertises mozc-jp layout \"$want\""
        return
    fi
    ibus write-cache >/dev/null 2>&1
    ibus restart
    log_ok "ibus engine cache rebuilt and ibus-daemon restarted"
}

main() {
    install_packages
    link_configs
    set_system_keymap
    set_im_framework
    set_gnome_input_sources
    reload_ibus
}

main "$@"

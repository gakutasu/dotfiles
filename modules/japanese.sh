#!/bin/sh
# Japanese input setup: ibus + Mozc on GNOME, for both Wayland and X11.
#
# This replaces the old X11-only approach (`setxkbmap jp` in .bashrc and an
# autostart .desktop). setxkbmap only changes the X server / XWayland keymap,
# so native Wayland clients never received the jp layout and Zenkaku/Hankaku
# arrived as `grave`, which Mozc does not bind. GNOME Shell instead derives the
# keymap from the active input source: for an IBus source it uses the layout
# the engine declares, and Mozc declares "default", which GNOME cannot resolve,
# so the keymap silently stayed "us". Declaring `layout : "jp"` in
# ~/.config/mozc/ibus_config.textproto fixes this for Wayland and X11 alike.
#
# Safe to re-run; every step is idempotent. Can be run standalone or via setup.sh.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

# True when running inside a graphical session (gsettings/ibus need the bus).
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
    # shellcheck disable=SC2086  # word splitting is intended
    sudo apt-get install -y $missing
    log_ok "installed$missing"
}

# ibus_config.textproto: Mozc engine declaration (layout : "jp").
# ime.conf: GTK_IM_MODULE=ibus etc. for the systemd user session, so IME
# preedit also works in VTE terminals (needed for Claude Code on GNOME).
link_configs() {
    section "Linking IME configs"
    mkdir -p "$HOME/.config/mozc" "$HOME/.config/environment.d"
    link "$DOTFILES_DIR/.config/mozc/ibus_config.textproto" "$HOME/.config/mozc/ibus_config.textproto"
    link "$DOTFILES_DIR/.config/environment.d/ime.conf" "$HOME/.config/environment.d/ime.conf"
}

# System-wide keymap in /etc/default/keyboard: used by GDM, by X11 sessions
# without GNOME and (converted) by the console. GNOME sessions override it
# with the input-sources setting below, so no setxkbmap is needed anywhere.
set_system_keymap() {
    section "Setting system keyboard layout (requires sudo)"
    if localectl status 2>/dev/null | grep -q 'X11 Layout: jp$'; then
        log_ok "X11 layout is jp (already set)"
        return
    fi
    sudo localectl set-x11-keymap jp pc105
    log_ok "X11 layout set to jp"
}

# Select ibus as the input method framework for non-GNOME X11 sessions.
# GNOME starts and manages ibus itself, so this is a no-op there.
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

# GNOME lists input sources in gsettings; Mozc must be there to be selectable.
# A single Mozc source is enough: the jp layout comes from the engine
# declaration and Zenkaku/Hankaku toggles Mozc between direct/hiragana input.
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

# Rebuild the ibus engine cache so the layout from ibus_config.textproto is
# picked up, then restart the running daemon so GNOME Shell re-reads the
# engine description and applies the jp keymap without re-login. Skipped when
# the running daemon already advertises the wanted layout, so re-runs do not
# bounce the IME.
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

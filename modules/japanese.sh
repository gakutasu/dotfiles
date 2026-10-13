#!/bin/sh
# Japanese input (ibus + Mozc) for GNOME on Wayland and X11.
# The jp layout is declared in ~/.config/mozc/ibus_config.textproto instead of
# setxkbmap, which never reaches native Wayland clients. Mozc suggestions
# while typing are turned off. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

in_graphical_session() {
    [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]
}

install_packages() {
    section "Installing ibus-mozc"
    ensure_apt_packages ibus-mozc mozc-utils-gui
}

link_configs() {
    section "Linking IME configs"
    mkdir -p "$HOME/.config/mozc" "$HOME/.config/environment.d"
    link "$DOTFILES_DIR/.config/mozc/ibus_config.textproto" "$HOME/.config/mozc/ibus_config.textproto"
    link "$DOTFILES_DIR/.config/environment.d/ime.conf" "$HOME/.config/environment.d/ime.conf"
}

# Rewrite ~/.config/mozc/config1.db (a serialized mozc.config.Config) with the
# three suggest features off, keeping every other field. Prints "updated" or
# "unchanged".
write_mozc_suggest_config() {
    python3 - <<'PY'
import os, sys

PATH = os.path.expanduser("~/.config/mozc/config1.db")
# protocol/config.proto: use_history_suggest, use_dictionary_suggest,
# use_realtime_conversion (bool, default true; numbers are stable).
WANT = {100: 0, 101: 0, 102: 0}

def read_varint(buf, i):
    shift = value = 0
    while True:
        byte = buf[i]
        i += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if not byte & 0x80:
            return value, i

def write_varint(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if not value:
            out.append(byte)
            return bytes(out)
        out.append(byte | 0x80)

data = open(PATH, "rb").read() if os.path.exists(PATH) else b""
kept = bytearray()
found = {}
i = 0
while i < len(data):
    start = i
    key, i = read_varint(data, i)
    field, wire = key >> 3, key & 7
    if wire == 0:
        value, i = read_varint(data, i)
    elif wire == 1:
        i += 8
    elif wire == 2:
        length, i = read_varint(data, i)
        i += length
    elif wire == 5:
        i += 4
    else:
        sys.exit(f"unsupported wire type {wire} in {PATH}")
    if field in WANT and wire == 0:
        found[field] = value
    else:
        kept += data[start:i]

if found == WANT:
    print("unchanged")
    sys.exit(0)
for field, value in WANT.items():
    kept += write_varint(field << 3) + write_varint(value)
tmp = PATH + ".tmp"
with open(tmp, "wb") as f:
    f.write(kept)
os.replace(tmp, PATH)
print("updated")
PY
}

# Mozc pops up candidates while typing; with history suggest, dictionary
# suggest and realtime conversion off they appear only after Space.
# mozc_server reads the config at start and ibus-engine-mozc relaunches it on
# the next keystroke, so a changed config just needs the server gone.
disable_mozc_suggest() {
    section "Disabling Mozc suggestions while typing"
    mkdir -p "$HOME/.config/mozc"
    if ! result="$(write_mozc_suggest_config)"; then
        log_warn "could not rewrite ~/.config/mozc/config1.db"
        return 1
    fi
    if [ "$result" = "unchanged" ]; then
        log_ok "mozc suggest already off"
        return
    fi
    if pgrep -x mozc_server >/dev/null 2>&1; then
        pkill -x mozc_server
        log_ok "mozc suggest off; mozc_server relaunches on next input"
    else
        log_ok "mozc suggest off"
    fi
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
    disable_mozc_suggest
    set_system_keymap
    set_im_framework
    set_gnome_input_sources
    reload_ibus
}

main "$@"

#!/bin/sh
# Keep the hardware clock (RTC) in local time so a dual-booted Windows, which
# reads the RTC as local time, shows the same time as Ubuntu. systemd warns
# that local-time RTC is discouraged (DST double adjustment), which does not
# apply to Asia/Tokyo. Safe to re-run.
#
# Switching the mode alone is not enough: timedated writes the RTC once, but
# the already running timesyncd keeps the kernel's 11-minute RTC sync enabled,
# which writes UTC back within minutes. timesyncd only disables that sync when
# it starts in local-RTC mode, so it is restarted after the switch, and the
# RTC is rewritten from the NTP-synced system clock whenever it does not hold
# local time. --adjust-system-clock is deliberately not used.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

set_local_rtc() {
    section "Setting RTC to local time (requires sudo)"
    if [ "$(timedatectl show -p LocalRTC --value 2>/dev/null)" = "yes" ]; then
        log_ok "RTC already in local time"
        return
    fi
    sudo timedatectl set-local-rtc 1
    sudo systemctl restart systemd-timesyncd
    log_ok "RTC set to local time"
}

# Seconds the RTC is ahead of the local wall-clock time it should hold.
rtc_offset_from_local() {
    rtc_usec="$(busctl get-property org.freedesktop.timedate1 \
        /org/freedesktop/timedate1 org.freedesktop.timedate1 RTCTimeUSec)"
    rtc_sec=$(( ${rtc_usec#t } / 1000000 ))
    want_sec="$(date -u -d "$(date '+%Y-%m-%d %H:%M:%S')" +%s)"
    echo $(( rtc_sec - want_sec ))
}

sync_rtc_from_system_clock() {
    section "Checking that the RTC holds local time"
    offset="$(rtc_offset_from_local)"
    if [ "$offset" -le 60 ] && [ "$offset" -ge -60 ]; then
        log_ok "RTC holds local time"
        return
    fi
    if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" != "yes" ]; then
        log_warn "RTC is off by ${offset}s but the system clock is not NTP-synced; not rewriting it"
        return 1
    fi
    log_warn "RTC is off by ${offset}s, rewriting it from the system clock"
    command -v hwclock >/dev/null 2>&1 || ensure_apt_packages util-linux-extra
    sudo hwclock --systohc --localtime
    log_ok "RTC rewritten (now off by $(rtc_offset_from_local)s)"
}

main() {
    set_local_rtc
    sync_rtc_from_system_clock
}

main "$@"

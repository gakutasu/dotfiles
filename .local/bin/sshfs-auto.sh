#!/usr/bin/env bash
# Auto-mount/unmount sshfs based on host reachability.
# Reachable via SSH port -> mount. Unreachable -> lazy unmount (prevents ls hangs).
# Invoked periodically by sshfs-auto.timer (systemd user unit).
set -u

# "ssh_config_host[,fallback_host...]:mountpoint" pairs. Add new hosts here.
# Hosts are tried in order and the first reachable one gets mounted, so list
# alternative routes to the same machine (e.g. LAN, then VPN) on one line.
TARGETS=(
    "albion,albion-vpn:/home/gakutasu/albion_robot"
    "pochi:/home/gakutasu/pochi_robot"
    "orion:/home/gakutasu/orion_robot"
)

# dir_cache=no: cached readdir returns d_type=DT_UNKNOWN, which makes VS Code's
# file watcher (@parcel/watcher) skip subdirectories, so open editors never
# reload after external edits.
SSHFS_OPTS="reconnect,ServerAliveInterval=5,ServerAliveCountMax=3,follow_symlinks,dir_cache=no"

# Resolve HostName from ~/.ssh/config (ssh -G works offline)
resolve_host() {
    ssh -G "$1" 2>/dev/null | awk '$1 == "hostname" {print $2; exit}'
}

resolve_port() {
    ssh -G "$1" 2>/dev/null | awk '$1 == "port" {print $2; exit}'
}

is_mounted() {
    # Check /proc/mounts only; never stat the mountpoint (it may hang on a dead mount)
    awk -v mp="$1" '$2 == mp {found=1} END {exit !found}' /proc/mounts
}

is_reachable() {
    # TCP connect AND read the SSH banner. A wedged sshd (host under heavy
    # load, OOM, etc.) can accept the TCP connection but never send the
    # banner, which would pass a plain port check and hang sshfs.
    local banner
    banner="$(timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2 && IFS= read -r -t 2 line <&3 && printf '%s' \"\$line\"" 2>/dev/null)"
    [[ "$banner" == SSH-* ]]
}

is_healthy() {
    # A mount can go stale (server died mid-session) while still listed in
    # /proc/mounts; probe it with a timeout so we never hang ourselves.
    timeout 3 stat -t -- "$1" >/dev/null 2>&1
}

mounted_host() {
    # sshfs lists its mount source as "host:"
    awk -v mp="$1" '$2 == mp {sub(/:.*/, "", $1); print $1; exit}' /proc/mounts
}

# Exit status: 0 reachable, 1 unreachable, 2 unresolvable
probe_host() {
    local addr port
    addr="$(resolve_host "$1")"
    port="$(resolve_port "$1")"
    [ -n "$addr" ] || return 2
    is_reachable "$addr" "${port:-22}"
}

unmount() {
    # Stopping the unit terminates sshfs, which tears down the mount;
    # fall back to fusermount for mounts not owned by a unit.
    systemctl --user stop "$1" 2>/dev/null
    is_mounted "$2" && fusermount -u -z "$2"
}

for target in "${TARGETS[@]}"; do
    IFS=, read -ra hosts <<< "${target%%:*}"
    mp="${target#*:}"
    # One unit per mountpoint, named after the primary host
    unit="sshfs-${hosts[0]}"

    # Tear down stale mounts first so a recovered host gets remounted below
    if is_mounted "$mp" && ! is_healthy "$mp"; then
        unmount "$unit" "$mp"
        echo "unmounted stale $mp"
    fi

    current="$(mounted_host "$mp")"
    if [ -n "$current" ]; then
        # Keep the mount while its host is reachable, and also when the host
        # cannot be resolved (e.g. ssh config broken mid-edit). A working
        # mount is never switched to a higher-priority host.
        probe_host "$current"
        [ $? -eq 1 ] || continue
        unmount "$unit" "$mp"
        echo "unmounted $mp (${current} unreachable)"
    fi

    for host in "${hosts[@]}"; do
        probe_host "$host" || continue
        # A lazily-detached sshfs (reconnect opt) can outlive its mount
        # and keep the unit name loaded; stop it before mounting again.
        systemctl --user stop "$unit" 2>/dev/null
        mkdir -p "$mp"
        # Run sshfs in its own transient unit, NOT as a child of this
        # service: systemd kills the whole cgroup when the oneshot unit
        # exits, which would tear down the mount immediately.
        # -f keeps sshfs in the foreground so the transient unit tracks it.
        systemd-run --user --quiet --collect --unit "$unit" \
            sshfs -f -o "$SSHFS_OPTS" "${host}:" "$mp"
        # systemd-run only reports that the unit started; sshfs may still
        # exit right away (e.g. auth failure), so verify the mount itself.
        sleep 2
        if is_mounted "$mp"; then
            echo "mounted ${host}: -> $mp"
            break
        fi
        echo "mount failed for ${host}: (check ssh auth)"
    done
done
exit 0

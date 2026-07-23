#!/usr/bin/env bash
# Auto-mount/unmount sshfs based on host reachability.
# Reachable via SSH port -> mount. Unreachable -> lazy unmount (prevents ls hangs).
# Invoked periodically by sshfs-auto.timer (systemd user unit).
set -u

# "ssh_config_host:mountpoint" pairs. Add new hosts here.
TARGETS=(
    "albion:/home/gakutasu/albion_robot"
    "pochi:/home/gakutasu/pochi_robot"
)

SSHFS_OPTS="reconnect,ServerAliveInterval=5,ServerAliveCountMax=3,follow_symlinks"

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
    # TCP connect to the SSH port, 2s timeout
    timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

for target in "${TARGETS[@]}"; do
    host="${target%%:*}"
    mp="${target#*:}"
    addr="$(resolve_host "$host")"
    port="$(resolve_port "$host")"
    [ -n "$addr" ] || continue

    if is_reachable "$addr" "${port:-22}"; then
        if ! is_mounted "$mp"; then
            mkdir -p "$mp"
            sshfs -o "$SSHFS_OPTS" "${host}:" "$mp" \
                && echo "mounted ${host}: -> $mp"
        fi
    else
        if is_mounted "$mp"; then
            fusermount -u -z "$mp" && echo "unmounted $mp (${host} unreachable)"
        fi
    fi
done
exit 0

#!/bin/sh
# Command-line tools used from the shell: fzf (its key bindings are sourced by
# .bashrc), the silver searcher (ag), htop, ifmetric and sshfs (needed by the
# sshfs-auto systemd timer), plus LAN scanning tools (nmap, arp-scan,
# avahi-utils for mDNS, nbtscan for NetBIOS). Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

install_packages() {
    section "Installing CLI tools"
    ensure_apt_packages fzf silversearcher-ag htop ifmetric sshfs
}

install_network_tools() {
    section "Installing network scanning tools"
    ensure_apt_packages nmap arp-scan avahi-utils nbtscan
}

main() {
    install_packages
    install_network_tools
}

main "$@"

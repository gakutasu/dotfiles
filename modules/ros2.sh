#!/bin/sh
# ROS 2 (the LTS distro for this Ubuntu, picked from the ROS apt source;
# override with ROS_DISTRO=<name>):
# locale, universe, the ROS apt source, desktop + dev tools + CycloneDDS RMW,
# rosdep, ripvcs (rv) in ~/.local/bin, and the CycloneDDS sysctl tuning in
# /etc/sysctl.d. ~/cyclonedds.xml and ~/ros2_alias.sh are linked by setup.sh
# together with the other home dotfiles, and .bashrc already exports the
# RMW/ROS environment. Most steps need sudo. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

ubuntu_codename() {
    # shellcheck disable=SC1091
    . /etc/os-release && echo "$VERSION_CODENAME"
}

# Sets $distro. ROS_DISTRO wins; a sourced /opt/ros/<distro>/setup.bash sets
# it too, which keeps re-runs on the installed distro. Otherwise pick the LTS
# from the ROS apt source: ROS 2 ships an LTS with every Ubuntu LTS and the
# non-LTS release a year later sorts after it (humble < iron, jazzy < kilted),
# so the alphabetically first non-rolling ros-<distro>-desktop is the LTS.
# Needs the apt lists from packages.ros.org (see install_ros_apt_source).
select_ros_distro() {
    section "Selecting ROS 2 distro"
    if [ -n "${ROS_DISTRO:-}" ]; then
        distro="$ROS_DISTRO"
        log_ok "$distro (from ROS_DISTRO)"
        return
    fi
    distro="$(apt-cache pkgnames ros- 2>/dev/null |
        sed -n 's/^ros-\([a-z]*\)-desktop$/\1/p' |
        grep -vx rolling | sort | head -n 1)"
    if [ -z "$distro" ]; then
        log_warn "no ros-<distro>-desktop in apt for Ubuntu $(ubuntu_codename); set ROS_DISTRO=<name>"
        return 1
    fi
    log_ok "$distro (LTS for Ubuntu $(ubuntu_codename))"
}

# "tag_name" of the latest GitHub release of owner/repo; empty when offline.
latest_release_tag() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null |
        sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p'
}

install_prerequisites() {
    section "Installing prerequisites"
    ensure_apt_packages locales software-properties-common curl
}

# ROS 2 needs a UTF-8 locale. Only LANG is set: a system-wide LC_ALL would
# override every per-category setting.
setup_locale() {
    section "Setting locale to en_US.UTF-8 (requires sudo)"
    if locale -a 2>/dev/null | grep -qi '^en_US\.utf-\?8$' &&
        grep -qs '^LANG=en_US.UTF-8$' /etc/default/locale; then
        log_ok "en_US.UTF-8 (already set)"
        return
    fi
    sudo locale-gen en_US en_US.UTF-8
    sudo update-locale LANG=en_US.UTF-8
    log_ok "locale set to en_US.UTF-8 (takes effect at next login)"
}

enable_universe() {
    section "Enabling the universe repository (requires sudo)"
    if apt-cache policy 2>/dev/null | grep -q '/universe '; then
        log_ok "universe (already enabled)"
        return
    fi
    sudo add-apt-repository -y universe
    log_ok "universe enabled"
}

# packages.ros.org via the ros2-apt-source package (keyring + sources list).
install_ros_apt_source() {
    section "Installing the ROS 2 apt source (requires sudo)"
    if dpkg -s ros2-apt-source >/dev/null 2>&1; then
        log_ok "ros2-apt-source $(dpkg-query -W -f='${Version}' ros2-apt-source) (already installed)"
        return
    fi
    version="$(latest_release_tag ros-infrastructure/ros-apt-source)"
    if [ -z "$version" ]; then
        log_warn "could not query the latest ros-apt-source release (offline?)"
        return 1
    fi
    deb="ros2-apt-source_${version}.$(ubuntu_codename)_all.deb"
    # World-readable temp dir so apt's sandboxed _apt user can read the .deb.
    tmpdir="$(mktemp -d)"
    chmod 755 "$tmpdir"
    curl -fsSL -o "$tmpdir/$deb" \
        "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${version}/${deb}"
    sudo apt-get install -y "$tmpdir/$deb"
    rm -rf "$tmpdir"
    log_ok "ros2-apt-source $version installed"
    # Fetch the packages.ros.org lists now: select_ros_distro reads them.
    sudo apt-get update
}

# colcon-cd, colcon-argcomplete and vcstool provide the completion files
# sourced by .bashrc; colcon-clean backs the rosclean alias.
install_ros_packages() {
    section "Installing ROS 2 $distro packages (requires sudo)"
    ensure_apt_packages \
        ros-dev-tools \
        "ros-$distro-desktop" \
        "ros-$distro-rmw-cyclonedds-cpp" \
        python3-colcon-clean \
        python3-colcon-cd \
        python3-colcon-argcomplete \
        python3-vcstool
}

init_rosdep() {
    section "Initializing rosdep (requires sudo)"
    if [ -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
        log_ok "rosdep sources (already initialized)"
    else
        sudo rosdep init
        log_ok "rosdep initialized"
    fi
    if [ -d "$HOME/.ros/rosdep/sources.cache" ]; then
        log_ok "rosdep cache (already present; refresh with: rosdep update)"
        return
    fi
    rosdep update
    log_ok "rosdep cache updated"
}

# ripvcs: fast vcstool replacement. Latest GitHub release into ~/.local/bin/rv.
install_ripvcs() {
    section "Installing ripvcs (rv)"
    ensure_local_bin_in_path
    latest="$(latest_release_tag ErickKramer/ripvcs)"
    if [ -z "$latest" ]; then
        log_warn "could not query the latest ripvcs release (offline?)"
        return 1
    fi
    if [ -x "$HOME/.local/bin/rv" ]; then
        # The "Version:" line carries ANSI color codes; match only the vX.Y.Z part.
        current="$("$HOME/.local/bin/rv" version 2>/dev/null | sed -n '/Version:/ s/.*\(v[0-9][0-9.]*\).*/\1/p')"
        if [ "$current" = "$latest" ]; then
            log_ok "rv $current (already installed)"
            return
        fi
    fi
    case "$(uname -m)" in
        x86_64) arch=amd64 ;;
        aarch64) arch=arm64 ;;
        *)
            log_warn "no ripvcs build for $(uname -m)"
            return 1
            ;;
    esac
    tmp="$HOME/.local/bin/rv.tmp"
    curl -fsSL -o "$tmp" \
        "https://github.com/ErickKramer/ripvcs/releases/download/${latest}/ripvcs_${latest#v}_linux_${arch}"
    chmod +x "$tmp"
    mv "$tmp" "$HOME/.local/bin/rv"
    log_ok "rv $latest installed to ~/.local/bin/rv"
    if [ -e /usr/local/bin/rv ]; then
        log_warn "old /usr/local/bin/rv is now shadowed; remove it with: sudo rm /usr/local/bin/rv"
    fi
}

link_cyclone_sysctl_conf() {
    section "Linking cyclone sysctl conf (requires sudo)"
    src="$DOTFILES_DIR/etc/sysctl.d/10-cyclone-max.conf"
    dest="/etc/sysctl.d/10-cyclone-max.conf"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        log_ok "$dest -> $src (already linked)"
        return
    fi
    sudo ln -sf "$src" "$dest"
    log_link "$dest -> $src"
    sudo sysctl -q --system
    log_ok "sysctl reloaded"
}

main() {
    install_prerequisites
    setup_locale
    enable_universe
    install_ros_apt_source
    select_ros_distro
    install_ros_packages
    init_rosdep
    install_ripvcs
    link_cyclone_sysctl_conf
    log_ok "open a new shell to load /opt/ros/$distro (sourced by .bashrc)"
}

main "$@"

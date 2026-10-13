#!/bin/sh
# Slack from the official .deb, replacing the snap. The apt source the .deb
# registers (packagecloud) serves no packages, so the current version is read
# from the download page and that .deb is fetched directly; re-running
# upgrades when the installed version is older. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

PKG="slack-desktop"
DOWNLOAD_PAGE="https://slack.com/downloads/linux"

# First "Version x.y.z" on the download page; the page may come back in
# Japanese regardless of Accept-Language.
latest_slack_version() {
    curl -fsSL -H 'Accept-Language: en-US' "$DOWNLOAD_PAGE" \
        | grep -Eo '(Version|バージョン)[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+' \
        | head -n1 \
        | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+'
}

install_slack() {
    section "Installing Slack (requires sudo)"
    ensure_apt_packages ca-certificates curl
    installed="$(pkg_version "$PKG")"
    version="$(latest_slack_version)" || version=""
    if [ -z "$version" ]; then
        if [ -n "$installed" ]; then
            log_warn "could not read the latest version from $DOWNLOAD_PAGE; keeping $PKG $installed"
            return
        fi
        log_warn "could not read the Slack version from $DOWNLOAD_PAGE"
        return 1
    fi
    log_ok "latest Slack is $version"
    install_deb_from_url "$PKG" \
        "https://downloads.slack-edge.com/desktop-releases/linux/x64/$version/slack-desktop-$version-amd64.deb" \
        "$version"
}

main() {
    remove_snap slack
    install_slack
}

main "$@"

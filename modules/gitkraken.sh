#!/bin/sh
# GitKraken from the official .deb, replacing the snap. The download link
# redirects to .../linux/x64/<version>/<id>/gitkraken-amd64.deb, so the newest
# version is read from that Location without fetching the package, and
# re-running upgrades when the installed version is older. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

DEB_URL="https://api.gitkraken.dev/releases/production/linux/x64/active/gitkraken-amd64.deb"

latest_gitkraken_version() {
    curl -fsS -o /dev/null -w '%{redirect_url}' "$DEB_URL" \
        | sed -n 's|.*/linux/x64/\([0-9][0-9.]*\)/.*|\1|p'
}

install_gitkraken() {
    section "Installing GitKraken (requires sudo)"
    ensure_apt_packages ca-certificates curl
    version="$(latest_gitkraken_version)" || version=""
    if [ -n "$version" ]; then
        log_ok "latest GitKraken is $version"
    else
        log_warn "could not read the latest GitKraken version; installing only if missing"
    fi
    install_deb_from_url gitkraken "$DEB_URL" "$version"
}

main() {
    remove_snap gitkraken
    install_gitkraken
}

main "$@"

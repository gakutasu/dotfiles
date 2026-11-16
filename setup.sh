#!/bin/sh
# Entry point: link home dotfiles, then run the setup modules under modules/.
# Every module is standalone (sh modules/<name>.sh) and safe to re-run.
#
#   sh setup.sh              # run everything
#   sh setup.sh claude codex # run only the named modules

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

# Modules do not depend on each other at setup time; the order only follows
# runtime needs: the systemd relink unit guards ~/.claude/settings.json before
# claude links it, plugin hooks run node, and the Claude Code codex plugin
# calls the codex binary. git comes early so its interactive ssh-keygen prompt
# is reached before the long installs.
DEFAULT_MODULES="rtc grub network git cli-tools terminator chrome vscode slack gitkraken vlc simplescreenrecorder ros2 japanese systemd nodejs claude codex"

symlink_dotfiles() {
    section "Linking home dotfiles"
    for fname in .bashrc .gitconfig cyclonedds.xml ros2_alias.sh; do
        link "$DOTFILES_DIR/$fname" "$HOME/$fname"
    done
}

# Run each module in its own shell so one failure (e.g. no sudo, offline)
# does not stop the rest. Failed modules are listed at the end.
run_modules() {
    failed=""
    for name in "$@"; do
        if [ ! -f "$DOTFILES_DIR/modules/$name.sh" ]; then
            log_warn "unknown module: $name"
            failed="$failed $name"
            continue
        fi
        sh "$DOTFILES_DIR/modules/$name.sh" || failed="$failed $name"
    done
    section "Done"
    if [ -n "$failed" ]; then
        log_warn "failed modules:$failed (retry with: sh setup.sh <name>)"
        return 1
    fi
}

# Shown last so it is not lost in the module output. Asks only when someone is
# at the terminal, and never reboots without a yes.
offer_reboot() {
    [ -s "$DOTFILES_RELOGIN_FILE" ] || return 0
    reasons="$(sort -u "$DOTFILES_RELOGIN_FILE" | sed 's/^/- /')"
    section "再起動が必要です"
    echo "次の変更は、再起動の後に有効になります。"
    echo "$reasons"
    [ -t 0 ] || return 0
    answer=n
    if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v zenity >/dev/null 2>&1; then
        if zenity --question --title="セットアップ完了" --width=480 \
            --text="次の変更は、再起動の後に有効になります。\n\n$reasons\n\n今すぐ再起動しますか？\n保存していない作業は失われます。" \
            --ok-label="今すぐ再起動" --cancel-label="あとで" --default-cancel 2>/dev/null; then
            answer=y
        fi
    else
        printf '今すぐ再起動しますか？ 保存していない作業は失われます。 [y/N] '
        read -r answer || answer=n
    fi
    case "$answer" in
        y | Y | yes) systemctl reboot || log_warn "再起動できませんでした。手動で再起動してください" ;;
        *) log_ok "あとで再起動してください" ;;
    esac
}

main() {
    DOTFILES_RELOGIN_FILE="$(mktemp)"
    export DOTFILES_RELOGIN_FILE
    trap 'rm -f "$DOTFILES_RELOGIN_FILE"' EXIT
    status=0
    symlink_dotfiles
    if [ $# -gt 0 ]; then
        run_modules "$@" || status=$?
    else
        # shellcheck disable=SC2086
        run_modules $DEFAULT_MODULES || status=$?
    fi
    offer_reboot
    return "$status"
}

main "$@"

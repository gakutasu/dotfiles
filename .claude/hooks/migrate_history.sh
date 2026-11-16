#!/bin/sh
# Move Claude Code history and memory left in the per-folder project folders
# into the shared one named in .config/environment.d/claude.conf (see
# lib/claude_migrate.py).
#
#   migrate_history.sh         setup (modules/claude.sh): copy the config and
#                              report whether a reboot is still needed. Moves
#                              nothing, because the shell that runs setup does
#                              not prove what Claude Code will use.
#   migrate_history.sh --hook  SessionStart hook: start the move in the
#                              background, handing it the hook input, which
#                              tells whether this session already uses the
#                              shared folder. Prints nothing, because the
#                              output of this hook is fed to the model.
set -eu

DOTFILES_DIR="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
shared="$(sed -n 's/^CLAUDE_CODE_PROJECT_DIR_NAME=//p' "$DOTFILES_DIR/.config/environment.d/claude.conf")"

migrate() {
    python3 "$DOTFILES_DIR/lib/claude_migrate.py" "$DOTFILES_DIR" "$shared" "$@"
}

# Cheap test that keeps python out of every session start once all is moved.
has_leftovers() {
    for entry in "$HOME/.claude/projects"/*/*; do
        [ -e "$entry" ] || continue
        case "$entry" in
            "$HOME/.claude/projects/$shared"/* | */memory.merged*) continue ;;
        esac
        return 0
    done
    return 1
}

case "${1:-}" in
    --hook)
        has_leftovers || exit 0
        # Read first: on the line below stdin is already redirected when the
        # assignment is expanded.
        input="$(cat)"
        MIGRATE_HOOK_INPUT="$input" setsid -f sh "$0" --background </dev/null >/dev/null 2>&1
        ;;
    --background)
        log="$HOME/.claude/migrate_history.log"
        status=0
        out="$(printf '%s' "${MIGRATE_HOOK_INPUT:-}" | migrate --hook 2>&1)" || status=$?
        [ "$status" -eq 0 ] || out="$out
migration failed with exit status $status"
        [ -z "$out" ] || printf '%s\n' "$out" >"$log" 2>/dev/null || true
        command -v notify-send >/dev/null 2>&1 || exit 0
        if [ "$status" -ne 0 ]; then
            notify-send "Claude Code" "過去の履歴とメモリの移行に失敗しました。詳細: $log" || true
        elif printf '%s\n' "$out" | grep -Eq "^ok$(printf '\t')(moved|merged) "; then
            notify-send "Claude Code" "過去の履歴とメモリを共通フォルダへ移しました。" || true
        fi
        ;;
    *)
        migrate --prepare
        ;;
esac

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
# calls the codex binary.
DEFAULT_MODULES="ros2 japanese systemd nodejs claude codex"

symlink_dotfiles() {
    section "Linking home dotfiles"
    for fname in .bashrc cyclonedds.xml ros2_alias.sh; do
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

main() {
    symlink_dotfiles
    if [ $# -gt 0 ]; then
        run_modules "$@"
    else
        # shellcheck disable=SC2086
        run_modules $DEFAULT_MODULES
    fi
}

main "$@"

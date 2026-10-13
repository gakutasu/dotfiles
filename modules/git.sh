#!/bin/sh
# Git with LFS, ~/.gitconfig linked from this repo, and an ed25519 SSH key.
# Because ~/.gitconfig is a symlink into the repo, later `git config --global`
# changes show up in `git diff` here. ssh-keygen prompts for a passphrase when
# the key does not exist yet. Safe to re-run.

set -eu

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$MODULE_DIR/.." && pwd)"

. "$DOTFILES_DIR/lib/common.sh"

SSH_KEY="$HOME/.ssh/id_ed25519"

install_packages() {
    section "Installing git"
    ensure_apt_packages git git-lfs
}

link_gitconfig() {
    section "Linking ~/.gitconfig"
    link "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
}

# Writes the lfs filter into ~/.gitconfig with the values the repo already
# tracks, so the repo stays clean. --skip-repo keeps it from touching the hooks
# of whatever repo the shell happens to be in.
setup_lfs() {
    section "Enabling git-lfs"
    git lfs install --skip-repo
    log_ok "git-lfs filters registered"
}

generate_ssh_key() {
    section "Generating SSH key"
    if [ -f "$SSH_KEY" ]; then
        log_ok "$SSH_KEY (already exists)"
        return
    fi
    install -d -m 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$(git config --global user.email)" -f "$SSH_KEY"
    log_ok "generated $SSH_KEY; register $SSH_KEY.pub with GitHub"
}

main() {
    install_packages
    link_gitconfig
    setup_lfs
    generate_ssh_key
}

main "$@"

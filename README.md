# dotfiles

Ubuntu 向けの設定ファイルとセットアップスクリプト。

## Setup

```sh
git clone git@github.com:gakutasu/dotfiles.git ~/dotfiles
sh ~/dotfiles/setup.sh
```

既存ファイルは `*.backup.<日時>` に退避してからシンボリックリンクする。再実行可。

## Layout

```
.
├── setup.sh                        # エントリポイント
├── lib/common.sh                   # 共通関数(ログ、バックアップ付き link)
├── modules/
│   └── japanese.sh                 # 日本語入力(ibus-mozc、Wayland / X11 両対応)
├── .bashrc
├── ros2_alias.sh                   # ROS 2 用シェル関数
├── cyclonedds.xml                  # CycloneDDS 設定
├── etc/sysctl.d/10-cyclone-max.conf
├── .config/
│   ├── environment.d/ime.conf      # IME 環境変数
│   ├── mozc/ibus_config.textproto  # Mozc エンジン宣言
│   └── systemd/user/               # sshfs 自動マウント、Claude 設定リンク復元
├── .local/bin/                     # systemd ユニットから呼ぶスクリプト
└── .claude/                        # Claude Code 設定
    ├── CLAUDE.md
    ├── settings.json
    ├── setup.sh
    └── skills/                     # /commit, /pr, /issue
```

## Claude Code

`.claude/` を `~/.claude/` にリンクする。同じ設定を Codex CLI(`~/.codex/`)にもリンクする。

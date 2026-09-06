# dotfiles

Ubuntu 向けの設定ファイルとセットアップスクリプト。

## Setup

```sh
git clone git@github.com:gakutasu/dotfiles.git ~/dotfiles
sh ~/dotfiles/setup.sh
```

既存ファイルは `*.backup.<日時>` に退避してからシンボリックリンクする。再実行可。

モジュール名を渡すと、そのモジュールだけ実行する。各モジュールは単体でも実行できる。

```sh
sh ~/dotfiles/setup.sh claude codex   # 指定したモジュールのみ
sh ~/dotfiles/modules/claude.sh       # 単体実行
```

失敗したモジュールがあっても残りは続行し、最後に一覧を表示する。

## Layout

```
.
├── setup.sh                        # エントリポイント(ホームのリンク + モジュール実行)
├── lib/common.sh                   # 共通関数(ログ、バックアップ付き link、apt、PATH)
├── modules/                        # 実行順に記載。すべて再実行可
│   ├── ros2.sh                     # CycloneDDS 用 sysctl 設定(sudo)
│   ├── japanese.sh                 # 日本語入力(ibus-mozc、Wayland / X11 両対応)
│   ├── systemd.sh                  # systemd ユーザーユニット(sshfs 自動マウント、Claude 設定リンク復元)
│   ├── nodejs.sh                   # Node.js LTS(NodeSource apt、sudo)
│   ├── claude.sh                   # Claude Code CLI、設定リンク、プラグイン導入
│   └── codex.sh                    # Codex CLI、Claude Code 設定の流用
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
    └── skills/                     # /commit, /pr, /issue
```

## Claude Code

`modules/claude.sh` が以下を行う。

1. 公式インストーラで CLI を `~/.local/bin/claude` に導入(導入済みならスキップ)
2. `.claude/` を `~/.claude/` にリンク
3. `settings.json` の `extraKnownMarketplaces` を `claude plugin marketplace add` で登録
4. `settings.json` の `enabledPlugins` を `claude plugin install` で導入

Claude Code は `enabledPlugins` を settings.json に書き込むが、新しい環境でそれを自動導入はしない。
3 と 4 がないと「有効なのに中身がない」状態になる。導入後は Claude Code を再起動するか `/reload-plugins` を実行する。

プラグインの hook は `node` を使うものがあるため、`nodejs.sh` を先に実行する。

## Codex

`modules/codex.sh` が公式インストーラで CLI を `~/.local/bin/codex` に導入し、Claude Code と同じ設定を使う。
`CLAUDE.md` を `~/.codex/AGENTS.md` に、`skills/` の各スキルを `~/.codex/skills/` にリンクする。
未ログインなら `codex login` を案内する。

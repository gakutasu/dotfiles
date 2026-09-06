# dotfiles

Ubuntu 環境向けの設定ファイルと、それを配置するセットアップスクリプト。

## Setup

```sh
git clone git@github.com:gakutasu/dotfiles.git ~/dotfiles
sh ~/dotfiles/setup.sh
```

`setup.sh` は次を順に行う。既存ファイルは `*.backup.<日時>` に退避してからリンクするので、再実行しても安全。

1. ホーム直下のドットファイル(`.bashrc`、`cyclonedds.xml`、`ros2_alias.sh`)をシンボリックリンク
2. CycloneDDS 用の sysctl 設定を `/etc/sysctl.d` にリンク(sudo)
3. `modules/` 以下のセットアップスクリプトを実行
4. systemd ユーザーユニットとそのスクリプトをリンクし、timer / path ユニットを有効化
5. Claude Code と Codex の設定をリンク

## Layout

| パス | 役割 |
|---|---|
| `setup.sh` | エントリポイント |
| `lib/common.sh` | ログ出力と、バックアップ付きシンボリックリンク(`link`)の共通関数 |
| `.bashrc` | シェル設定。エディタ、CUDA、fzf、ROS 2 環境の読み込みなど |
| `ros2_alias.sh` | ROS 2 用のシェル関数(ワークスペース検出、ビルド、source、プロセス監視)。`.bashrc` から読み込む |
| `cyclonedds.xml` | CycloneDDS の設定 |
| `etc/sysctl.d/10-cyclone-max.conf` | CycloneDDS 向けのカーネルパラメータ |
| `.config/environment.d/ime.conf` | systemd ユーザーセッションに IME の環境変数を設定 |
| `.config/mozc/ibus_config.textproto` | Mozc の IBus エンジン宣言(キーボード配列など) |
| `.config/systemd/user/` | systemd ユーザーユニット |
| `.local/bin/` | ユニットから呼ばれるスクリプト |
| `.claude/` | Claude Code の設定 |
| `modules/` | 機能単位のセットアップスクリプト |

## Modules

機能単位のセットアップスクリプト。`setup.sh` から呼ばれるほか、単体でも実行できる。すべて冪等。

| スクリプト | 役割 |
|---|---|
| `modules/japanese.sh` | 日本語入力環境の構築。ibus-mozc の導入、GNOME の入力ソース設定、Mozc / IME 設定のリンク、システムのキーボード配列設定を行う。Wayland / X11 両対応 |

## systemd user units

`setup.sh` が `~/.config/systemd/user/` にリンクし、`.timer` と `.path` を `enable --now` する。

| ユニット | 役割 |
|---|---|
| `sshfs-auto.timer` / `.service` | ロボット(albion、pochi)への sshfs マウントを到達性に応じて自動マウント / アンマウントする |
| `claude-settings-relink.path` / `.service` | Claude Code が `~/.claude/settings.json` を実体ファイルに置き換えたとき、内容を dotfiles に取り込んでシンボリックリンクを復元する |

## Claude Code

`.claude/setup.sh` が `.claude/` 以下を `~/.claude/` にリンクする。認証情報(`.claude/.credentials.json`)は `.gitignore` で除外している。

| パス | 役割 |
|---|---|
| `.claude/CLAUDE.md` | 全プロジェクト共通の指示(言語、コーディングスタイル、禁止コマンドなど) |
| `.claude/settings.json` | Claude Code の設定(権限、モデル、プラグイン、UI など) |
| `.claude/skills/` | カスタムスキル |

| スキル | 役割 |
|---|---|
| `/commit` | Conventional Commits 形式でコミットを作成する |
| `/pr` | 作業ブランチのコミットから GitHub PR を作成する |
| `/issue` | セッション中に起きた問題を GitHub issue として報告する |

### Codex

同じ設定を Codex CLI でも使う。`setup.sh` が `CLAUDE.md` を `~/.codex/AGENTS.md` に、各スキルを `~/.codex/skills/` にリンクする。

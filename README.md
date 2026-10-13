# dotfiles

Ubuntu 向けの設定ファイルとセットアップスクリプト。

## Setup

```sh
git clone git@github.com:gakutasu/dotfiles.git ~/dotfiles
sh ~/dotfiles/setup.sh
```

既存ファイルは `*.backup.<日時>` に退避してからシンボリックリンクする。再実行可。
再実行すると apt 管理のパッケージと Chrome / Slack / GitKraken を最新版に更新する(sudo が必要)。apt のリスト更新は 10 分以内に行われていれば省略する。

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
├── lib/common.sh                   # 共通関数(ログ、バックアップ付き link、apt 導入 / 更新、.deb 導入、snap 削除、PATH)
├── modules/                        # 実行順に記載。すべて再実行可
│   ├── rtc.sh                      # RTC をローカル時刻に(Windows とのデュアルブート向け)
│   ├── grub.sh                     # GRUB の初期選択を前回起動したエントリに(Windows とのデュアルブート向け)
│   ├── git.sh                      # git / git-lfs、.gitconfig リンク、SSH 鍵生成
│   ├── cli-tools.sh                # fzf、silversearcher-ag、ifmetric、sshfs
│   ├── terminator.sh               # Terminator と設定リンク
│   ├── chrome.sh                   # Google Chrome(公式 .deb、apt ソースは .deb が登録)
│   ├── vscode.sh                   # VS Code(Microsoft apt)、python3-venv
│   ├── slack.sh                    # Slack(公式 .deb、snap は削除)
│   ├── gitkraken.sh                # GitKraken(公式 .deb、snap は削除)
│   ├── vlc.sh                      # VLC、ffmpeg、ffmpegthumbnailer
│   ├── simplescreenrecorder.sh     # SimpleScreenRecorder
│   ├── ros2.sh                     # ROS 2 導入
│   ├── japanese.sh                 # 日本語入力(ibus-mozc、Wayland / X11 両対応、入力中サジェスト無効)
│   ├── systemd.sh                  # systemd ユーザーユニット(sshfs 自動マウント、Claude 設定リンク復元)
│   ├── nodejs.sh                   # Node.js LTS(NodeSource apt、sudo)
│   ├── claude.sh                   # Claude Code CLI、設定リンク、プラグイン導入
│   └── codex.sh                    # Codex CLI、Claude Code 設定の流用
├── .bashrc
├── .gitconfig                      # git 設定(user、editor、lfs)
├── ros2_alias.sh                   # ROS 2 用シェル関数
├── cyclonedds.xml                  # CycloneDDS 設定
├── etc/sysctl.d/10-cyclone-max.conf
├── .config/
│   ├── environment.d/ime.conf      # IME 環境変数
│   ├── mozc/ibus_config.textproto  # Mozc エンジン宣言
│   ├── systemd/user/               # sshfs 自動マウント、Claude 設定リンク復元
│   └── terminator/config           # Terminator 設定(透過背景、無限スクロールバック)
├── .local/bin/                     # systemd ユニットから呼ぶスクリプト
└── .claude/                        # Claude Code 設定
    ├── CLAUDE.md
    ├── settings.json
    └── skills/                     # /commit, /pr, /issue
```

## デスクトップアプリ

- `git.sh`: `~/.gitconfig` はこのリポジトリへのシンボリックリンクなので、`git config --global` での変更は `git diff` に現れる。`~/.ssh/id_ed25519` が無ければ `ssh-keygen` を対話実行する(パスフレーズを聞かれる)。
- `chrome.sh`: 公式 .deb を導入する。.deb が `google-chrome.sources` と鍵を登録するので、以後はそのソースから最新版に更新する。
- `vscode.sh`: Microsoft の apt ソースを deb822 形式(`vscode.sources`)で登録し、ubuntu_setup が書いた旧 `vscode.list` があれば削除する。
- `slack.sh` / `gitkraken.sh`: 公式 .deb を導入する。Slack はダウンロードページ、GitKraken はダウンロードリンクのリダイレクト先から最新版の番号を読み、導入済みの版が古ければ更新する。Slack の apt ソース(packagecloud)はパッケージを配信しないため、`apt upgrade` では更新されない。

## ROS 2

`modules/ros2.sh` が以下を行う。distro は ROS の apt ソースにある `ros-<distro>-desktop` のうち、rolling を除いてアルファベット順で先頭のもの(その Ubuntu 向けの LTS。noble なら jazzy、resolute なら lyrical)を自動で選ぶ。`ROS_DISTRO=<name>` で上書きできる。

1. locale を en_US.UTF-8 にし、universe と ROS 2 の apt ソース(`ros2-apt-source`)を導入
2. `ros-<distro>-desktop`、`ros-dev-tools`、`rmw-cyclonedds-cpp`、colcon 拡張(clean / cd / argcomplete)、vcstool を導入
3. `rosdep init` と `rosdep update`(初回のみ)
4. ripvcs(`rv`)の最新リリースを `~/.local/bin/rv` に導入
5. CycloneDDS 用 sysctl 設定を `/etc/sysctl.d` にリンクして適用

`~/cyclonedds.xml` と `~/ros2_alias.sh` は `setup.sh` がリンクし、`.bashrc` が RMW と alias を読み込む。導入後は新しいシェルを開く。

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

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
├── setup.sh                        # エントリポイント(ホームのリンク + モジュール実行、必要なら最後に再起動を案内)
├── lib/common.sh                   # 共通関数(ログ、バックアップ付き link、apt 導入 / 更新、.deb 導入、snap 削除、PATH)
├── lib/codex_sync.py               # Claude Code の設定を Codex に同期(codex.sh から実行)
├── lib/claude_migrate.py           # フォルダ別だった Claude Code の履歴とメモリを共通フォルダへ移行(claude.sh から実行)
├── modules/                        # 実行順に記載。すべて再実行可
│   ├── rtc.sh                      # RTC をローカル時刻に(Windows とのデュアルブート向け)
│   ├── grub.sh                     # GRUB の初期選択を前回起動したエントリに(Windows とのデュアルブート向け)
│   ├── network.sh                  # Wi-Fi の省電力を無効化(NetworkManager の conf.d にリンク)
│   ├── git.sh                      # git / git-lfs、.gitconfig リンク、SSH 鍵生成
│   ├── cli-tools.sh                # fzf、silversearcher-ag、ifmetric、sshfs、nmap、arp-scan、avahi-utils、nbtscan
│   ├── terminator.sh               # Terminator と設定リンク
│   ├── chrome.sh                   # Google Chrome(公式 .deb、apt ソースは .deb が登録)
│   ├── vscode.sh                   # VS Code(Microsoft apt)、python3-venv
│   ├── slack.sh                    # Slack(公式 .deb、snap は削除)
│   ├── gitkraken.sh                # GitKraken(公式 .deb、snap は削除)
│   ├── vlc.sh                      # VLC、ffmpeg、ffmpegthumbnailer
│   ├── simplescreenrecorder.sh     # SimpleScreenRecorder
│   ├── ros2.sh                     # ROS 2 導入
│   ├── japanese.sh                 # 日本語入力(ibus-mozc、Wayland / X11 両対応、入力中サジェスト無効)
│   ├── systemd.sh                  # systemd ユーザーユニット(sshfs 自動マウント、Claude 設定リンク復元、vscode-pets パッチ)
│   ├── nodejs.sh                   # Node.js LTS(NodeSource apt、sudo)
│   ├── claude.sh                   # Claude Code CLI、設定リンク、履歴とメモリの移行、プラグイン導入
│   └── codex.sh                    # Codex CLI、Claude Code 設定の同期
├── .bashrc
├── .gitconfig                      # git 設定(user、editor、lfs)
├── ros2_alias.sh                   # ROS 2 用シェル関数
├── cyclonedds.xml                  # CycloneDDS 設定
├── etc/NetworkManager/conf.d/wifi-powersave-off.conf
├── etc/sysctl.d/10-cyclone-max.conf
├── .config/
│   ├── environment.d/ime.conf      # IME 環境変数
│   ├── environment.d/claude.conf   # Claude Code の履歴とメモリを全フォルダ共通にする環境変数
│   ├── mozc/ibus_config.textproto  # Mozc エンジン宣言
│   ├── systemd/user/               # sshfs 自動マウント、Claude 設定リンク復元、vscode-pets パッチ
│   └── terminator/config           # Terminator 設定(透過背景、無限スクロールバック)
├── .local/bin/                     # systemd ユニットから呼ぶスクリプト
└── .claude/                        # Claude Code 設定
    ├── CLAUDE.md
    ├── settings.json
    ├── agents/                     # Claude Code 専用サブエージェント(Codex 相談の中継役)
    ├── hooks/                      # セッションタイトルに作業フォルダ名を付けるフック、履歴とメモリの移行を始めるフック
    ├── rules/                      # Claude Code 専用ルール(Codex には渡さない)
    └── skills/                     # /commit, /pr, /issue, codex-consult
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

1. 公式インストーラで CLI を `~/.local/bin/claude` に導入(導入済みなら更新)
2. `.claude/` を `~/.claude/` に、`.config/environment.d/claude.conf` を `~/.config/environment.d/` にリンク
3. 履歴とメモリの共通化の準備(設定ファイルのコピーと、再起動が必要かの判定。過去の履歴とメモリの移行は Claude Code の起動時フックが行う)
4. `settings.json` の `extraKnownMarketplaces` を `claude plugin marketplace add` で登録
5. `settings.json` の `enabledPlugins` を `claude plugin install` で導入

Claude Code は `enabledPlugins` を settings.json に書き込むが、新しい環境でそれを自動導入はしない。
4 と 5 がないと「有効なのに中身がない」状態になる。導入後は Claude Code を再起動するか `/reload-plugins` を実行する。

プラグインの hook は `node` を使うものがあるため、`nodejs.sh` を先に実行する。

### 履歴とメモリの共通化

`claude.conf` により、会話履歴と自動メモリは作業フォルダに関係なく `~/.claude/projects/all/` に保存される。
履歴の一覧でフォルダを見分けられるよう、`.claude/hooks/session_title_prefix.py` がタイトルの先頭に `【ホームからの相対パス】` を付ける。

環境変数はログイン時に読まれるため、共通化が有効になるのは再起動の後になる。
必要な場合は `setup.sh` が最後にその旨を表示し、端末から実行していれば再起動するかを尋ねる(デスクトップではダイアログ)。

共通化の前に `~/.claude/projects/<フォルダ別>/` へ保存されたものは、次の流れで共通フォルダへ移る。セットアップを流すのは 1 回でよい。

1. セットアップ時: `~/.claude.json` を `~/.claude/.claude.json` にコピーする(コピー先がない場合のみ。共通化後は後者が読まれる)。会話とメモリはまだ動かさない。共通化が有効になる前に動かすと、履歴の一覧から見えなくなるため
2. 再起動後: Claude Code を開くと、SessionStart フック(`.claude/hooks/migrate_history.sh`)が裏で移行(`lib/claude_migrate.py`)を実行し、結果をデスクトップ通知で知らせる。警告や失敗の内容は `~/.claude/migrate_history.log` に残る

移行を始めるのは、会話の保存先が共通フォルダになっている Claude Code のフックだけ。その Claude Code からは、移した後も履歴が見える。セットアップ自体は会話もメモリも動かさない。
共通フォルダの指定には Claude Code v2.1.234 以降が必要。

`environment.d` の変数が ssh のシェルに渡るとは限らない。変数を持たずに起動した Claude Code は旧フォルダを使い続け、移行もそこからは始まらない。
同じ PC でデスクトップと ssh の両方から Claude Code を使う場合、デスクトップ側が移行した後は、変数を持たない ssh 側から過去の履歴とメモリが見えなくなる。

移行の内容は次のとおり。

- メモリを `all/memory/` にコピーし、`MEMORY.md` に元のフォルダごとの見出しで追記。元のフォルダは `memory.merged` に改名して残す
- 会話を `all/` に移動し、タイトルに元のフォルダ名を付ける

使用中の会話は移動せず、次に Claude Code を開いたときに回す。
メモリの統合は Claude Code を開いたままでも行う。統合の瞬間に Claude Code が `MEMORY.md` を書き換えると、その追記が失われることがある。
同名で内容が異なるメモリが `all/memory/` に既にある場合は上書きしない。別の旧フォルダにも同名のメモリがあれば番号付きの別名(`名前-2.md`)で取り込み、なければ統合後に編集されたものとみなして警告だけを出す。

## Codex

`modules/codex.sh` が公式インストーラで CLI を `~/.local/bin/codex` に導入し、Claude Code の設定を Codex に一方向で同期する(Claude → Codex)。
`CLAUDE.md` は `~/.codex/AGENTS.md` にリンクし、残りは `lib/codex_sync.py` が Claude 側の現状から毎回作り直す。

- スキル: dotfiles の `skills/` と有効プラグインのスキルを `~/.agents/skills/` にリンク。プラグインのコマンドはスキルに変換して生成
- フック: `settings.json` と有効プラグインのフックを `~/.codex/hooks.json` に統合。変更後は Codex 内の `/hooks` で一度承認が必要。`~/.claude/hooks/` のフック(タイトルの接頭辞、履歴の移行)は Claude Code 専用なので除外
- 権限: `permissions` の `Bash(xxx *)` を `~/.codex/rules/claude.rules` の `prefix_rule` に変換。完全一致(`Bash(python3)` など)は前方一致にすると許可範囲が広がるため変換しない
- プラグイン: Codex 公式版があるもの(`NATIVE_PLUGINS`、現状 superpowers)は Codex 側にネイティブ導入し、Claude 専用のもの(`EXCLUDED_PLUGINS`、codex プラグイン)は除外

作成物は `~/.codex/claude-sync.json` に記録し、Claude 側から消えたものは次回実行時に削除する。記録にないファイルには触れない。
プラグインの導入先を読むため、`claude.sh` の後に実行する。スキル・フック・プラグインを追加したら `sh setup.sh codex` で反映する。
未ログインなら `codex login` を案内する。

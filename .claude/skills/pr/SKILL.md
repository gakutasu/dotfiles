---
name: pr
description: 現在の作業ブランチのコミット済み変更で GitHub PR を作成する。ユーザーが「PR を作って」「プルリクを出して」と依頼した時、または `/pr` と入力した時に使用する。
---

# PR 作成スキル

現在の作業ブランチのコミット済み変更を対象に GitHub PR を作成する。ステージング済み・未コミットの変更は一切対象外とする（コミット・`git add` は行わない）。

コマンドが失敗したときは、その結果を「差分なし」などと解釈せず、エラー内容をユーザーに報告して中断する。例外は、各手順で「見つからない場合」「未設定の場合」の扱いを明記したものだけとする。一覧の取得と検索（`grep`）は分けて実行し、取得の失敗と「該当なし」を区別する。

## 1. 対象リポジトリの特定

- リポジトリのルート: `git rev-parse --show-toplevel`
  - 失敗した場合（ROS ワークスペース直下など）は、セッション中に変更したファイルが属するリポジトリを候補とする。候補が1つに定まらなければユーザーに確認する
  - 以降のコマンドはすべてこのルートで実行する
- 現在のブランチ: `git branch --show-current`（空なら detached HEAD なので中断する）
- リモート一覧: `git remote -v`
- 作業ツリーの状態: `git status --short`（未コミットの変更があっても PR には含めない）

## 2. 投稿先・base・head の確定

PR の投稿先（target）と変更元（head）を分けて扱う。fork から upstream へ出す場合、両者は別のリポジトリになる。

1. origin の情報を取得する

   ```bash
   git remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##'
   gh repo view <origin の owner/repo> --json nameWithOwner,isFork,parent,isInOrganization
   ```

2. 投稿先を決める。優先順位は「ユーザー指定 → origin が fork なら parent（`<.parent.owner.login>/<.parent.name>`）→ origin」
3. 投稿先のデフォルトブランチを取得する: `gh repo view <投稿先> --json defaultBranchRef --jq '.defaultBranchRef.name'`
4. base を決める。優先順位は「ユーザー指定 → `git config branch.<ブランチ>.gh-merge-base` → 投稿先のデフォルトブランチ」（`git config` が値なしで終了コード 1 を返すのは未設定であり、次の候補に進む）
5. 投稿先の base を fetch し、SHA を base_ref として控える。fetch 元は、`git remote -v` に投稿先を指すリモートがあればそのリモート名、なければ `https://github.com/<投稿先>.git` とする

   ```bash
   git fetch <fetch 元> <base>
   git rev-parse --verify 'FETCH_HEAD^{commit}'
   ```

6. head を決める
   - push 先は origin の `<ブランチ>` とする
   - 投稿先と origin が同じリポジトリなら head は `<ブランチ>`、違うなら `<origin の owner>:<ブランチ>` とする
   - 投稿先と origin が同じリポジトリで、ブランチが base と同じ場合は中断する（作業ブランチが必要）

## 3. PR に含まれる変更の確認

base_ref を起点に、コミット済みの変更だけを取得する。

```bash
merge_base=$(git merge-base <base_ref> HEAD)
git log --oneline "$merge_base..HEAD"
git diff --stat "$merge_base" HEAD
git diff "$merge_base" HEAD
```

- `git log` の出力が空なら、PR に含める変更がないので中断する
- 下書きを作った時点の `git rev-parse HEAD` を控えておく（step 8 で使う）

続けて、次の2点を確認する。

- **既存 PR**: `gh pr list --repo <投稿先> --head <ブランチ> --base <base> --state open --limit 100 --json number,url,headRepositoryOwner`
  - `.headRepositoryOwner.login` が origin の owner と一致する PR があれば、その URL をユーザーに示して中断する
- **push の要否**: `git ls-remote origin refs/heads/<ブランチ>` の SHA が HEAD と同じなら不要、違うか出力が空なら必要とする

## 4. PR テンプレートの読み込み

GitHub が使うのは、デフォルトブランチ上のテンプレートである。作業ツリーではなく、投稿先のデフォルトブランチから読む（fork 側にしかないテンプレートや、未コミットのテンプレートを使わないため）。

テンプレートの配置は `.github/`・ルート・`docs/` のいずれかで、ファイル名の大文字小文字は区別されない。拡張子は `.md` / `.txt` またはなし。複数の場所にある場合は `.github/` → ルート → `docs/` の順に優先する。以下の順で探す。

1. **投稿先リポジトリのテンプレート**

   base がデフォルトブランチならその base_ref を、違えばデフォルトブランチを fetch した SHA を template_ref とする。

   ```bash
   git ls-tree -r --name-only <template_ref> > <scratchpad>/pr-tree.txt
   grep -iE '^(\.github/|docs/)?pull_request_template(\.(md|txt))?(/[^/]+)?$' <scratchpad>/pr-tree.txt
   git show <template_ref>:<見つかったパス>
   ```

   `grep` の該当なし（終了コード 1）は「テンプレートなし」として 2 に進む。

2. **投稿先 owner の共通テンプレート**

   GitHub は、owner の**公開**リポジトリ `<owner>/.github` にあるテンプレートを既定として使う。

   ```bash
   gh repo view <owner>/.github --json visibility,defaultBranchRef
   gh api "repos/<owner>/.github/git/trees/<デフォルトブランチ>?recursive=1" --jq '.tree[].path' > <scratchpad>/pr-org-tree.txt
   grep -iE '^(\.github/|docs/)?pull_request_template(\.(md|txt))?(/[^/]+)?$' <scratchpad>/pr-org-tree.txt
   gh api "repos/<owner>/.github/contents/<見つかったパス>" -H "Accept: application/vnd.github.raw"
   ```

   リポジトリが存在しない（`gh repo view` が not found）、公開されていない、または `grep` の該当がない場合は 3 に進む。

3. **デフォルト構成**。見出しはそのまま使い、中身を step 5 で決めた言語で書く。

```
## Summary
（変更の目的・背景）

## Detail
- （変更の詳細）

## Test
- （動作確認の手順）
```

**テンプレートが複数ある場合:**

ファイル名と内容を PR の内容と照らし合わせ、最も適切なものを自分で選ぶ。判断基準：

- バグ修正 → bug fix 系
- 新機能 → feature 系
- ドキュメント変更 → docs 系
- リファクタリング → refactor / chore 系

どのテンプレートにも当てはまらない、または甲乙つけがたい場合に限りユーザーに確認する。

## 5. タイトル・本文の言語の決定

投稿先リポジトリ（fork の場合は upstream）で判定する。

- 投稿先の owner が `sbgisen` または `gakutasu` → **日本語**
- それ以外の外部リポジトリ → 以下で判定する
  1. 投稿先の CONTRIBUTING やテンプレートで言語が指定されていれば、それに従う
  2. 最近の PR と issue を取得する

     ```bash
     gh pr list --repo <投稿先> --state all --limit 20 --json title,body,author
     gh issue list --repo <投稿先> --state all --limit 20 --json title,body,author
     ```

  3. bot の投稿、テンプレートの定型文、コード・ログ・引用を除き、人が書いたタイトル・本文に、仮名を含む日本語の文章があれば**日本語**、なければ**英語**とする。漢字が含まれるだけでは日本語と判断しない
  4. PR・issue が1件もない場合や取得に失敗した場合は**英語**とする（中断しない）

タイトルと本文は同じ言語で書く。ユーザーとのやり取り（プレビューの説明や確認の質問）は、PR の言語にかかわらず日本語で行う。

## 6. 下書きの作成と自己レビュー

下書きを作り、ユーザーに見せる前に自己レビューする。

**下書きのルール:**

- タイトルは変更内容を短く表す（例: 日本語 `ユーザー認証を追加`、英語 `Add user authentication`）
- 本文はテンプレートを埋める。日本語の場合、**文体は常体（だ・である調）とし、ですます調は使用しない**（例: ×「認証機能を追加します」 → ○「認証機能を追加する」）
- ステージング済み・未コミットの変更は本文に含めない
- テスト欄には、実際に行った確認と、行っていない確認を区別して書く
- 関連する issue がある場合は、テンプレートの該当箇所に prefix を付けて明示する
  - `close #123` / `fix #123` — マージ時に issue を自動クローズする。自動クローズが働くのは、投稿先のデフォルトブランチに向けた PR の場合だけ
  - `ref #123` — 参照のみ（クローズしない）
  - 別リポジトリの issue は `owner/repo#123` と書く
  - 複数ある場合はそれぞれ記載する（例: `close #12, ref #34`）
  - issue が不明な場合はコミットメッセージやブランチ名から推測し、`gh issue view <番号> --repo <issue のリポジトリ>` で実在と内容を確認できたものだけ記載する

**自己レビュー:** step 3 の diff と下書きを突き合わせる。

- 本文に書いた変更点がすべて diff に含まれているか（実在しない変更を書いていないか）
- diff に含まれる重要な変更が本文から漏れていないか
- 影響範囲・テスト欄がコード変更と整合しているか
- issue の参照が、実際の変更内容と関連しているか

## 7. プレビュー表示・承認確認

以下の形式で PR の内容をユーザーに提示し、**必ず承認を得てから投稿**すること。承認が得られない場合は中断する。

```
---
タイトル: <タイトル>
投稿先: <投稿先の owner/repo>（<base> ← <head>）
言語: <日本語 / 英語>（判定根拠: <例: sbgisen のリポジトリ / 直近の PR・issue に日本語の投稿なし>）
push: <必要 / 不要>

<テンプレートを埋めた本文>
---
この PR を投稿しますか？
```

本文を修正した場合は、修正後の内容で再度プレビューを示して承認を得る。

## 8. push と PR 投稿

ユーザーの承認を得た後にのみ実行する。

1. `git rev-parse HEAD` が step 3 で控えた値と同じか確認する。違う場合は step 3 からやり直す
2. push が必要なら `git push -u origin <ブランチ>` を実行する。拒否された（リモートと分岐している）場合や失敗した場合は、投稿せずに中断して報告する（force push はしない）
3. `git ls-remote origin refs/heads/<ブランチ>` の SHA が HEAD と同じことを確認する
4. PR を投稿する

   ```
   gh pr create --repo <投稿先> --base <base> --head <head> --title "<タイトル>" --body "$(cat <<'EOF'
   <テンプレートを埋めた本文>
   EOF
   )"
   ```

   投稿先と origin が別のリポジトリで、origin が organization の所有（step 2 の `isInOrganization` が true）の場合、`gh pr create` の `--head <owner>:<ブランチ>` は使えない。代わりに REST API で投稿する。

   ```
   gh api repos/<投稿先>/pulls -f base=<base> -f head=<origin の owner>:<ブランチ> -f title="<タイトル>" -f body="$(cat <<'EOF'
   <テンプレートを埋めた本文>
   EOF
   )" --jq '.html_url'
   ```

完了後は PR の URL を表示すること。

## 注意事項

- `gh` コマンドはユーザーの承認を経て実行する（ユーザーが事前に承認済みの範囲を除く）。読み取り用の `gh` コマンドは、初めて実行する前に実行予定のものをまとめて示し、一度に承認を得てよい。投稿の承認とは別に扱う
- `gh` コマンドが未認証の場合は `gh auth login` を案内して中断すること
- ブランチ作成・コミット・`git add`・force push は一切行わないこと

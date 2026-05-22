---
name: pr
description: 現在の作業ブランチのコミット済み変更で GitHub PR を作成する。ユーザーが「PR を作って」「プルリクを出して」と依頼した時、または `/pr` と入力した時に使用する。
---

# PR 作成スキル

現在の作業ブランチのコミット済み変更を対象に GitHub PR を作成する。ステージング済み・未コミットの変更は一切対象外とする（コミット・`git add` は行わない）。

## 1. コンテキスト収集

以下を Bash ツールで実行し、現在の状態を把握する。

- 現在のブランチ: `git branch --show-current`
- リモートとの差分（PR に含まれるコミット）:
  ```
  git log --oneline @{u}..HEAD 2>/dev/null || git log --oneline $(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master 2>/dev/null)..HEAD 2>/dev/null
  ```
- PR に含まれる変更（コミット済みのみ）:
  ```
  git diff $(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master 2>/dev/null) HEAD 2>/dev/null || git diff @{u}..HEAD 2>/dev/null
  ```
- ステージング・未コミットの状態: `git status --short`
- PR テンプレート検索:
  ```
  find . -maxdepth 4 \( -path "*/.github/PULL_REQUEST_TEMPLATE/*.md" -o -name "PULL_REQUEST_TEMPLATE.md" -o -name "pull_request_template.md" \) -not -path "*/node_modules/*" 2>/dev/null
  ```
- organization の取得: `git remote get-url origin | sed 's|.*github\.com[:/]\([^/]*\)/.*|\1|'`

## 2. 前提確認

以下の条件を確認し、問題がある場合は**作業を中断してユーザーに報告**すること。

- `main` / `master` ブランチにいる場合は中断する（PR 作成には作業ブランチが必要）
- リモートより先行するコミットが存在しない場合（PR に含む変更がない）は中断する
- **ステージング済み・未コミットの変更は PR の対象外**とし、コミット・ステージングは一切行わない

## 3. プッシュ

コミット済みの変更をリモートにプッシュする。

```
git push -u origin <現在のブランチ名>
```

すでにリモートと同期済みの場合はスキップする。

## 4. PR テンプレート読み込み

以下の優先順位でテンプレートを探す。**ファイル名は固定せず、必ず一覧取得してから読み込むこと。**

**優先順位:**

1. **リポジトリのテンプレート**（コンテキスト収集の `find` 結果を使う）
   - `.github/PULL_REQUEST_TEMPLATE.md` / `.github/pull_request_template.md`
   - `.github/PULL_REQUEST_TEMPLATE/*.md`（複数バリアント）
   - `docs/PULL_REQUEST_TEMPLATE.md` / `PULL_REQUEST_TEMPLATE.md`
   - **複数ある場合は PR の内容に合うものを自分で選ぶ**（後述）

2. **organization の共通テンプレート**（リポジトリに存在しない場合）

   コンテキスト収集で取得した org 名を使い、`gh api` でディレクトリ一覧を取得してから内容を読み込む。`gh api` は Base64 エンコードで返すので `base64 -d` でデコードする。

   ```bash
   # Step 1: ディレクトリ一覧を取得してファイル名を確認する
   gh api repos/<org>/.github/contents/.github 2>/dev/null | jq -r '.[].name'

   # Step 2: 見つかったファイル名で内容を取得する
   gh api repos/<org>/.github/contents/.github/<実際のファイル名> --jq '.content' | base64 -d 2>/dev/null

   # PULL_REQUEST_TEMPLATE/ ディレクトリがある場合
   gh api repos/<org>/.github/contents/.github/PULL_REQUEST_TEMPLATE 2>/dev/null | jq -r '.[].name'
   ```

   **複数ある場合は PR の内容に合うものを自分で選ぶ**（後述）

3. **デフォルト構成**（上記どちらも存在しない場合）

```
## Summary
（変更の目的・背景）

## Detail
- （変更の詳細）

## Test
- （動作確認の手順）
```

**テンプレートが複数ある場合:**

ファイル名・`name` フィールド・`about` フィールドと、PR の内容を照合して最も適切なものを自分で選ぶ。判断基準：

- バグ修正 → bug fix 系
- 新機能 → feature 系
- ドキュメント変更 → docs 系
- リファクタリング → refactor / chore 系

どのテンプレートにも当てはまらない、または甲乙つけがたい場合に限りユーザーに確認する。

## 5. PR プレビュー表示・承認確認

以下の形式で PR の内容をユーザーに提示し、**必ず承認を得てから投稿**すること。承認が得られない場合は中断する。

```
---
タイトル: <英語タイトル>
ブランチ: <現在のブランチ> → main

<テンプレートを埋めたボディ>
---
この PR を投稿しますか？
```

- **タイトルは英語**（例: `Add user authentication`, `Fix null pointer exception`）
- **ボディは日本語**でテンプレートを埋めること。**文体は常体（だ・である調）とし、ですます調は使用しないこと**（例: ×「認証機能を追加します」 → ○「認証機能を追加する」）
- ステージング済み・未コミットの変更は PR の説明に含めないこと
- 関連する issue がある場合は、テンプレートの該当箇所に prefix を付けて明示すること
  - `close #123` / `fix #123` — PR マージ時に issue を自動クローズする
  - `ref #123` — 参照のみ（クローズしない）
  - 複数ある場合はそれぞれ記載する（例: `close #12, ref #34`）
  - issue が不明な場合はコミットメッセージやブランチ名から推測し、確認できない場合は省略する

## 6. PR 内容と変更差分の整合性確認

ユーザーの承認後、投稿する直前に、PR の内容と「コンテキスト収集」で取得した変更差分（コミット済みの diff）に齟齬がないか自己レビューする。

**確認観点:**

- PR に記載した変更点が実際の diff にすべて含まれているか（実在しない変更を記載していないか）
- diff に含まれる重要な変更が PR 本文から漏れていないか
- 影響範囲・テスト手順がコード変更と整合しているか
- `close #123` などの issue 参照が、実際の変更内容と関連しているか

**齟齬があった場合:**

PR 本文を書き直し、修正後の内容を**再度ユーザーに提示して承認を得る**こと（step 5 のフォーマットに従う）。承認なしで step 7 に進んではならない。

齟齬がなければそのまま step 7 に進む。

## 7. PR 投稿

ユーザーの承認を得た後にのみ実行する。

```
gh pr create --title "<英語タイトル>" --body "$(cat <<'EOF'
<テンプレートを埋めたボディ>
EOF
)"
```

完了後は PR の URL を表示すること。

## 注意事項

- `gh` コマンドが未認証の場合は `gh auth login` を案内して中断すること
- ブランチ作成・コミット・`git add` は一切行わないこと

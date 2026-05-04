---
description: GitHubのIssue/PR状態を取得し、ObsidianボルトのFamilyRecorderドキュメントを最新状態に更新する
---

GitHubの最新状態をもとに、Obsidianのドキュメントを更新してください。

## ドキュメントパス

`/Users/kikuchitakashi/Library/Mobile Documents/iCloud~md~obsidian/Documents/my-vault/アプリ開発/FamilyRecorder/`

## 手順

1. 以下の情報を取得する：
   - `gh issue list --state all --limit 50 --json number,title,state,labels` でIssue一覧
   - `gh pr list --state all --limit 20 --json number,title,state,mergedAt` でPR一覧
   - `git log --oneline -10` で最近のコミット
2. ドキュメントパス配下の既存ファイルを確認する（`ls`）
3. `issues.md` が存在する場合は内容を読んで更新する。なければ新規作成する。
   - オープンなIssueを優先度・カテゴリ別に整理
   - クローズ済みIssueも実装済み機能として記録
4. 必要に応じて `CHANGELOG.md` や `README.md` も更新する
5. 更新したファイルの一覧と変更内容の概要を報告する

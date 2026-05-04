---
description: オープンなIssueを一覧表示し、選んだIssueのfeatureブランチを切って実装準備を整える
---

次に着手するIssueを選択して、featureブランチを作成してください。

## 手順

1. `gh issue list --state open --json number,title,labels` でオープンなIssueを一覧取得する
2. 以下の形式で一覧を表示する：

```
## オープンなIssue一覧

| # | タイトル | ラベル |
|---|---------|--------|
| 23 | 一覧画面：一括削除機能の追加 | - |
| 24 | 一覧画面：ファイルの会話量を表示 | - |
...
```

3. $ARGUMENTSが指定されていればその番号のIssueを、なければユーザーに番号を聞く
4. 選択されたIssueの詳細を `gh issue view <number>` で取得して表示する
5. Issue番号とタイトルからブランチ名を生成する
   - 形式: `feature/issue-<number>-<slug>`
   - slugはタイトルを英語の単語2〜3語に要約したkebab-case（例: `bulk-delete`, `conversation-stats`）
6. `git checkout main && git pull` でmainを最新に更新する
7. `git checkout -b feature/issue-<number>-<slug>` でブランチを作成する
8. ブランチ作成完了を報告し、Issueの要件を箇条書きで整理して「実装を開始できます」と伝える

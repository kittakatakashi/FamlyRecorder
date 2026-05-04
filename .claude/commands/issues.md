---
description: GitHubのオープンなIssue一覧を番号・タイトル・ラベル付きで表示する
---

`gh issue list --state open --json number,title,labels,createdAt` を実行し、以下の形式で表示してください。

```
## オープンなIssue一覧

| # | タイトル | ラベル |
|---|---------|--------|
| 26 | プレイヤー画面：文字起こしテキストの表示 | - |
...
```

件数も最後に `（全N件）` と添えてください。

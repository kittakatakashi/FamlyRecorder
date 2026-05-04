---
description: 現在ブランチのPRレビューコメントを確認し、未対応の指摘を整理して対応方針を提案する
---

現在のブランチに紐づくオープンなPRのレビューコメントを確認してください。

## 手順

1. `git branch --show-current` で現在のブランチ名を取得する
2. `gh pr list --head <branch> --json number,title,url` でそのブランチのPR番号を取得する
   - PRがなければ「現在のブランチにオープンなPRはありません」と伝える
3. `gh pr view <number> --comments` で全体コメントを取得する
4. `gh api repos/{owner}/{repo}/pulls/<number>/comments` でインラインコメント（ファイル指定の指摘）を取得する
   - owner/repo は `gh repo view --json nameWithOwner -q .nameWithOwner` で取得する
5. 取得したコメントを以下の形式で整理して表示する：

```
## PRレビューコメント一覧（PR #<number>）

### インラインコメント
- [<ファイル>:<行>] <優先度バッジ> **<タイトル>**
  <内容の要約>

### 全体コメント
- <author>: <内容の要約>
```

6. 未対応と思われる指摘があれば「対応が必要な指摘」としてまとめ、各指摘に対する修正方針を簡潔に提案する
7. ユーザーに「対応しますか？」と確認する

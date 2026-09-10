---
name: safe-push
description: "現在のブランチを push する。特に rebase や fold の後の force-push で使う。lease を実際のリモート tip に固定し、浮いた fixup!/amend! を拒否し、200 行を超える書き換えはレビュー用ブランチに逃がし、旧 tip を archive タグで残せる。git push --force-with-lease を生で叩く代わりに使う。"
argument-hint: "[--remote <name>] [--approved] [--archive <reason>]"
allowed-tools: Bash
---

# /git:safe-push

push、特に履歴を書き換えた後の push は `safe-push.sh` で行う。

```bash
PUSH=<this skill dir>/safe-push.sh

$PUSH                          # 通常
$PUSH --archive pre-fold       # 旧 tip を archive/<branch>/<date>-pre-fold として先に push
$PUSH --approved               # 200 行超の書き換えを、ユーザー承認後に push
$PUSH --remote upstream        # origin 以外
```

拒否されたとき:

| メッセージ | 対応 |
|---|---|
| floating fixup!/amend! commits present | `/git:fold` で折り込んでから再実行 |
| old->new tree diff is N lines (> 200) | `git push origin HEAD:<branch>-rework` してユーザーに確認。承認後に `--approved` |
| remote tip ... is not present locally | `git fetch <remote>` してから再実行 |

書き換え前の SHA が Issue や PR コメントに引用されているなら `--archive
<reason>` を付ける。閾値は `GIT_SAFE_PUSH_REVIEW_THRESHOLD` で変えられる。

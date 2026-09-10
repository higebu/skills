---
name: fold
description: "ステージした差分や書き直したコミットメッセージを、履歴上の特定コミットに折り込む(fixup / amend)。git commit --fixup + rebase --autosquash、rebase -i での reword、git commit --amend の代わりに使う。対象を SHA で指定するので、件名の重複や amend! の書式不備で無言で失敗しない。"
argument-hint: "fixup <sha> | amend <sha> <msg-file> | all <base> | check <base>"
allowed-tools: Bash, Read
---

# /git:fold

履歴の書き換えは生の `--fixup` / `--autosquash` / `--amend` / `rebase -i`
ではなく `fold.sh` で行う。

```bash
FOLD=<this skill dir>/fold.sh

$FOLD fixup <target-sha>             # ステージした差分を <sha> に折り込む
$FOLD amend <target-sha> <msg-file>  # <sha> のメッセージを <msg-file> で置き換える
$FOLD all <base-ref>                 # 浮いている fixup!/amend! を全部折り込む
$FOLD check <base-ref>               # 検証だけ
```

| やりたいこと | 手順 |
|---|---|
| レビュー指摘を該当コミットに反映 | `git add -p` → `fold.sh fixup <sha>` |
| 件名や本文の書き直し | 完全なメッセージ(trailer 込み)をファイルに書く → `fold.sh amend <sha> <file>` |
| 直前のコミットへの追加 | `fold.sh fixup HEAD` |
| 既にある `fixup!` の処理 | `fold.sh all <base>` |

- 作業ツリーに unstaged の変更があると拒否される。先に stash するか含める。
- `amend` のメッセージは `check-msg.sh` (`/git:commit-message`) を通らないと
  拒否される。メッセージを直してから再実行する。
- `all` が「件名が曖昧」で拒否したら、その fixup は `fixup` / `amend` で
  SHA を指定して個別に折り込む。
- rebase が衝突したら自動で abort され、ブランチは元に戻る。差分は
  ステージし直されているので、対象を変えるか衝突を解消してから再実行する。
- 折り込んだら `/git:safe-push` で push する。

メッセージ検査を差し替えるには `GIT_FOLD_MSG_CHECK=<command>`(`--text
<message>` で呼ばれ、非 0 で違反)。空にすると検査しない。

---
name: commit-message
description: "コミットメッセージを書く・直す・検査する。git commit の直前、rebase で件名や本文を書き換えるとき、既存コミットのメッセージを監査するときに使う。Conventional Commits のリポジトリにも kernel 風 subsystem prefix のリポジトリにも当てはまる。check-msg.sh が機械的に検査できる部分を検査する。"
argument-hint: "[--range <base>..HEAD | --last-commit]"
allowed-tools: Read, Bash, Grep, Glob
---

# コミットメッセージ

各コミットは単独で自分を正当化する。PR 本文もレビューのスレッドも
`git log` からは見えない。

## 手順

1. リポジトリの流儀を読む。

   ```bash
   git log --no-merges --format='%s' -30          # 件名の形式
   git log --no-merges --format='%B' -5 -- <path> # 触る領域の本文の密度
   ```

   件名は既存の多数派に合わせる。

   | 形式 | 例 |
   |---|---|
   | Conventional Commits | `fix(tools): keep MCP tool descriptions under 1024 characters` |
   | subsystem prefix | `seg6: add support for the SRv6 End.M.GTP6.D behavior` |

   本文の長さも既存に合わせる。

2. `git diff --cached` を読んでから書く。記憶や計画から書かない。

3. 下の「形」に従って書く。

4. commit の前に検査する。

   ```bash
   check-msg.sh --text "$(cat msg.txt)"        # 下書き
   check-msg.sh --file .git/COMMIT_EDITMSG     # エディタ経由
   check-msg.sh --last-commit                  # コミット直後の監査
   check-msg.sh --range main..HEAD             # ブランチ全体
   check-msg.sh --style prefix --text ...      # 件名形式の自動判定を上書き
   ```

   `check-msg.sh` はこのスキルのディレクトリにある。

## 形

```
<prefix>: <何が変わるか、命令形、72 字以内、末尾にピリオドなし>
                                        ← 空行(必須)
<問題。何が困っていて、誰に何が起きるか。>

<変更。何がどう変わるか。差分から読めない「なぜこの方法か」はここ。>
                                        ← 75 桁で折り返す
Fixes: 1234567890ab ("<subject of the broken commit>")   ← 該当時
Closes #123                                              ← GitHub
Signed-off-by: ...                                       ← upstream 向けの木
```

- 件名は「何が変わるか」。ファイル名や作業名 (`update foo.go`, `WIP`,
  `fix review comments`) にしない。
- 件名の直後は空行。
- 本文は 75 桁で自分で折り返す。git は折り返さない。
- 命令形、現在形。"Add", "Fix", "Rewrite"。"Added" / "Adding" /
  "This commit adds" にしない。
- 本文は「なぜ」。問題、利用者への影響、なぜこの方法を選んだか、捨てた
  代替案、測定値。何を変えたかは差分にある。
- 速くなった、小さくなったと書くなら before / after の数値と測定ツール名。
- `Fixes:` は 12 桁以上の SHA と `("件名")`。GitHub では `Closes #N` /
  `Fixes #N` を末尾に置く。
- trailer は末尾に一塊。trailer の後ろに本文を続けない。

## 書かないもの

| 書きがちなもの | 代わりに |
|---|---|
| `This commit adds ...` / `This patch ...` | 削って命令形に |
| `in this series` / `in a later patch` / `previous version` / `as discussed in review` | 書かない。各コミットを自己完結させる |
| レビュアー名、日付、一時的なブランチ名 | `Reviewed-by:` / `Suggested-by:` trailer と `Link:` |
| `Co-Authored-By: Claude ...`、セッション URL、`Generated with ...` | 書かない。upstream 向けの木では `Assisted-by:` trailer |
| 差分の復唱 (`Rename X to Y in foo.c`, 変更したファイル一覧) | 「なぜ」だけ残す |
| 仕様の引き写し (`Section 5.3 says ...`) | 仕様番号への参照 1 行 |
| lint / test が通った | 書かない。CI がないリポジトリだけ 1 行 |
| レビュアー向けの一時的な注記 | PR コメント |

## PR 本文との関係

PR が 1 コミットなら PR 本文と同じ文章でよい (`/pr-description:write`)。
複数コミットなら、PR 本文は全体の問題と方針、各コミットのメッセージは
そのコミットの「なぜ」。

## 例

```
fix(tools): keep MCP tool descriptions under 1024 characters

OpenAI-compatible chat completions APIs reject a tool whose
function.description exceeds 1024 characters, and clients that route
other vendors' models (GitHub Copilot with Gemini, for one) through that
API shape drop the whole tool list when one description is over the cap.
get_asn1 (1160), search (1217) and search_openapi (2320) exceeded it.

Rewrite the three descriptions to fit, moving the FTS5 query syntax and
tokenization notes into the query parameter description, which the cap
does not cover. Add TestToolDescriptionLength, which lists the tools
through an in-memory client session and fails on any description over
1024 characters.
```

## 既存コミットのメッセージを直すとき

`git commit --amend` や `rebase -i` ではなく `/git:fold` の
`fold.sh amend <sha> <msg-file>` を使う。

## 参照

- https://www.kernel.org/doc/html/latest/process/submitting-patches.html
  ("Describe your changes", "The canonical patch format")
- https://git-scm.com/docs/SubmittingPatches
- https://www.ozlabs.org/~akpm/stuff/tpp.txt (§4 Changelog)

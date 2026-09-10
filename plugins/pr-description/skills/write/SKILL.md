---
name: pr-description
description: "プルリクエストのタイトルと本文（およびコミットメッセージ）を短く、自己完結した形で書く。PR を作成する直前、PR 本文を書く・短くする・書き直すよう頼まれたとき、コミットメッセージを書くときに使う。Linux カーネルの changelog の作法（tpp.txt / submitting-patches）を GitHub PR 向けに翻訳したもの。"
argument-hint: "[base ref] (省略時は main)"
allowed-tools: Read, Bash, Grep, Glob
---

# PR 本文の書き方

PR 本文は **将来の読者が `git log` から辿り着く changelog** であって、
設計書でもレビュー日誌でもない。差分そのものが記録なので、差分を読めば
分かることは書かない。

一次ソース:

- Andrew Morton, *The perfect patch* — https://www.ozlabs.org/~akpm/stuff/tpp.txt
  (§4 Changelog: なぜ必要だったか / 設計方針 / 実装の要点 / テスト結果。
  「this patch does ...」を書かない。過去の版に言及しない。恒久的でない
  情報は `---` の下に置く)
- Linux, *Submitting patches* § Describe your changes —
  https://www.kernel.org/doc/html/latest/process/submitting-patches.html#describe-your-changes
  (問題を先に書く。利用者に見える影響を書く。数値で裏付ける。命令形。
  自己完結させる。**説明が長くなるのは分割すべきサイン**)

## 手順

1. 差分を把握する。本文は差分から書く。記憶や計画書から書かない。

   ```bash
   git log --oneline ${BASE:-main}..HEAD
   git diff --stat ${BASE:-main}...HEAD
   git diff ${BASE:-main}...HEAD          # 大きければ主要ファイルだけ
   ```

2. 次の 4 つに一文ずつ答える。答えられない項目は本文に入れない。

   | 問い | 本文での位置 |
   |---|---|
   | 何が困っていたか。利用者に何が起きるか | 第 1 段落 |
   | 何をしたか（何を作ったか、ではなく何が変わるか） | 第 2 段落 |
   | 差分を読んでも意図が分からない箇所はどこか | 箇条書き 3 件まで |
   | CI が確認しないことを、何で確認したか | 最終段落 |

3. 書く。下の「形」に従う。

4. 検査する。

   ```bash
   wc -w body.md            # 250 語以下。超えたら削るか PR を分ける
   grep -nE 'This PR|this patch|Generated|claude\.ai|review pass|findings|last commit|Phase [0-9]' body.md
   ```

   grep に当たった行は書き直す（理由は「書かないもの」参照）。

## 形

```
<type>(<scope>): <何が変わるか、命令形、72 字以内>

<問題。何が困っていて、利用者に何が起きるか。1〜3 文。>

<変更。何がどう変わるか。設計の要点はここに 1〜2 文。>

<差分から読み取れない意図だけを箇条書き。省略可。>
- ...

Closes #NNN                       <あれば>

<CI が確認しないことをどう確認したか。1〜3 文。>
```

- **見出しは要らない。** 段落の順序が構造になる。見出しを置くと「埋めるべき
  欄」に見えて、書くことがない欄まで埋めてしまう。3 段落を超える本文にだけ
  `## Problem` / `## Changes` / `## Testing` を許す。
- **タイトルは Conventional Commits。** タイトルは PR の永続的な識別子になる
  (tpp §2)。`fix(tools): keep MCP tool descriptions under 1024 characters` のように
  「何が変わるか」を書き、ファイル名や作業名を書かない。
- **命令形、現在形。** "Add `get_tdoc`" であって "This PR adds" ではない
  (submitting-patches)。PR であることは読者が知っている (tpp §4c)。
- **数値で裏付ける。** 速くなった、小さくなったと書くなら before / after の数を
  書く。逆に、トレードオフやコストも書く。
- **Issue は `Closes #N` / `Fixes #N`** の行で参照する。議論の要点は本文に
  要約し、リンク先を読まないと分からない本文にしない。
  https://docs.github.com/en/issues/tracking-your-work-with-issues/using-keywords-in-issues-and-pull-requests
- 英語で書く。セッション URL や生成ツールの署名は入れない。

## 書かないもの

| 書きがちなもの | どこへ行くべきか |
|---|---|
| パッケージごとの「どう動くか」の解説 | AGENTS.md / README / パッケージの doc comment。**将来の読者は PR ではなくそこを読む** |
| ファイル一覧、関数名の列挙 | 差分。`Files changed` タブが既にある |
| `gofmt` / `go vet` / lint / `go test` が通った | CI。CI が走らないリポジトリでだけ一行書く |
| レビューで N 件指摘され最後のコミットで直した | 書かない。**本文は最終状態だけを、自己完結で説明する** (tpp §4d)。レビューの経過は PR のコメント欄にある |
| 「計画の Phase 1」「前回の PR に続いて」 | 範囲外は "Out of scope:" の一文にする。計画そのものは書かない |
| 既知の制限の長いリスト | ドキュメント。利用者に影響するものだけ一文で |
| 「この PR は…」「本 PR では…」 | 削って命令形にする |
| レビュアーへの一時的な注意 (「この 2 ファイルは移動だけ」) | 本文の末尾に `---` を置きその下に書く (tpp §4g)。マージ後には意味を持たない情報だと分かる |

## 長くなったら

本文が 250 語を超える、または「変更」段落が 2 つ以上の独立した話を含むなら、
**本文を圧縮する前に PR の分割を検討する** (submitting-patches: "If your
description starts to get long, that's a sign that you probably need to split
up your patch")。#240 の例なら、リファクタリング (`ondemand` の切り出し) と
パーサーの新オプション (`KeepPreamble`) は、それぞれ先行 PR にできた。
準備的な変更を先に、機能を後に (tpp §6d)。

分割できないときも本文は伸ばさない。詳細は各コミットのメッセージと
ドキュメントに置き、本文にはそこへの道筋だけを残す。

## 例

### Before (higebu/3gpp-mcp#240、約 700 語)

```
## Summary

The 3GPP FTP site holds far more than `Specs/archive`: ... This PR reads
those documents on demand, ... and exposes them through a new MCP tool
`get_tdoc`, a CLI command `get-tdoc` and web pages under `/tdocs`.

Phase 1 of the plan: ... Meeting listings, TDoc-list search and structured
CR cover-sheet extraction are left for later PRs.

## How it works

- **`internal/tdoc`** locates a document. A TDoc number (...) maps to its
  group's FTP folder through a prefix table; the group's DynaReport meeting
  page (...) gives every meeting's folder and TDoc number range, so ...
  (5 段落、各 5〜8 行。パッケージごとの動作解説)

## Verification

- `gofmt`, `go vet`, `golangci-lint run` (0 issues), `go test -race -short ./...` all pass.
- Live checks against the FTP site: ... (7 件列挙)
- An `ocr review` pass over the branch produced 8 findings; all were verified
  against the code and fixed in the last commit with regression tests (...).

## Known limitations

- (4 件)
```

何が悪いか: 「How it works」は AGENTS.md に書くべき内容で、PR がマージされた
後は誰も PR を開いて読まない。lint と test は CI が示す。レビュー経過は
最終状態の説明ではない。「Phase 1 of the plan」は読者の知らない計画への参照。

### After (約 220 語)

```
feat: on-demand access to 3GPP meeting documents (TDocs)

Every 3GPP meeting publishes its contributions, CRs, liaison statements and
reports under `<group>/<meeting>/Docs/` on the FTP site, but the server only
knows `Specs/archive`. Reading a CR or an LS today means leaving the tool,
finding the folder and opening the zip by hand.

Add `get_tdoc` (MCP), `get-tdoc` (CLI) and `/tdocs` (web) to read one
document by TDoc number (`R1-2509715`) or FTP path. The document is fetched,
converted and cached on demand in a separate SQLite file, like archived spec
versions; it never enters the main database or search.

Changes outside the new packages that the diff does not explain by itself:
- `docx.ParseOptions.KeepPreamble` keeps content before the first heading as
  section `""`. Off by default, so spec output is unchanged; for a CR that
  section is the cover sheet the converter used to drop.
- The single-flight fetch logic moves from `versionstore` into
  `internal/ondemand`, shared by both stores.

Out of scope: meeting listings, TDoc search and CR cover-sheet extraction.
`.pptx`/`.xlsx`/`.pdf` bodies are not converted; the tool returns the file
list and URL instead.

Tested live against the FTP site with a CR, an LS with a nested attachment,
a meeting report by path (111 sections, 93 images) and a 2010 `.doc`
(LibreOffice conversion, ~8 s).
```

## コミットメッセージ

同じ規則が 1 コミットにも当てはまる。1 行目はタイトルと同じ形式で 50 字を目安、
本文は「なぜ」を書く。PR が 1 コミットなら本文とコミットメッセージは同じ
文章でよい。複数コミットなら、PR 本文に書かなかった詳細は該当コミットの
メッセージに置く。

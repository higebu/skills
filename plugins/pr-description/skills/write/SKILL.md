---
name: pr-description
description: "プルリクエストのタイトルと本文を短く、自己完結した形で書く。PR を作成する直前、PR 本文を書く・短くする・書き直すよう頼まれたときに使う。"
argument-hint: "[base ref] (省略時は main)"
allowed-tools: Read, Bash, Grep, Glob
---

# PR 本文の書き方

PR 本文は changelog であって、設計書でもレビュー日誌でもない。差分を読めば
分かることは書かない。

## 手順

1. 差分から書く。記憶や計画書から書かない。

   ```bash
   git log --oneline ${BASE:-main}..HEAD
   git diff --stat ${BASE:-main}...HEAD
   git diff ${BASE:-main}...HEAD          # 大きければ主要ファイルだけ
   ```

2. 次の 4 つに一文ずつ答える。答えられない項目は本文に入れない。

   | 問い | 本文での位置 |
   |---|---|
   | 何が困っていたか。利用者に何が起きるか | 第 1 段落 |
   | 何が変わるか | 第 2 段落 |
   | 差分を読んでも意図が分からない箇所はどこか | 箇条書き 3 件まで |
   | CI が確認しないことを、何で確認したか | 最終段落 |

3. 下の「形」に従って書く。

4. 検査する。

   ```bash
   wc -w body.md            # 250 語以下。超えたら削るか PR を分ける
   grep -nE 'This PR|this patch|Generated|claude\.ai|review pass|findings|last commit|Phase [0-9]' body.md
   ```

   grep に当たった行は書き直す。

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

- 見出しは付けない。3 段落を超える本文にだけ `## Problem` / `## Changes` /
  `## Testing` を許す。
- タイトルは Conventional Commits。「何が変わるか」を書き、ファイル名や
  作業名にしない。
- 命令形、現在形。"Add `get_tdoc`" であって "This PR adds" ではない。
- 速くなった、小さくなったと書くなら before / after の数値。トレードオフも書く。
- Issue は `Closes #N` / `Fixes #N` の行で参照し、議論の要点は本文に要約する。
- 英語で書く。セッション URL や生成ツールの署名は入れない。

## 書かないもの

| 書きがちなもの | 代わりに |
|---|---|
| パッケージごとの「どう動くか」の解説 | AGENTS.md / README / doc comment に書く |
| ファイル一覧、関数名の列挙 | 書かない。差分にある |
| lint / test が通った | 書かない。CI がないリポジトリだけ 1 行 |
| レビューで N 件指摘され最後のコミットで直した | 書かない。本文は最終状態だけを説明する |
| 「計画の Phase 1」「前回の PR に続いて」 | 範囲外は "Out of scope:" の一文 |
| 既知の制限の長いリスト | ドキュメントに書く。利用者に影響するものだけ一文 |
| 「この PR は…」 | 削って命令形に |
| レビュアーへの一時的な注意 | 本文末尾に `---` を置き、その下に書く |

## 長くなったら

本文が 250 語を超える、または「変更」段落が独立した話を 2 つ以上含むなら、
圧縮する前に PR の分割を検討する。準備的な変更(リファクタリング、新オプション)
を先行 PR にし、機能を後にする。分割できないときも本文は伸ばさず、詳細は
各コミットのメッセージ (`/git:commit-message`) とドキュメントに置く。

## 例

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

## 参照

- https://www.ozlabs.org/~akpm/stuff/tpp.txt (§4 Changelog)
- https://www.kernel.org/doc/html/latest/process/submitting-patches.html#describe-your-changes
- https://docs.github.com/en/issues/tracking-your-work-with-issues/using-keywords-in-issues-and-pull-requests

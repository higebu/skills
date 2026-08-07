---
name: ocr-review
description: "open-code-review (ocr) で変更差分をレビューする。コミット前・プッシュ前・PR を出す前に自分の変更を確認したいとき、ブランチ間の差分をレビューしたいときに使う。日常の開発フローで最も使う ocr の使い方。事前に /ocr-setup が必要。"
---

# ocr による差分レビュー

日常的に使うのはこちら。PR を出す前に自分の変更を見てもらう。

未設定なら先に `/ocr-setup` を実行すること。

## 基本

```bash
# 作業ツリーの変更（staged / unstaged / untracked）
ocr review --provider opencode-go --model deepseek-v4-flash

# ブランチ間
ocr review --from main --to HEAD --provider opencode-go --model deepseek-v4-flash

# 単一コミット（親との差分）
ocr review -c <commit> --provider opencode-go --model deepseek-v4-flash
```

モデル名は接頭辞なしで指定する（`opencode-go/...` 形式は opencode CLI の記法）。

## ⚠️ 背景コンテキストのフラグを間違えない

**2 つあり、型が違う。取り違えると無言で失敗する。**

| フラグ | 受け取るもの | `ocr review` | `ocr scan` |
|---|---|---|---|
| `-b, --background` | **文字列そのもの** | あり | あり |
| `-B, --background-file` | **ファイルのパス** | あり | **存在しない** |

**最も危険なのは `-b` にファイル名を渡すこと。**

```bash
ocr review -b AGENTS.md ...     # ✗ 「AGENTS.md」という 9 文字が渡るだけ
```

エラーも警告も出ず、背景を渡したつもりで何も渡っていない状態になる。
`-b` は必ず**中身**を渡す。

```bash
ocr review -b "fix(auth): reject expired refresh tokens" ...   # ○ 短い文字列
ocr review -b "$(cat /tmp/bg.md)" ...                          # ○ ファイルの中身を展開
ocr review -B /tmp/bg.md ...                                   # ○ パスを渡す
```

補足:

- `-B` は公式 CLI リファレンスに記載がない（動作は確認済み）。文書化された範囲で
  済ませたいなら `-b "$(cat ...)"` を使う
- **8,000 文字の上限チェックは `-B` にしかない。** `-b` は超過しても黙って実行される。
  `-b` を使うなら `wc -c` で自分で確認する
- **`ocr scan` に `-B` はない。** 渡すと `unknown shorthand flag: 'B' in -B` で即エラー。
  scan では `-b "$(cat ...)"` を使う（→ `/ocr-scan`）

## 変更の意図を渡す（最も効果が大きい）

**`--background` はレビュー品質を最も左右する引数。** プロンプト内では
`### Requirement Background` という見出しで注入され、「この変更が何をしようとしているか」
をモデルに伝える。意図が分からないと、モデルは差分から意図を推測するしかない。

PR タイトル1行でも効果がある。Conventional Commits 形式だとさらに効く。

```bash
ocr review --from main --to HEAD \
  -b "fix(auth): reject expired refresh tokens" \
  --provider opencode-go --model deepseek-v4-flash
```

## プロジェクトの不変条件が絡む変更

意図だけでは足りない場合がある。**記法・データ形式・呼び出し規約といった契約に
触れる変更**は、差分の中を見るだけでは壊れることが分からない。エスケープやバリデーションの
追加のように「差分だけ見れば無害」なものが、消費側の前提を静かに破ることがある。

このとき、**意図の後ろにプロジェクトの不変条件を連結**して渡す。

```bash
{
  echo "## この変更について"; echo
  git log -1 --format='%s%n%n%b'    # または PR のタイトルと本文
  echo; echo "---"; echo
  echo "## プロジェクトの不変条件（この変更が壊してはいけないもの）"; echo
  cat AGENTS.md
} > /tmp/bg.md

wc -c /tmp/bg.md    # 8000 未満であること

ocr review --from main --to HEAD -B /tmp/bg.md --max-tools 100 \
  --provider opencode-go --model deepseek-v4-flash --timeout 30
```

この順序には理由がある。

- **意図を先頭に置く。** 見出しが `Requirement Background` なので、枠と内容が一致する
- **不変条件には「この変更が壊してはいけないもの」という見出しを付ける。**
  これがないと、モデルが不変条件を「この変更が実装すべき要件」と誤読しうる

| フラグ | 役割 |
|---|---|
| `-B` / `-b "$(cat ...)"` | 意図と不変条件。「どこを疑うべきか」を与える |
| `--max-tools` | 1 ファイルあたりのツール呼び出し上限。「そこまで辿り着く余力」を与える |

**片方だけでは効かない。** 背景だけ与えると探索が深まった結果、既定のツール予算を
使い切って結論を出せず `failed` で終わる。必ず両方を指定する。

制約とコスト:

- **背景は 8,000 文字が上限。** `-B` なら超過時にエラーで止まるが、`-b` は黙って通る
- **簡潔な文書ほど効果的。** 網羅的な文書はノイズになり、探索が迷走してコストも跳ね上がる。
  「コードを読めば分かること」を削り、**コードからは発見できない不変条件と落とし穴だけ**を
  残した文書が最も機能する
- 通常のレビューよりコストは数倍になる。ただし 2 回目以降は入力の大半がキャッシュヒットする
- 常用せず、契約に触れる変更に限定する

### 補足: 背景と `--rule` の使い分け

`ocr` にはルール層（`--rule` / `<repo>/.opencodereview/rule.json` /
`~/.opencodereview/rule.json` / 組み込み）があり、プロンプト内では
`### Review Checklist` として注入される。恒久的なレビュー観点の正しい置き場所はこちら。

ただし**ルールはマージではなく置換**で、最初に一致したパターンだけが有効になる。
`{"path": "**/*.go", "rule": "..."}` を書くと、組み込みの Go ルール（1万字超の
「精度優先」「go vet が判定できることは重複報告するな」等を含む詳細な指針）が
**丸ごと失われる**。偽陽性が増える方向に効くため、安易に使わないこと。

```bash
# 有効なルールと層を確認
ocr rules check path/to/file.go
# Source: System built-in  → 組み込みが効いている
# Source: Custom (--rule)  → 独自ルールが組み込みを上書きしている
```

同期コストが継続的に発生するため、当面は背景に不変条件を含める運用でよい。

## 使いどころ

| タイミング | コマンド |
|---|---|
| コミット前に手元の変更を確認 | `ocr review -b "<意図>"` |
| プッシュ前にブランチ全体を確認 | `ocr review --from main --to HEAD -b "<意図>"` |
| 契約・記法・データ形式に触れる変更 | `-B <意図+不変条件>.md --max-tools 100` |

## 実行回数

差分レビューは通常 **1 回**でよい。見落としのコストが高い変更
（セキュリティ、並行性、データ移行、契約変更）では **2 回**まわして結果を合わせる。

3 回以上は費用対効果が落ちる。同じ予算を使うなら、回数を増やすより
背景と `--max-tools` で 1 回の深さを上げる方が効く。

**同じモデルを何回まわしても、そのモデルが構造的に見落とすバグには到達できない。**
契約変更のように見落としが高くつく差分では、`ocr delegate` で解決済みのルールを
取り出し、**系統の違うモデル（Claude opus など）に 1 回レビューさせる**方が効く。

```bash
ocr delegate rule $(git diff --name-only main...HEAD) > /tmp/ocr_rule.txt
```

取り出したルールをチェックリストとして opus の subagent に渡す。手順は
`/ocr-scan` の「系統の違うモデルで 1 回追加する」に詳しい——**haiku は使わないこと**を
含め、そちらの注意書きがそのまま当てはまる。

なおこの相補性は全ファイル監査で実測したもので、差分レビューでの効果は未計測。

## 出力の扱い

機械的に処理するなら JSON で受ける。

```bash
ocr review --format json > review.json
```

**必ず `status` と `warnings` を先に見る。** タイムアウトしたファイルは指摘ゼロで返るため、
「問題なし」と見分けがつかない。

```bash
python3 - <<'PY'
import json
d = json.load(open('review.json'))
print('status:', d['status'], '|', d.get('message', ''))
for w in (d.get('warnings') or []):
    print('!! レビュー未実行:', w['file'], '-', w['message'])
rank = {'high': 0, 'medium': 1, 'low': 2}
for c in sorted(d.get('comments') or [], key=lambda c: rank.get(c.get('severity'), 3)):
    print(f"[{c.get('severity')}/{c.get('category')}] {c['path']}:{c.get('start_line')}")
    print('   ', c['content'][:200].replace('\n', ' '))
PY
```

`status` が `failed` の場合、`comments` は `null` になる（空配列ではない）。
`--max-tools` を上げて再実行する。

## 指摘の検証

指摘はモデルの出力であって事実ではない。修正に着手する前に:

1. 指摘された行を実ファイルで読む。行番号がずれていたり、存在しないコードの話をしていることがある
2. 到達可能性を追う。呼び出し側が保証している不変条件や、プロジェクトの規約文書に反する指摘は偽陽性
3. セキュリティ系はシンクまで経路を追う。エスケープ漏れは、描画側がエスケープしていなければ初めて脆弱性になる
4. **重大度も再現回数も正しさの根拠にならない。** 複数回のレビューで毎回 high と判定された
   指摘が、実際に動かしてみると完全な誤りだったという例は珍しくない。逆に本物のバグが
   数回に1回しか出ないこともある。頻度ではなくコードで判断する
5. 修正には「バグが存在したことを示す回帰テスト」を添える

**明白な修正が別のものを壊す指摘**に注意する。ガード条件の変更は、周囲のコメントが
その条件を意図的にそう書いた理由を説明していないか確認してから行う。

**「安全に見える追加」も疑う。** エスケープやバリデーションの追加は差分だけ見ると
無害だが、その値を消費する側が変換を前提にしていない場合、静かに壊す。

## 自動化

CI では PR タイトルを `--background` に渡すのが公式に推奨されている。

```yaml
- run: |
    ocr review --background "$PR_TITLE" \
      --from "origin/$BASE_REF" --to "origin/$HEAD_REF" \
      --format json --audience agent
```

LLM 呼び出しには時間がかかるため、フックにするなら差分が小さいことを前提にするか、
警告のみで失敗させない運用にする。背景 + `--max-tools` を付けた重い構成はフック向きではない。

## 関連スキル

- 差分がない既存コードの監査 → `/ocr-scan`
- 設定・認証 → `/ocr-setup`

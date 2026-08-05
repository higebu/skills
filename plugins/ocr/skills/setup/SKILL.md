---
name: setup
description: "open-code-review (ocr) をインストールし、OpenCode Zen と OpenCode Go の両方をプロバイダとして設定する。ocr review / ocr scan を初めて使うとき、別マシンや CI で環境を作り直すとき、認証エラーやプロバイダ設定の不具合を解決するときに使う。"
---

# ocr のセットアップ

## 1. インストール

```bash
npm install -g @alibaba-group/open-code-review
ocr --version
```

## 2. API キー

環境変数に入れる。Zen・Go のどちらも同じキーを使う。

```bash
export OPENCODE_API_KEY=sk-...
```

**`opencode auth login` は使わない。** TUI 専用のフローで API キーを渡すフラグがなく、
標準入力にパイプしても確定しないため、非対話では完了できない。

## 3. プロバイダを2つ登録

```bash
# OpenCode Zen
ocr config set custom_providers.opencode-zen.url https://opencode.ai/zen/v1
ocr config set custom_providers.opencode-zen.protocol openai
ocr config set custom_providers.opencode-zen.api_key "$OPENCODE_API_KEY"

# OpenCode Go
ocr config set custom_providers.opencode-go.url https://opencode.ai/zen/go/v1
ocr config set custom_providers.opencode-go.protocol openai
ocr config set custom_providers.opencode-go.api_key "$OPENCODE_API_KEY"
```

## 4. 既定のプロバイダとモデルを設定

使えるモデル ID は各エンドポイントに問い合わせて確認する。

```bash
curl -s -H "Authorization: Bearer $OPENCODE_API_KEY" \
  https://opencode.ai/zen/v1/models | jq -r '.data[].id'

curl -s -H "Authorization: Bearer $OPENCODE_API_KEY" \
  https://opencode.ai/zen/go/v1/models | jq -r '.data[].id'
```

返ってきた ID を**接頭辞なしのまま**設定する。

```bash
ocr config set provider opencode-go
ocr config set model deepseek-v4-flash
```

`opencode run -m` は `opencode-go/deepseek-v4-flash` のように `プロバイダ/モデル` 形式を
使うが、`ocr` はモデル ID のみを受け取り、プロバイダは別に指定する。

なお `/ocr:review` / `/ocr:scan` はコマンドラインでプロバイダとモデルを明示するため、
ここでの既定値には依存しない。

## 5. 動作確認

LLM を呼ばずに対象ファイルだけ確認する。

```bash
ocr scan --preview
```

1 ファイルだけ実際に通す。

```bash
ocr scan --path <小さめのファイル> --format json | jq '.status, .summary'
```

`status` が `success` なら設定完了。

## モデル選択について

**モデルの階層名（pro / flash など）を能力の順序と考えない。** レビュー性能は
世代の新しさに強く影響され、上位階層でも古い世代なら新しい下位階層に劣ることがある。

新しいモデルが増えたら、**既知のバグを含むファイルを用意して自分で測る**のが確実。
判断材料は「既知バグの検出率」「所要時間」「コスト」の3つ。

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| 認証エラー | `OPENCODE_API_KEY` と `custom_providers.*.api_key` の両方を再設定する |
| モデルが見つからない | 接頭辞付きの名前（`opencode-go/...`）を渡していないか確認する。`ocr` はモデル ID のみ |
| 特定のモデルだけ見つからない | そのエンドポイントの `/models` に含まれているか確認する。プロバイダ側の設定で無効化されていることがある |
| `context deadline exceeded` | 認証ではなくタイムアウト（→ `/ocr:scan`） |

## 次に使うスキル

- 差分レビュー → `/ocr:review`
- 全ファイル監査 → `/ocr:scan`

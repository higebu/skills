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

環境変数に入れる。Go・Zen のどちらも同じキーを使う。

```bash
export OPENCODE_API_KEY=sk-...
```

**`opencode auth login` は使わない。** TUI 専用のフローで API キーを渡すフラグがなく、
標準入力にパイプしても確定しないため、非対話では完了できない。

## 3. プロバイダを登録

```bash
# OpenCode Go（通常はこちらを使う）
ocr config set custom_providers.opencode-go.url https://opencode.ai/zen/go/v1
ocr config set custom_providers.opencode-go.protocol openai
ocr config set custom_providers.opencode-go.api_key "$OPENCODE_API_KEY"

# OpenCode Zen（Go を契約していない環境向けのフォールバック）
ocr config set custom_providers.opencode-zen.url https://opencode.ai/zen/v1
ocr config set custom_providers.opencode-zen.protocol openai
ocr config set custom_providers.opencode-zen.api_key "$OPENCODE_API_KEY"
```

Go を契約している場合、Zen 側の無料モデル（`-free` 付き）を使う理由はない。
無料モデルは context が小さく低速で、契約下では節約にもならない。

## 4. 既定のプロバイダとモデルを設定

使えるモデル ID は各エンドポイントに問い合わせて確認する。

```bash
curl -s -H "Authorization: Bearer $OPENCODE_API_KEY" \
  https://opencode.ai/zen/go/v1/models | jq -r '.data[].id'

curl -s -H "Authorization: Bearer $OPENCODE_API_KEY" \
  https://opencode.ai/zen/v1/models | jq -r '.data[].id'
```

**⚠️ 必ず provider を先に設定する。** `ocr config set model` は
**アクティブなプロバイダ配下**（`custom_providers.<名前>.model`）に保存されるため、
順序を逆にすると別のプロバイダにモデルが書き込まれ、あとから provider を変えても追従しない。

```bash
ocr config set provider opencode-go      # 先
ocr config set model deepseek-v4-flash   # 後
```

モデル ID は**接頭辞なし**で指定する。`opencode run -m` は
`opencode-go/deepseek-v4-flash` のように `プロバイダ/モデル` 形式を使うが、
`ocr` はモデル ID のみを受け取り、プロバイダは別に指定する。

なお `/ocr:review` / `/ocr:scan` はコマンドラインでプロバイダとモデルを明示するため、
ここでの既定値には依存しない。

## 5. 設定の確認

**`ocr config list` というコマンドは存在しない**（`unknown command "list"`）。
`ocr config` のサブコマンドは `model` / `provider` / `set` / `unset` の 4 つだけ。

現在の設定と疎通は `ocr llm test` で確認する。有効なプロバイダ・URL・モデルを表示し、
実際にエンドポイントを呼んで検証する。

```bash
$ ocr llm test
Source: provider:opencode-go
URL:    https://opencode.ai/zen/go/v1
Model:  deepseek-v4-flash
...
✓ Connection test successful
```

設定ファイルの中身を直接見たい場合はこちら（`~/.opencodereview/config.json`）。

```bash
python3 -c "
import json,os
d=json.load(open(os.path.expanduser('~/.opencodereview/config.json')))
def mask(o):
    if isinstance(o,dict): return {k:('***' if 'key' in k.lower() else mask(v)) for k,v in o.items()}
    return o
print(json.dumps(mask(d), indent=2))
"
```

手動編集は非推奨（次回の `ocr config set` 実行時に再フォーマットされる）。
ただし `timeout_sec` など `ocr config set` が受け付けないキーは直接編集するしかない。

## モデル選択について

**モデルの階層名（pro / flash など）を能力の順序と考えない。** レビュー性能は
世代の新しさに強く影響され、上位階層でも古い世代なら新しい下位階層に劣ることがある。
context や出力上限も階層と一致するとは限らず、上位階層でも同じ値のことがある。

新しいモデルが増えたら、**既知のバグを含むファイルを用意して自分で測る**のが確実。
判断材料は「既知バグの検出率」「所要時間」「コスト」の3つ。

無料モデルは、Go のような定額契約がない環境でのみ検討する。
契約下では context が小さく低速なだけで、得るものがない。

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| `unknown command "list" for "ocr config"` | `ocr config list` は存在しない。`ocr llm test` を使う |
| 意図と違うモデルが使われる | `ocr llm test` で有効なプロバイダとモデルを確認する。`model` は provider 配下に保存されるため、provider を変えた場合は model を設定し直す |
| 認証エラー | `OPENCODE_API_KEY` と `custom_providers.*.api_key` の両方を再設定する |
| モデルが見つからない | 接頭辞付きの名前（`opencode-go/...`）を渡していないか確認する。`ocr` はモデル ID のみ |
| 特定のモデルだけ見つからない | そのエンドポイントの `/models` に含まれているか確認する。プロバイダ側の設定で無効化されていることがある |
| `context deadline exceeded` | 認証ではなくタイムアウト（→ `/ocr:scan`） |

## 次に使うスキル

- 差分レビュー → `/ocr:review`
- 全ファイル監査 → `/ocr:scan`

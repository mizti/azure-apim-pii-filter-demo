# Azure APIM Presidio Demo

顧客サポートメッセージ受付APIを例に、Azure API Management（APIM）でリクエスト本文の個人情報（PII）を検査し、PIIを含まないリクエストだけをバックエンドへ転送するサンプルです。

## 構成

- Azure API Management Developer SKU
- PresidioラッパーAPIをホストするAzure Functions Flex Consumption
- 内部PIIフィルターAPIをホストするAzure Functions Flex Consumption
- VNet統合なし

APIMは顧客サポートメッセージを受け付け、リクエスト本文をPresidio Functionへ送信します。PIIが検出された場合はHTTP `400`を返し、検出されなかった場合だけ内部PIIフィルターFunctionへリクエストを転送します。

詳細は[アーキテクチャ](docs/architecture.md)と[APIインターフェース](docs/api-interfaces.md)を参照してください。

## 前提条件

- Azure CLI（`az`）
- Azure Developer CLI（`azd`）
- `curl`
- `jq`

Azureへログインし、デプロイに使用する値を環境変数へ設定します。

```bash
az login --use-device-code
azd auth login

export AZURE_LOCATION="japaneast"
export PUBLISHER_EMAIL="your-email@example.com"
```

## Functionsのデプロイ

`azd`環境を作成し、2つのFunction Appと関連リソースをデプロイします。

```bash
azd env new apim-presidio-demo
azd env set AZURE_LOCATION "$AZURE_LOCATION"
azd up
```

デプロイ後のリソースグループ名とFunction AppのURLを環境変数へ設定します。

```bash
export RESOURCE_GROUP_NAME="$(azd env get-value RESOURCE_GROUP_NAME)"
export PII_FILTER_FUNCTION_BASE_URL="$(azd env get-value PII_FILTER_FUNCTION_BASE_URL)"
export PRESIDIO_FUNCTION_BASE_URL="$(azd env get-value PRESIDIO_FUNCTION_BASE_URL)"
```

## API Managementのデプロイ

APIM Developer SKUのプロビジョニングには約40分かかるため、Functionsとは分けてデプロイします。

```bash
./tests/02_deploy_apim.sh \
    "$RESOURCE_GROUP_NAME" \
    "$PUBLISHER_EMAIL" \
    "$AZURE_LOCATION"
```

デプロイ完了後、APIM名とゲートウェイURLを環境変数へ設定します。

```bash
export APIM_NAME="$(az apim list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query '[0].name' \
    --output tsv)"
export APIM_GATEWAY_URL="https://${APIM_NAME}.azure-api.net"
```

## 動作確認

### テストスクリプト

```bash
./tests/00_prerequisites.sh
./tests/03_test_function_direct.sh "$PII_FILTER_FUNCTION_BASE_URL"
./tests/04_test_apim.sh "$APIM_GATEWAY_URL"
```

### 許可されるリクエスト

個人情報を含まない顧客サポートメッセージはバックエンドへ転送され、HTTP `200`が返ります。

```bash
curl --include --silent --show-error \
    --request POST \
    "${APIM_GATEWAY_URL}/customer-support/messages" \
    --header 'Content-Type: application/json' \
    --data '{"text":"this text is safe"}'
```

レスポンス例:

```http
HTTP/1.1 200 OK
Content-Type: application/json

{"status":"accepted","message":"No PII was detected.","text":"this text is safe"}
```

### 拒否されるリクエスト

電話番号などの個人情報を含むリクエストはAPIMポリシーで拒否され、バックエンドへは転送されません。

```bash
curl --include --silent --show-error \
    --request POST \
    "${APIM_GATEWAY_URL}/customer-support/messages" \
    --header 'Content-Type: application/json' \
    --data '{"text":"my phone number is 090-1234-5678"}'
```

レスポンス例:

```http
HTTP/1.1 400 Bad Request
Content-Type: application/json

{"status":"rejected","message":"PII detected by APIM policy."}
```

## 参考: APIインターフェース仕様

すべてのAPIは`Content-Type: application/json`のHTTP `POST`を受け付けます。このサンプルではAPIMのサブスクリプションキーとFunctionキーを要求しません。

### 共通リクエスト

```json
{
    "text": "検査対象の文字列"
}
```

`text`は空でない文字列である必要があります。不正なJSON、`text`の欠落、空文字列にはHTTP `400`を返します。

### APIM公開API

顧客からの問い合わせメッセージを受け付ける事業APIです。APIMがPresidio FunctionでPIIを検査し、PIIがなければ内部PIIフィルターFunctionへ転送します。

| 項目 | 値 |
| --- | --- |
| メソッド | `POST` |
| URL | `${APIM_GATEWAY_URL}/customer-support/messages` |
| 認証 | なし |

| HTTPステータス | 条件 | レスポンス概要 |
| --- | --- | --- |
| `200` | PIIが検出されなかった | メッセージの受理レスポンス |
| `400` | PIIが検出された | APIMポリシーの拒否レスポンス |
| `502` | Presidio Functionの呼び出しに失敗した | `{"status":"error","message":"Presidio API call from APIM failed."}` |

PIIが検出されなかった場合:

```json
{
    "status": "accepted",
    "message": "No PII was detected.",
    "text": "検査対象の文字列"
}
```

PIIが検出された場合:

```json
{
    "status": "rejected",
    "message": "PII detected by APIM policy."
}
```

### 内部PIIフィルターFunction API

バックエンドでメッセージをPII検査する内部エンドポイントです。このFunction自身もPresidio Functionを呼び出してPIIを検査します。

| 項目 | 値 |
| --- | --- |
| メソッド | `POST` |
| URL | `${PII_FILTER_FUNCTION_BASE_URL}/api/pii-filter/messages` |
| 認証 | なし |

| HTTPステータス | 条件 | レスポンス概要 |
| --- | --- | --- |
| `200` | PIIが検出されなかった | 受理結果と入力文字列 |
| `400` | リクエスト不正、またはPIIが検出された | エラーまたは拒否結果 |
| `500` | `PRESIDIO_API_URL`が未設定 | 設定エラー |
| `502` | Presidio Functionの呼び出しに失敗した | 依存APIエラー |

PIIが検出された場合:

```json
{
    "status": "rejected",
    "message": "PII detected in request payload.",
    "findings": [
        {
            "entity_type": "EMAIL_ADDRESS",
            "start": 12,
            "end": 28,
            "score": 0.8,
            "text": "john@example.com"
        }
    ]
}
```

### Presidio Function API

文字列を解析し、検出したPIIの位置、種別、スコアを返すエンドポイントです。PIIの有無にかかわらず、正常に解析できた場合はHTTP `200`を返します。

| 項目 | 値 |
| --- | --- |
| メソッド | `POST` |
| URL | `${PRESIDIO_FUNCTION_BASE_URL}/api/pii-filter/analyze` |
| 認証 | なし |

| HTTPステータス | 条件 | レスポンス概要 |
| --- | --- | --- |
| `200` | 解析に成功した | `has_pii`と検出結果一覧 |
| `400` | JSONまたは`text`が不正 | 入力エラー |

PIIが検出された場合:

```json
{
    "text": "Call me at 090-1234-5678",
    "has_pii": true,
    "findings": [
        {
            "entity_type": "PHONE_NUMBER",
            "start": 11,
            "end": 24,
            "score": 0.8,
            "text": "090-1234-5678"
        }
    ]
}
```

PIIが検出されなかった場合は`has_pii`が`false`、`findings`が空配列になります。

```json
{
    "text": "this text is safe",
    "has_pii": false,
    "findings": []
}
```

# Azure APIM + Microsoft Decision-1 PII Filter Demo

顧客サポートメッセージを例に、Azure API Management（APIM）からMicrosoft Decision-1を
呼び出し、通常は個人情報（PII）が含まれないリクエストだけをバックエンドへ転送するサンプルです。
PresidioおよびPresidioをホストするFunctionは使用しません。

## 構成

```text
Client → APIM → Decision-1（Foundry）
           ├─ pii    → 400で拒否
           ├─ エラー → 502で拒否
           └─ no_pii → メッセージ受付Function → 200
```

- APIM Developer SKU（システム割り当てマネージドID）
- Microsoft Decision-1 v1、DataZoneStandard、容量60
- バックエンド: Azure Functions Flex Consumption、Python 3.11
- Storage、Application Insights、Log Analytics
- FunctionのVNet統合とStorage用Private Endpoint（Blob / Queue / Table）、Private DNS
- APIMとFoundryの通信は公開HTTPSエンドポイント＋マネージドID

PII判定はAPIMだけで行います。バックエンドFunctionはJSONの入力検証とメッセージ受理のみで、
Decision-1やPresidioの再呼び出しは行いません。
日本語の `instructions` / `criteria` による `choice` 型で `pii` / `no_pii` を分類します。
独自の確率しきい値は適用しません。

詳細は[アーキテクチャ](docs/architecture.md)、[API仕様](docs/api-interfaces.md)、
[Decision-1利用ガイドと単体実測結果](docs/decision-1.md)を参照してください。

## 前提条件

- Azure CLI（`az`、Bicep CLIを含む）、Azure Developer CLI（`azd`）
- Bash、`curl`、`jq`
- リソース作成権限とロール割り当て作成権限
- Flex ConsumptionのVNet統合に必要な `Microsoft.App` リソースプロバイダーの登録権限
- 対象リージョンでのDecision-1提供とクォータ

2026-10-25のJapan Eastでは `DataZoneStandard` が利用可能でした。
データゾーン内で処理されるため、Japan Eastのみでの処理を保証するものではありません。
提供状況はデプロイ前に再確認してください。

## azdによる一式デプロイ

```bash
az login --use-device-code
azd auth login

az provider register --namespace Microsoft.App --wait
azd env new apim-decision1
azd env set AZURE_SUBSCRIPTION_ID "$(az account show --query id --output tsv)"
azd env set AZURE_LOCATION japaneast
azd env set AZURE_PRINCIPAL_ID "$(az ad signed-in-user show --query id --output tsv)"
azd env set PUBLISHER_EMAIL "your-email@example.com"
azd up --no-prompt
```

既存環境を使う場合は `azd env new` の代わりに `azd env select apim-decision1` を実行します。
APIM、FoundryとDecision-1、バックエンドFunctionをすべて同じazd環境で作成します。
APIM Developerの初回作成には約30〜45分以上かかることがあります。課金が発生します。
APIMを別のスクリプトで作成する必要はありません。

同じ処理を行う補助スクリプト:

```bash
./tests/01_deploy.sh apim-decision1 japaneast your-email@example.com
```

ローカルのazd環境には、エンドポイントなどの出力が保存されます。

```bash
export RESOURCE_GROUP_NAME="$(azd env get-value RESOURCE_GROUP_NAME)"
export APIM_NAME="$(azd env get-value APIM_NAME)"
export APIM_GATEWAY_URL="$(azd env get-value APIM_GATEWAY_URL)"
export DEMO_FUNCTION_BASE_URL="$(azd env get-value DEMO_FUNCTION_BASE_URL)"
export DECISION1_ENDPOINT="$(azd env get-value DECISION1_ENDPOINT)"
export DECISION1_DEPLOYMENT="$(azd env get-value DECISION1_DEPLOYMENT)"
```

APIMのIDにはFoundryアカウントスコープの `Cognitive Services User` を割り当てます。
APIキーは使用せず、Foundryのキー認証も無効にしています。
`AZURE_PRINCIPAL_ID` のユーザーにも単体テスト用の推論権限を付与します。
RBAC反映直後は一時的に `502` となる場合があるため、権限の反映後に再確認してください。

Storageは公開アクセスを無効化し、FunctionのVNet統合からPrivate Endpoint経由で使用します。
デプロイ環境の組織PolicyがStorageの公開アクセスを無効化するため、
元の「VNetなし」からこの部分を変更しています。Policyの除外や共有キー有効化は行いません。
Private Endpoint等にも追加料金がかかります。

## 動作確認

```bash
./tests/00_prerequisites.sh
./tests/03_test_function_direct.sh "$DEMO_FUNCTION_BASE_URL"
./tests/04_test_apim.sh "$APIM_GATEWAY_URL"
```

直接Functionを呼ぶテストではPIIも受理されます。PII拒否の検証はAPIM経由で行ってください。
APIMテストはPIIの有無、入力不正、転送するフィールドの正規化、JSONエスケープを検証します。
実データではなく、合成データを使用してください。

### PIIなし

```bash
curl --include --silent --show-error \
  --request POST "${APIM_GATEWAY_URL}/customer-support/messages" \
  --header 'Content-Type: application/json' \
  --data '{"text":"アプリの設定を教えてください。"}'
```

HTTP `200`:

```json
{"status":"accepted","message":"Message accepted.","text":"アプリの設定を教えてください。"}
```

### PIIあり

同じリクエストを送る、jq不要の単一curlサンプル:

```bash
export APIM_GATEWAY_URL="$(azd env get-value APIM_GATEWAY_URL)"
./tests/08_curl_apim-pii.sh
```

レスポンスのHTTPヘッダーと本文を表示します。期待値はHTTP `400` と以下の拒否JSONです。
このサンプル自体は期待値を自動検証しません。自動検証には `04_test_apim.sh` を使ってください。

```bash
curl --include --silent --show-error \
  --request POST "${APIM_GATEWAY_URL}/customer-support/messages" \
  --header 'Content-Type: application/json' \
  --data '{"text":"連絡先は090-1234-5678です。"}'
```

HTTP `400`:

```json
{"status":"rejected","message":"PII detected by APIM policy."}
```

### PII判定をスキップする（デモ用）

`?no-pii-filter` を付けるとDecision-1を呼ばず、PIIを含む本文もバックエンドへ転送します。
キーの存在で判定するため、`?no-pii-filter=false` でもスキップします。
JSONと `text` の入力検証は維持し、クエリや余分なフィールドはバックエンドへ転送しません。

```bash
export APIM_GATEWAY_URL="$(azd env get-value APIM_GATEWAY_URL)"
./tests/09_test_apim-no-pii-filter.sh
```

09はcurlで通常時の拒否、スキップ時の受理、不正入力の拒否を送り、jqで応答を自動検証します。

08と同じ本文を `?no-pii-filter` 付きで送る、jq不要の単一curlサンプル:

```bash
./tests/10_curl_apim-no-pii-filter.sh
```

10はHTTPヘッダーと本文を表示します。期待値はHTTP `200`、`status=accepted` です。
期待値の自動検証は行いません。

**誰でも判定を回避できるデモ用機能です。本番ではこの分岐を削除するか権限制御を追加してください。**

### Decision-1の単体テスト

```bash
./tests/05_test_decision1.sh
./tests/06_test_decision1-jp.sh
./tests/07_curl_decision1-jp.sh
```

それぞれ英語プロンプト、日本語プロンプト、jq不要の単一curlサンプルです。
これらはAPIMを通さずDecision-1を呼びます。

### バックエンドのローカルテスト

```bash
python3 -m pip install -r src/demo-api/requirements.txt
python3 -m unittest discover -s tests -p 'test_*.py'
```

## 実環境での確認結果

`apim-decision1` 環境、Japan East、リソースグループ `rg-apim-decision1` で
`azd up --environment apim-decision1 --no-prompt` のプロビジョニングとコード公開が成功しました。

| 検証 | 結果 |
| --- | --- |
| Function直接呼び出し | 7件成功 |
| APIM経由の分類・入力検証・転送内容 | 22件成功 |
| Decision APIエラーと模擬応答による分岐検証 | 11件成功 |
| ローカルのPython・APIMポリシーテスト | 8件成功 |

異常系では、存在しないモデルデプロイ、未知の分類、必須フィールドの欠落、
型不正、不正JSON、HTTP 503を検証し、HTTP 502で拒否することを確認しました。
模擬応答用の一時APIM APIは削除し、実際のDecision-1接続先へ復元後にHTTP 200を再確認しています。

稼働中のバックエンドは `func-apim-decision1-support-o5mj5g` です。
VNet統合前に作成した空の `func-apim-decision1-demo-o5mj5g` とそのFlexプランは、
後付け統合後もコード公開に失敗したため使用していません。削除はしていません。
`azure.yaml` の `resourceName` で、新しいバックエンドを明示的に指定しています。
新規環境では、この古い空のFunctionやプランは作成されません。

## 制約と注意

- このサンプルは本番向けDLP実装ではなく、モデルの見逃し・過検知があります。
- APIM公開APIはサブスクリプションキーを要求しません。
- デモのバックエンドFunctionは匿名アクセス可能です。直接アクセスではPII検査を迂回できます。
  本番ではFunctionへの直接アクセスを認証・ネットワーク制限で遮断してください。
- 未知の回答やDecision-1のHTTPエラー、タイムアウト、応答解析失敗ではバックエンドへ転送しません。
- 検査・転送の対象は `text` のみです。他のフィールドとクエリパラメーターは転送しません。
- 旧Presidioの `findings`、内部PIIフィルター経路、二重検査は廃止しました。
- モデルv1の廃止予定は確認時点で2027-02-04でした。継続利用前に最新情報を確認してください。

不要になった環境は対象を確認したうえで削除します。

```bash
azd down --environment apim-decision1
```

先行する単体検証用の `rg-apim-decision1-demo` は別のリソースグループです。
このazd環境の削除では削除されません。

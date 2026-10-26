# APIインターフェース仕様

## 1. Customer Support API（APIM公開API）

| 項目 | 値 |
| --- | --- |
| メソッド | `POST` |
| パス | `/customer-support/messages` |
| Content-Type | `application/json` |
| 認証 | このデモでは不要 |

### リクエスト

```json
{"text":"アプリの設定を教えてください。"}
```

`text` は空白のみではない文字列が必要です。余分なフィールドは判定対象にせず、
バックエンドにも転送しません。クエリパラメーターも転送しません。

### 成功（200）

通常はDecision-1の回答が `type=choice`、`choice=no_pii` の場合のみ、
バックエンドを呼び出してその受理結果を返します。

```json
{"status":"accepted","message":"Message accepted.","text":"アプリの設定を教えてください。"}
```

### PII判定のスキップ（デモ用）

`POST /customer-support/messages?no-pii-filter` のように、クエリに
`no-pii-filter` キーを付けるとDecision-1の呼び出しと判定結果の検証をスキップします。
値ではなくキーの存在で判定するため、`?no-pii-filter=`、
`?no-pii-filter=true`、`?no-pii-filter=false` もスキップします。
有効な `text` はPIIの有無によらずバックエンドへ転送され、通常はHTTP `200` になります。
入力検証、余分なフィールドの除去、クエリをバックエンドへ転送しない動作は維持します。

**認証不要のデモ用バイパスです。誰でもPII検査を無効化できるため、
PII流出防止を必須とする本番環境では、この分岐を削除するか権限制御を追加してください。**

### PII拒否（400）

Decision-1の回答が `choice=pii` の場合、バックエンドへは転送しません。

```json
{"status":"rejected","message":"PII detected by APIM policy."}
```

### 入力不正（400）

不正なJSON、非オブジェクトのJSON、`text`の欠落・数値・null・空文字列・空白のみが対象です。
Decision-1とバックエンドは呼び出しません。

```json
{"status":"error","message":"Request body must be valid JSON with a non-empty string field 'text'."}
```

### 判定失敗（502）

Decision-1の非200応答（認証失敗・レート制限等を含む）、通信失敗・タイムアウト、
不正な回答形式・未知の選択肢・ポリシー実行エラーでは通過させません。
PII検出としての `400` ではなく、依存APIの失敗として `502` を返します。
モデルの生の応答・入力・トークンはクライアントへ返しません。

```json
{"status":"error","message":"Decision-1 API call from APIM failed."}
```

## 2. メッセージ受付API（バックエンドFunction）

| 項目 | 値 |
| --- | --- |
| メソッド | `POST` |
| パス | `/api/customer-support/messages` |
| Content-Type | `application/json` |
| 認証 | このデモでは不要 |

有効な `text` を受け付け、上記の受理レスポンスを返します。
入力が不正な場合はHTTP `400`、`status=error` と入力エラーメッセージを返します。
このFunctionはPII判定を行わず、PIIを含む入力も直接呼ぶと受理します。
本番ではAPIMを迂回できないように認証・ネットワーク制限を設定してください。

## 3. Decision-1 API（APIMからの内部呼び出し）

- URL: `<Foundryリソースエンドポイント>/providers/microsoft/v1/systemone`
- メソッド: `POST`
- 認証: APIMマネージドIDによるEntra ID Bearerトークン
- 質問: 日本語の `instructions` / `criteria` と `type=choice`
- 選択肢: `pii` / `no_pii`
- 正常な解析では、PIIの有無にかかわらずHTTP `200`

要求・応答の詳細と単体テストは[Decision-1利用ガイド](decision-1.md)を参照してください。

## 旧APIからの変更

- `/api/pii-filter/analyze`（Presidio Function）は削除しました。
- バックエンドの `/api/pii-filter/messages` は `/api/customer-support/messages` に変更しました。
- APIMの公開パス `/customer-support/messages` は変更していません。
- バックエンド側のPII再検査、Presidioの依存エラー、`findings` は廃止しました。
- 受理メッセージは `No PII was detected.` から `Message accepted.` に変更しました。

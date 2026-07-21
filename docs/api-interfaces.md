# APIインターフェース仕様

## 1. Presidio PII Filter API（Function）

### Endpoint
- Method: `POST`
- Path: `/api/pii-filter/analyze`
- Content-Type: `application/json`

### Request Body
```json
{
  "text": "Call me at 090-1234-5678"
}
```

### Success Response (`200`)
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

### Error Response (`400`)
```json
{
  "error": "Field 'text' is required."
}
```

## 2. Message PII Filter API（Function）

### Endpoint
- Method: `POST`
- Path: `/api/pii-filter/messages`
- Content-Type: `application/json`

### Request Body
```json
{
  "text": "This is a sample request without PII"
}
```

### Success Response (`200`)
```json
{
  "status": "accepted",
  "message": "No PII was detected.",
  "text": "This is a sample request without PII"
}
```

### PII Block Response (`400`)
```json
{
  "status": "rejected",
  "message": "PII detected in request payload.",
  "findings": [
    {
      "entity_type": "EMAIL_ADDRESS",
      "start": 5,
      "end": 22,
      "score": 0.8,
      "text": "john@example.com"
    }
  ]
}
```

### Dependency Failure (`502`)
```json
{
  "status": "error",
  "message": "Presidio API call failed.",
  "detail": "timeout"
}
```

## 3. Customer Support API（APIM公開API）

### Endpoint
- Method: `POST`
- Path: `/customer-support/messages`

### Behavior
- APIM sends the inbound request body to Presidio API.
- If `has_pii == true`, APIM returns `400`.
- Otherwise APIM forwards the request to the internal PII filter API `/api/pii-filter/messages`.

### APIM PII Block Response (`400`)
```json
{
  "status": "rejected",
  "message": "PII detected by APIM policy."
}
```

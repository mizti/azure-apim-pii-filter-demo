#!/usr/bin/env bash
set -euo pipefail

: "${APIM_GATEWAY_URL:?Set the API Management gateway URL.}"

curl --include --silent --show-error --max-time 60 \
  --request POST "${APIM_GATEWAY_URL%/}/customer-support/messages?no-pii-filter" \
  --header "Content-Type: application/json" \
  --data-binary @- <<'EOF'
{
  "text": "私の住所はXXXXXXです。"
}
EOF

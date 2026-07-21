#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <apim-gateway-base-url>"
  exit 1
fi

APIM_BASE_URL="$1"

printf "\n[No PII request]\n"
curl -i -sS -X POST "${APIM_BASE_URL}/demo/process" \
  -H 'Content-Type: application/json' \
  -d '{"text":"this text is safe"}'

printf "\n\n[PII request]\n"
curl -i -sS -X POST "${APIM_BASE_URL}/demo/process" \
  -H 'Content-Type: application/json' \
  -d '{"text":"my phone number is 090-1234-5678"}'

printf "\n"

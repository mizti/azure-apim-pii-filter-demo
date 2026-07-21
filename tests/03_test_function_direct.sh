#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <demo-function-base-url>"
  exit 1
fi

DEMO_BASE_URL="$1"

curl -sS -X POST "${DEMO_BASE_URL}/api/demo/process" \
  -H 'Content-Type: application/json' \
  -d '{"text":"hello world"}' | jq

curl -sS -X POST "${DEMO_BASE_URL}/api/demo/process" \
  -H 'Content-Type: application/json' \
  -d '{"text":"my email is john@example.com"}' | jq

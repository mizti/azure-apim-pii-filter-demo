#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <apim-gateway-base-url>"
  exit 1
fi

APIM_BASE_URL="$1"

test_request() {
  local label="$1"
  local payload="$2"
  local expected_status="$3"
  local response_file
  local actual_status

  response_file="$(mktemp)"
  trap 'rm -f "$response_file"' RETURN

  actual_status="$(curl --max-time 60 -sS -o "$response_file" -w '%{http_code}' \
    -X POST "${APIM_BASE_URL}/customer-support/messages" \
    -H 'Content-Type: application/json' \
    -d "$payload")"

  printf '\n[%s] HTTP %s\n' "$label" "$actual_status"
  jq . "$response_file"

  if [[ "$actual_status" != "$expected_status" ]]; then
    echo "Expected HTTP $expected_status, got $actual_status"
    exit 1
  fi
}

test_request "No PII request" '{"text":"this text is safe"}' 200
test_request "PII request" '{"text":"my phone number is 090-1234-5678"}' 400

#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <pii-filter-function-base-url>"
  exit 1
fi

PII_FILTER_BASE_URL="$1"

test_request() {
  local label="$1"
  local payload="$2"
  local expected_status="$3"
  local response_file
  local actual_status

  response_file="$(mktemp)"
  trap 'rm -f "$response_file"' RETURN

  actual_status="$(curl --max-time 60 -sS -o "$response_file" -w '%{http_code}' \
    -X POST "${PII_FILTER_BASE_URL}/api/pii-filter/messages" \
    -H 'Content-Type: application/json' \
    -d "$payload")"

  printf '\n[%s] HTTP %s\n' "$label" "$actual_status"
  jq . "$response_file"

  if [[ "$actual_status" != "$expected_status" ]]; then
    echo "Expected HTTP $expected_status, got $actual_status"
    exit 1
  fi
}

test_request "No PII request" '{"text":"hello world"}' 200
test_request "PII request" '{"text":"my email is john@example.com"}' 400

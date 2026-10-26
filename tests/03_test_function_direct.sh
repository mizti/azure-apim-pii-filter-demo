#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <demo-function-base-url>"
  exit 1
fi

DEMO_BASE_URL="$1"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT

test_request() {
  local label="$1"
  local payload="$2"
  local expected_status="$3"
  local expected_text="${4:-}"
  local response_file
  local actual_status

  response_file="$work_dir/response.json"

  actual_status="$(curl --max-time 60 -sS -o "$response_file" -w '%{http_code}' \
    -X POST "${DEMO_BASE_URL%/}/api/customer-support/messages" \
    -H 'Content-Type: application/json' \
    -d "$payload")"

  printf '\n[%s] HTTP %s\n' "$label" "$actual_status"
  jq . "$response_file"

  if [[ "$actual_status" != "$expected_status" ]]; then
    echo "Expected HTTP $expected_status, got $actual_status"
    exit 1
  fi
  if [[ "$expected_status" == 200 ]]; then
    jq -e --arg text "$expected_text" \
      '. == {status:"accepted", message:"Message accepted.", text:$text}' "$response_file" >/dev/null
  else
    jq -e '.status == "error" and (.message | type == "string")' "$response_file" >/dev/null
  fi
}

test_request "Valid request" '{"text":"hello world"}' 200 'hello world'
test_request "PII screening belongs to APIM, not this backend" '{"text":"my email is test.person@example.com"}' 200 'my email is test.person@example.com'
test_request "Malformed JSON" '{' 400
test_request "Missing text" '{}' 400
test_request "Blank text" '{"text":"  "}' 400
test_request "Wrong text type" '{"text":123}' 400
test_request "Non-object JSON" '[]' 400

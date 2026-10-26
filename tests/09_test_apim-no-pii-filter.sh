#!/usr/bin/env bash
set -euo pipefail

: "${APIM_GATEWAY_URL:?Set the API Management gateway URL.}"

work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
total=0
pii_text='連絡先は090-1234-5678です。'
payload='{"text":"連絡先は090-1234-5678です。","extra":"not forwarded"}'

test_request() {
  local label="$1" query="$2" body="$3" expected_status="$4" expected_state="$5"
  local status
  status="$(curl --silent --show-error --max-time 60 \
    --request POST "${APIM_GATEWAY_URL%/}/customer-support/messages${query}" \
    --header 'Content-Type: application/json' \
    --data-binary "$body" --output "$work_dir/response.json" --write-out '%{http_code}')"
  printf '\n[%s] HTTP %s\n' "$label" "$status"
  jq . "$work_dir/response.json"
  if [[ "$status" != "$expected_status" ]]; then
    echo "Expected HTTP $expected_status, got $status" >&2
    exit 1
  fi
  case "$expected_state" in
    accepted)
      jq -e --arg text "$pii_text" \
        '. == {status:"accepted", message:"Message accepted.", text:$text}' "$work_dir/response.json" >/dev/null
      ;;
    rejected)
      jq -e '. == {status:"rejected", message:"PII detected by APIM policy."}' "$work_dir/response.json" >/dev/null
      ;;
    error)
      jq -e '. == {status:"error", message:"Request body must be valid JSON with a non-empty string field \u0027text\u0027."}' \
        "$work_dir/response.json" >/dev/null
      ;;
  esac
  total=$((total + 1))
}

test_request 'Without bypass: reject PII' '' "$payload" 400 rejected
test_request 'Bare parameter: accept PII' '?no-pii-filter' "$payload" 200 accepted
test_request 'Empty parameter: accept PII' '?no-pii-filter=' "$payload" 200 accepted
test_request 'True value: accept PII' '?no-pii-filter=true' "$payload" 200 accepted
test_request 'Presence, not value: false also bypasses' '?no-pii-filter=false' "$payload" 200 accepted
test_request 'Other query parameters: accept PII' '?other=value&no-pii-filter&another=1' "$payload" 200 accepted
test_request 'Similar name must not bypass' '?no-pii-filter-other=true' "$payload" 400 rejected
test_request 'Malformed JSON still rejected' '?no-pii-filter' '{' 400 error
test_request 'Missing text still rejected' '?no-pii-filter' '{}' 400 error
test_request 'Blank text still rejected' '?no-pii-filter' '{"text":"  "}' 400 error
test_request 'Wrong text type still rejected' '?no-pii-filter' '{"text":123}' 400 error
test_request 'Without bypass remains protected' '' "$payload" 400 rejected

printf '\nAll %s APIM bypass cases passed.\n' "$total"

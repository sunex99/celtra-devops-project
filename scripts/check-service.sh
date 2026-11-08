#!/usr/bin/env bash
# Checks that a running instance of the data service follows the contract.
#
# Usage: bash scripts/check-service.sh <base-url>
#   e.g. bash scripts/check-service.sh http://localhost:8080
#
# It is used against the container in CI and, later, against the deployed
# service as the smoke test. It only sends GET and POST requests to the
# given URL and changes nothing. Requires curl and jq.

set -euo pipefail

base="${1:?usage: $0 <base-url>}"
base="${base%/}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# status <curl args...> prints only the HTTP status code of the response.
status() {
  curl --silent --output /dev/null --write-out '%{http_code}' --max-time 5 "$@"
}

echo "Waiting for $base/healthz"
# Retry for up to ~30 seconds, since the container needs a moment to start.
curl --silent --fail --retry 15 --retry-delay 2 --retry-connrefused \
  --max-time 5 --output /dev/null "$base/healthz" || fail "service did not become healthy"

echo "Check: /healthz returns ok"
[ "$(curl --silent --max-time 5 "$base/healthz")" = "ok" ] || fail "/healthz body is not 'ok'"

echo "Check: /acme-42/data has the expected shape"
body="$(curl --silent --fail --max-time 5 "$base/acme-42/data")"
now="$(date +%s)"
echo "$body" | jq -e --argjson now "$now" '
  (keys == ["accountId", "data", "timestamp"])
  and .accountId == "acme-42"
  and (.data | test("^[0-9a-f]{32}$"))
  and (.timestamp | type == "number")
  and ((.timestamp - $now) | if . < 0 then -. else . end) < 60
' > /dev/null || fail "unexpected response: $body"

echo "Check: Content-Type is application/json"
type="$(curl --silent --output /dev/null --write-out '%{content_type}' --max-time 5 "$base/acme-42/data")"
[ "$type" = "application/json" ] || fail "Content-Type is '$type'"

echo "Check: data differs between two calls"
first="$(curl --silent --max-time 5 "$base/acme-42/data" | jq -r .data)"
second="$(curl --silent --max-time 5 "$base/acme-42/data" | jq -r .data)"
[ "$first" != "$second" ] || fail "two calls returned the same data: $first"

echo "Check: invalid account id returns 400"
[ "$(status "$base/has%20space/data")" = "400" ] || fail "expected 400 for an invalid account id"

echo "Check: unknown path returns 404"
[ "$(status "$base/acme-42/other")" = "404" ] || fail "expected 404 for an unknown path"

echo "Check: POST is not allowed"
[ "$(status -X POST "$base/acme-42/data")" = "405" ] || fail "expected 405 for POST"

echo "All checks passed"

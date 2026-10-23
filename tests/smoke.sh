#!/usr/bin/env bash
# shellcheck disable=SC2015
# Smoke test: bring up HarnessRouter (lean backends) beside a mock provider, then verify the login
# gate, the lean first boot, and real agent turns through opencode and codex, both from the
# console session and from a minted API key.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
MOCK_BASE="http://mock:8080/v1"

STARTED=0
if [ "${HR_REUSE_STACK:-0}" != "1" ]; then
  section "bring the stack up"
  compose up -d >/dev/null 2>&1 || die "compose up failed"
  STARTED=1
  trap 'compose logs --no-color --tail 80 || true; [ "$STARTED" = 1 ] && compose down -v --remove-orphans >/dev/null 2>&1 || true; rm -rf "$TEST_TMP"' EXIT
else
  trap 'rm -rf "$TEST_TMP"' EXIT
fi

section "first boot and liveness"
t0=$(date +%s)
wait_for_code "$APP_URL/login" 200 "$TEST_TIMEOUT" && pass "/login returns 200 without a session (the health path)" || die "console never came up"
echo "  INFO  first boot took $(( $(date +%s) - t0 ))s"
logs=$(compose logs --no-color app 2>&1)
assert_contains "the lean backends are installed" "backends available: claude codex opencode" "$logs"
assert_not_contains "no requested backend is missing" "requested but not installed" "$logs"
assert_not_contains "the default console password is not in use" "using the DEFAULT password" "$logs"
tools_mb=$(compose exec -T app du -sm /data/agent-tools | awk '{print $1}')
if [ "${tools_mb:-99999}" -lt 2048 ]; then pass "agent CLIs on the volume stay small (${tools_mb} MB < 2048 MB)"; else fail "agent CLIs use ${tools_mb} MB"; fi

section "the console requires a sign-in"
assert_eq "/ redirects to the sign-in page" "307" "$(http_code "$APP_URL/")"
assert_eq "the API answers 401 without a session" "401" "$(http_code "$API/v1/harnesses")"
assert_eq "the integrations document answers 401 without a session" "401" "$(http_code "$API/v1/admin/integrations")"
assert_eq "a wrong password is rejected" "401" "$(login_code "$HR_USER" definitely-wrong)"
assert_eq "the published default password is rejected" "401" "$(login_code harnessrouter harnessrouter)"
assert_eq "a made-up bearer key is rejected" "401" "$(http_code -H 'Authorization: Bearer sk-hr-not-a-real-key' "$API/v1/harnesses")"

section "sign in"
jar="$TEST_TMP/jar"
login "$jar" && pass "the console signs in with HR_AUTH_PASSWORD" || die "console sign-in failed"
assert_contains "the session names the console user" "\"user\":\"$HR_USER\"" "$(curl -s -b "$jar" "$APP_URL/api/selfhost/session")"
bases=$(jget "$jar" /v1/bases)
assert_contains "the codex base is listed" '"id":"codex"' "$bases"
assert_contains "the opencode base is listed" '"id":"opencode"' "$bases"
assert_contains "the claude-code base is listed" '"id":"claude-code"' "$bases"

section "connect a provider (the mock)"
put=$(put_mock_integrations "$jar" "$MOCK_BASE")
assert_contains "the integrations document is saved" '"ok":true' "$put"
assert_not_contains "the provider key is not echoed back" 'mock-provider-not-a-secret' "$put$(jget "$jar" /v1/admin/integrations)"

section "real agent turns"
r=$(run_turn_cookie "$jar" opencode mock-model)
assert_eq "an opencode turn completes" "completed" "$(jq -r .status <<<"$r" 2>/dev/null)"
assert_contains "the opencode turn returns the provider's answer" "$EXPECT_ANSWER" "$(answer_of "$r")"
r=$(run_turn_cookie "$jar" codex mock-resp)
assert_eq "a codex turn completes" "completed" "$(jq -r .status <<<"$r" 2>/dev/null)"
assert_contains "the codex turn returns the provider's answer" "$EXPECT_ANSWER" "$(answer_of "$r")"

section "the API with a minted key"
hdr="$TEST_TMP/auth.hdr"
mint_key "$jar" smoke "$hdr" && pass "an API key is minted" || die "could not mint an API key"
assert_eq "the key lists harnesses" "200" "$(bcode "$hdr" /v1/harnesses)"
h=$(curl -s --max-time 60 -H @"$hdr" -H 'Content-Type: application/json' \
  --data '{"name":"Template Smoke Agent","base":"opencode","default_model":"mock-model"}' "$API/v1/harnesses")
hid=$(jq -r '.id // empty' <<<"$h" 2>/dev/null)
[ -n "$hid" ] && pass "a custom harness is created" || die "harness create: $(head -c 300 <<<"$h")"
r=$(run_turn_bearer "$hdr" "$hid" mock-model)
assert_contains "the custom harness runs a turn over the API" "$EXPECT_ANSWER" "$(answer_of "$r")"
sid=$(jq -r '.metadata.session_id // empty' <<<"$r" 2>/dev/null)
[ -n "$sid" ] && pass "the turn names its session" || fail "no session id in the response"
assert_eq "the session is readable with the key" "200" "$(bcode "$hdr" "/v1/sessions/$sid")"
r=$(run_turn_bearer "$hdr" "$hid" mock-model "$sid")
assert_contains "a follow-up turn continues the same session" "$EXPECT_ANSWER" "$(answer_of "$r")"
assert_eq "the session lists both turns" "2" "$(bget "$hdr" "/v1/sessions/$sid/turns" | jq '.turns | length' 2>/dev/null)"
assert_contains "a file is written to the session workspace" '"written":true' \
  "$(curl -s --max-time 60 -H @"$hdr" -X PUT -H 'Content-Type: application/json' --data '{"content":"smoke-file-ok"}' "$API/v1/sessions/$sid/files/notes/smoke.txt")"
assert_eq "the file reads back" "smoke-file-ok" "$(bget "$hdr" "/v1/sessions/$sid/files/notes/smoke.txt")"

summary

#!/usr/bin/env bash
# shellcheck disable=SC2015
# Live end-to-end test against a deployed template, over HTTPS.
#
#   HR_PASSWORD_FILE=/path/600-file HR_STATE_DIR=/path/dir \
#   MOCK_BASE_URL=http://mock.railway.internal:8080/v1 tests/railway-smoke.sh https://<domain>
#   ... tests/railway-smoke.sh https://<domain> --verify     # after a redeploy
#
# The full run proves the gate, the lean first boot (via /v1/bases), a provider connection, real
# opencode and codex turns, a minted API key, a custom harness, a session and a file; it saves the
# ids (and the key, mode 600) to HR_STATE_DIR. --verify proves they survived a redeploy.
# MOCK_BASE_URL is a test-only mock provider reachable FROM the deployed app (a private sidecar);
# without it the agent turns are skipped.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
[ $# -ge 1 ] || { echo "usage: $0 https://<domain> [--verify]" >&2; exit 2; }
APP_URL=${1%/}; MODE=${2:-full}
[ -n "${HR_PASSWORD_FILE:-}" ] || { echo "HR_PASSWORD_FILE is required" >&2; exit 2; }
: "${HR_STATE_DIR:?HR_STATE_DIR is required}"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
mkdir -p "$HR_STATE_DIR"; chmod 700 "$HR_STATE_DIR"
trap 'rm -rf "$TEST_TMP"' EXIT
hdr="$HR_STATE_DIR/auth.hdr"
jar="$TEST_TMP/jar"

section "edge, TLS and the gate"
case "$APP_URL" in https://*) pass "the URL is HTTPS" ;; *) fail "not an HTTPS URL" ;; esac
wait_for_code "$APP_URL/login" 200 600 && pass "/login returns 200 (the health path)" || die "the deploy is not serving"
assert_eq "/ redirects to the sign-in page" "307" "$(http_code "$APP_URL/")"
assert_eq "the API answers 401 without a session" "401" "$(http_code "$API/v1/harnesses")"
assert_eq "a wrong password is rejected" "401" "$(login_code "$HR_USER" definitely-wrong)"
assert_eq "the published default password is rejected" "401" "$(login_code harnessrouter harnessrouter)"

section "sign in"
login "$jar" && pass "the console signs in with the generated password" || die "sign-in failed"
cookie=$(grep -c 'hr_selfhost' "$jar" || true)
[ "${cookie:-0}" -ge 1 ] && pass "the hr_selfhost session cookie is set" || fail "no session cookie"
hsec=$(curl -s -D - -o /dev/null --max-time 30 -X POST "$APP_URL/api/selfhost/login" -H 'Content-Type: application/json' \
  --data @<(login_body "$HR_USER" "$(password_file)" /dev/stdout) | tr -d '\r' | grep -i '^set-cookie' || true)
assert_contains "the session cookie is Secure over HTTPS" "Secure" "$hsec"
assert_contains "the session cookie is HttpOnly" "HttpOnly" "$hsec"

if [ "$MODE" = "--verify" ]; then
  section "state survived the redeploy"
  [ -f "$hdr" ] && [ -f "$HR_STATE_DIR/ids" ] || die "no saved state; run the full test first"
  # shellcheck disable=SC1091
  . "$HR_STATE_DIR/ids"
  assert_eq "the API key still works" "200" "$(bcode "$hdr" /v1/harnesses)"
  assert_eq "the harness survived" "Live Smoke Agent" "$(bget "$hdr" "/v1/harnesses/${HID:-x}" | jq -r .name)"
  assert_eq "the session survived" "2" "$(bget "$hdr" "/v1/sessions/${SID:-x}/turns" | jq '.turns | length')"
  assert_eq "the session file survived" "live-file-ok" "$(bget "$hdr" "/v1/sessions/${SID:-x}/files/notes/live.txt")"
  assert_contains "the provider connection survived" '"name":"mock"' "$(jget "$jar" /v1/admin/integrations | head -c 2000)"
  if [ -n "${MOCK_BASE_URL:-}" ]; then
    r=$(run_turn_bearer "$hdr" "${HID:-opencode}" mock-model "${SID:-}")
    assert_contains "the old session takes a new turn" "$EXPECT_ANSWER" "$(answer_of "$r")"
  fi
  summary; exit $?
fi

bases=$(jget "$jar" /v1/bases)
assert_contains "the codex base is listed" '"id":"codex"' "$bases"
assert_contains "the opencode base is listed" '"id":"opencode"' "$bases"

section "API key and custom harness"
mint_key "$jar" live-smoke "$hdr" && pass "an API key is minted" || die "could not mint a key"
assert_eq "the key lists harnesses" "200" "$(bcode "$hdr" /v1/harnesses)"
assert_eq "a made-up bearer key is rejected" "401" "$(http_code -H 'Authorization: Bearer sk-hr-not-a-real-key' "$API/v1/harnesses")"
hid=$(curl -s --max-time 60 -H @"$hdr" -H 'Content-Type: application/json' \
  --data '{"name":"Live Smoke Agent","base":"opencode","default_model":"mock-model"}' "$API/v1/harnesses" | jq -r '.id // empty')
[ -n "$hid" ] && pass "a custom harness is created" || fail "harness create failed"

if [ -z "${MOCK_BASE_URL:-}" ]; then
  echo "  SKIP  agent turns (MOCK_BASE_URL unset)"
  printf 'HID=%s\nSID=\n' "$hid" > "$HR_STATE_DIR/ids"
  summary; exit $?
fi

section "connect a provider (the private mock) and run real turns"
assert_contains "the integrations document is saved" '"ok":true' "$(put_mock_integrations "$jar" "$MOCK_BASE_URL")"
r=$(run_turn_cookie "$jar" opencode mock-model)
assert_contains "an opencode turn returns the provider's answer" "$EXPECT_ANSWER" "$(answer_of "$r")"
r=$(run_turn_cookie "$jar" codex mock-resp)
assert_contains "a codex turn returns the provider's answer" "$EXPECT_ANSWER" "$(answer_of "$r")"
r=$(run_turn_bearer "$hdr" "${hid:-opencode}" mock-model)
assert_contains "the custom harness runs a turn over the API key" "$EXPECT_ANSWER" "$(answer_of "$r")"
sid=$(jq -r '.metadata.session_id // empty' <<<"$r" 2>/dev/null)
[ -n "$sid" ] && pass "the turn names its session" || fail "no session id"
r=$(run_turn_bearer "$hdr" "${hid:-opencode}" mock-model "$sid")
assert_contains "a follow-up turn continues the session" "$EXPECT_ANSWER" "$(answer_of "$r")"
assert_eq "the session lists both turns" "2" "$(bget "$hdr" "/v1/sessions/$sid/turns" | jq '.turns | length')"
assert_contains "a file is written to the session workspace" '"written":true' \
  "$(curl -s --max-time 60 -H @"$hdr" -X PUT -H 'Content-Type: application/json' --data '{"content":"live-file-ok"}' "$API/v1/sessions/$sid/files/notes/live.txt")"
assert_eq "the file reads back" "live-file-ok" "$(bget "$hdr" "/v1/sessions/$sid/files/notes/live.txt")"
printf 'HID=%s\nSID=%s\n' "$hid" "$sid" > "$HR_STATE_DIR/ids"

summary

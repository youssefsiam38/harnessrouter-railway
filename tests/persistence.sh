#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence test: create state (provider connection, harness, session, file, API key), recreate
# the container keeping the /data volume, and verify all of it survived and that the agent CLIs
# were not reinstalled.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
MOCK_BASE="http://mock:8080/v1"

trap 'compose logs --no-color --tail 80 || true; compose down -v --remove-orphans >/dev/null 2>&1 || true; rm -rf "$TEST_TMP"' EXIT

section "first run: create state"
compose up -d >/dev/null 2>&1 || die "compose up failed"
wait_for_code "$APP_URL/login" 200 "$TEST_TIMEOUT" || die "console never came up"
jar="$TEST_TMP/jar"; hdr="$TEST_TMP/auth.hdr"
login "$jar" || die "sign-in failed"
put_mock_integrations "$jar" "$MOCK_BASE" | grep -q '"ok":true' || die "could not save the integrations"
mint_key "$jar" persistence "$hdr" || die "could not mint a key"
hid=$(curl -s --max-time 60 -H @"$hdr" -H 'Content-Type: application/json' \
  --data '{"name":"Persistence Agent","base":"opencode","default_model":"mock-model"}' "$API/v1/harnesses" | jq -r '.id // empty')
[ -n "$hid" ] || die "could not create a harness"
r=$(run_turn_bearer "$hdr" "$hid" mock-model)
sid=$(jq -r '.metadata.session_id // empty' <<<"$r")
[ -n "$sid" ] || die "the first turn returned no session"
curl -s --max-time 60 -H @"$hdr" -X PUT -H 'Content-Type: application/json' \
  --data '{"content":"persisted-file-ok"}' "$API/v1/sessions/$sid/files/notes/keep.txt" | grep -q '"written":true' || die "could not write a file"
pass "state created (integration, key, harness, session, file)"

section "recreate the container, keep the volume"
compose down >/dev/null 2>&1 || die "compose down failed"
compose up -d >/dev/null 2>&1 || die "compose up (second) failed"
t0=$(date +%s)
wait_for_code "$APP_URL/login" 200 300 && pass "the console comes back" || die "console never came back"
elapsed=$(( $(date +%s) - t0 ))
if [ "$elapsed" -lt 120 ]; then pass "the second boot is fast (${elapsed}s < 120s)"; else fail "the second boot took ${elapsed}s"; fi
boot2=$(compose logs --no-color --since "$(( elapsed + 30 ))s" app 2>&1 || true)
assert_contains "the second boot's log is captured" "backends available: claude codex opencode" "$boot2"
assert_not_contains "the agent CLIs are reused from the volume, not reinstalled" "installing Codex" "$boot2"

section "everything survived"
jar2="$TEST_TMP/jar2"
login "$jar2" && pass "the console password still signs in" || fail "sign-in after restart"
assert_eq "the API key still works" "200" "$(bcode "$hdr" /v1/harnesses)"
assert_eq "the harness survived" "Persistence Agent" "$(bget "$hdr" "/v1/harnesses/$hid" | jq -r .name)"
assert_eq "the session survived" "1" "$(bget "$hdr" "/v1/sessions/$sid/turns" | jq '.turns | length')"
assert_eq "the session file survived" "persisted-file-ok" "$(bget "$hdr" "/v1/sessions/$sid/files/notes/keep.txt")"
assert_contains "the provider connection survived" '"name":"mock"' "$(jget "$jar2" /v1/admin/integrations | head -c 2000)"
r=$(run_turn_bearer "$hdr" "$hid" mock-model "$sid")
assert_contains "the old session takes a new turn" "$EXPECT_ANSWER" "$(answer_of "$r")"

summary

#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2034
# Shared helpers for harnessrouter-railway tests. Source this file; do not execute it.
#
# Secrets discipline: the console password and minted API keys are never echoed or put on argv.
# They live in mode-600 files under $TEST_TMP and reach curl as `--data @file` / `-H @file`.

: "${APP_URL:=http://127.0.0.1:${HR_TEST_PORT:-13000}}"
: "${TEST_TIMEOUT:=900}"
: "${HR_USER:=harnessrouter}"
API="${APP_URL%/}/api/harness"
EXPECT_ANSWER="HR-MOCK-OK"

umask 077
TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found [$2]"; else pass "$1"; fi; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@" || true; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url")
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 5
  done
}

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }

# The console password: from HR_PASSWORD_FILE (live tests), else the local test value.
password_file() {
  local f="$TEST_TMP/password"
  if [ -n "${HR_PASSWORD_FILE:-}" ]; then
    [ -r "$HR_PASSWORD_FILE" ] || die "HR_PASSWORD_FILE is not readable"
    cp "$HR_PASSWORD_FILE" "$f"
  elif [ ! -f "$f" ]; then
    printf '%s' "${HR_TEST_PASSWORD:-local-test-only-console-password}" > "$f"
  fi
  printf '%s' "$f"
}

# login_body USER PASSFILE OUT -> writes {"username","password"} to OUT (mode 600).
login_body() { jq -nc --arg u "$1" --rawfile p "$2" '{username:$u, password:($p|rtrimstr("\n"))}' > "$3"; }

# login JAR -> 0 when the console credentials sign in (session cookie in JAR).
login() {
  local jar=$1 body="$TEST_TMP/login.json" code
  login_body "$HR_USER" "$(password_file)" "$body"
  code=$(curl -s -c "$jar" -o /dev/null -w '%{http_code}' --max-time 30 -X POST "$APP_URL/api/selfhost/login" \
    -H 'Content-Type: application/json' --data @"$body")
  rm -f "$body"
  [ "$code" = "200" ]
}

# login_code USER PASSWORD-LITERAL -> HTTP status of a sign-in with a deliberately wrong credential.
login_code() {
  local body="$TEST_TMP/bad-login.json"
  jq -nc --arg u "$1" --arg p "$2" '{username:$u, password:$p}' > "$body"
  http_code -X POST "$APP_URL/api/selfhost/login" -H 'Content-Type: application/json' --data @"$body"
  rm -f "$body"
}

jget() { curl -s --max-time 60 -b "$1" "$API$2"; }

# put_mock_integrations JAR BASE_URL -> the gateway's answer. Two custom rows on the mock:
#   mock      OpenAI chat format   -> model mock-model  (opencode)
#   mockresp  OpenAI Responses     -> model mock-resp   (codex)
put_mock_integrations() {
  local doc="$TEST_TMP/integrations.json"
  jq -nc --arg b "$2" '{
    integrations: [
      {name:"mock", provider:"custom",
       config:{api_format:"openai", base_url:$b, api_key:"mock-provider-not-a-secret"},
       models:[{canonical:"mock-model", provider_id:"mock-model"}]},
      {name:"mockresp", provider:"custom",
       config:{api_format:"responses", base_url:$b, api_key:"mock-provider-not-a-secret"},
       models:[{canonical:"mock-resp", provider_id:"mock-resp"}]}],
    model_map: {"mock-model":"mock", "mock-resp":"mockresp"}}' > "$doc"
  curl -s --max-time 60 -b "$1" -X PUT -H 'Content-Type: application/json' --data @"$doc" "$API/v1/admin/integrations"
}

# turn_body HARNESS MODEL [PREVIOUS_SESSION] -> a non-streaming /v1/responses body on stdout.
turn_body() {
  jq -nc --arg h "$1" --arg m "$2" --arg s "${3:-}" '{
    input:"Reply with exactly: it works.", model:$m, stream:false,
    metadata:({harness_id:$h} + (if $s == "" then {} else {session_id:$s} end))}'
}

# run_turn_cookie JAR HARNESS MODEL -> the response JSON.
run_turn_cookie() {
  turn_body "$2" "$3" > "$TEST_TMP/turn.json"
  curl -s --max-time 600 -b "$1" -H 'Content-Type: application/json' --data @"$TEST_TMP/turn.json" "$API/v1/responses"
}

# mint_key JAR NAME HDRFILE -> 0 when a key was minted; writes "Authorization: Bearer <key>" to HDRFILE.
mint_key() {
  local out="$TEST_TMP/key.json"
  curl -s --max-time 60 -b "$1" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg n "$2" '{name:$n, member_id:"", workspace:""}')" \
    "$API/v1/orgs/local/keys" > "$out"
  jq -e -r '.key | select(startswith("sk-hr-"))' "$out" >/dev/null || { rm -f "$out"; return 1; }
  jq -r '"Authorization: Bearer " + .key' "$out" > "$3"
  rm -f "$out"
}

bget() { curl -s --max-time 60 -H @"$1" "$API$2"; }
bcode() { http_code -H @"$1" "$API$2"; }

# run_turn_bearer HDRFILE HARNESS MODEL [SESSION] -> the response JSON.
run_turn_bearer() {
  turn_body "$2" "$3" "${4:-}" > "$TEST_TMP/turn.json"
  curl -s --max-time 600 -H @"$1" -H 'Content-Type: application/json' --data @"$TEST_TMP/turn.json" "$API/v1/responses"
}

answer_of() { jq -r '[.output[]? | select(.type=="message") | .content[]? | select(.type=="output_text") | .text] | join(" ")' <<<"$1" 2>/dev/null; }

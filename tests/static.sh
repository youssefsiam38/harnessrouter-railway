#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# Static validation: syntax, shellcheck, compose shape, image pins and configuration. No containers.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
trap 'rm -rf "$TEST_TMP"' EXIT

section "syntax"
for f in tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done
if python3 -m py_compile tests/mock/mock_openai.py 2>/dev/null; then pass "parses: tests/mock/mock_openai.py"; else fail "mock does not compile"; fi
for f in tests/*.sh; do
  if [ -x "$f" ]; then pass "executable: $f"; else fail "not executable: $f"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -x -s bash tests/*.sh; then pass "shellcheck tests"; else fail "shellcheck tests"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config -q; then pass "compose config"; else fail "compose config"; fi
cfg=$(docker compose -f compose.yaml config --format json)
assert_eq "services" "app mock" "$(jq -r '[.services | keys[]] | sort | join(" ")' <<<"$cfg")"
assert_eq "the console port binds to loopback" "127.0.0.1" "$(jq -r '[.services.app.ports[]? | .host_ip] | join(" ")' <<<"$cfg")"
assert_eq "the console listens on 3000" "3000" "$(jq -r '[.services.app.ports[]? | .target] | join(" ")' <<<"$cfg")"
assert_eq "the mock publishes no port" "" "$(jq -r '[.services.mock.ports[]? | .target] | join(" ")' <<<"$cfg")"
assert_eq "the data volume is mounted at /data" "/data" "$(jq -r '[.services.app.volumes[]? | .target] | join(" ")' <<<"$cfg")"
assert_contains "the app is the official image, pinned by digest" \
  '^harnessrouter/harnessrouter:[0-9.]*@sha256:[0-9a-f]\{64\}$' "$(jq -r '.services.app.image' <<<"$cfg")"
assert_contains "the mock image is pinned by digest" '@sha256:[0-9a-f]\{64\}$' "$(jq -r '.services.mock.image' <<<"$cfg")"
assert_eq "no user override (the entrypoint must start as root)" "null" "$(jq -r '.services.app.user // "null"' <<<"$cfg")"

section "configuration"
env_json=$(jq -c '.services.app.environment' <<<"$cfg")
assert_eq "PORT matches the console port" "3000" "$(jq -r .PORT <<<"$env_json")"
assert_eq "the backend set is lean" "claude,codex,opencode" "$(jq -r .HR_BACKENDS <<<"$env_json")"
assert_eq "the console user is set" "harnessrouter" "$(jq -r .HR_AUTH_USER <<<"$env_json")"
assert_contains "the compose console password defaults to a local placeholder" 'HR_AUTH_PASSWORD: ${HR_TEST_PASSWORD:-local-test-only' "$(cat compose.yaml)"
assert_eq "HR_SECRET_KEY is wired" "true" "$(jq -r 'has("HR_SECRET_KEY")' <<<"$env_json")"
assert_eq "the login gate is not disabled" "null" "$(jq -r '.HR_AUTH_DISABLED // "null"' <<<"$env_json")"

section "docs"
for f in README.md ARCHITECTURE.md SECURITY.md UPSTREAM.md MAINTENANCE.md THIRD_PARTY_NOTICES.md MARKETPLACE_AUDIT.md marketplace/OVERVIEW.md assets/icon.png licenses/HARNESSROUTER-LICENSE; do
  if [ -s "$f" ]; then pass "present: $f"; else fail "missing: $f"; fi
done
digest=$(jq -r '.services.app.image' <<<"$cfg" | sed 's/.*@//')
assert_contains "UPSTREAM.md records the pinned digest" "$digest" "$(cat UPSTREAM.md)"
assert_contains "the overview has the required Deployment Dependencies heading" '^### Deployment Dependencies' "$(cat marketplace/OVERVIEW.md)"
assert_contains "MAINTENANCE.md documents upgrades" '## Upgrading' "$(cat MAINTENANCE.md)"

section "secrets hygiene"
mapfile -t tracked < <(git ls-files 2>/dev/null | grep . || find . -type f -not -path './.git/*')
if [ "${#tracked[@]}" -gt 0 ] && grep -lE '(sk-ant-[A-Za-z0-9_-]{20,}|sk-hr-[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{32,}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "${tracked[@]}" 2>/dev/null; then
  fail "a credential-shaped string is in the repository"
else
  pass "no credential-shaped strings in ${#tracked[@]} files"
fi

summary

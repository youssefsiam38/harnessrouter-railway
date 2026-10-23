# Marketplace audit

## Identity

| | |
|---|---|
| App | HarnessRouter Community Edition |
| Upstream | https://github.com/HarnessRouter/harnessrouter (3.3k stars, active: several releases a week) |
| Image | `harnessrouter/harnessrouter:0.36.0@sha256:42223fdd…` (official, Docker Hub, amd64 + arm64, ~3 GB) |
| Template shape | One service, one volume, no wrapper |

## Licence and brand

- Apache-2.0. Redistribution of the unmodified image is fine; LICENSE and NOTICE are carried in `licenses/`.
- Claude Code (Anthropic's terms) and other CLIs are installed by the container at first boot, not
  redistributed by the image or the template. Upstream designed the image this way for exactly that reason.
- No trademark policy found upstream. The template uses the name descriptively, ships a generic
  icon, and states it is not affiliated.

## Existing marketplace entry

A `harnessrouter` template already exists (published 2026-09-20, image `0.20.1`, 0 deploys at
review). It runs upstream's default `HR_BACKENDS` (26 CLIs, several GB on first boot), pins by tag
only, and shows no evidence of end-to-end testing. This template differs: lean default backends,
digest pin, generated `HR_SECRET_KEY`, a 600 s first-boot health window, an upgrade guide, and
live e2e tests.

## Security review

| Concern | Finding | Handling |
|---|---|---|
| Published default login | `harnessrouter`/`harnessrouter` in upstream README | `HR_AUTH_PASSWORD` generated; tests assert the default is rejected |
| Gateway has no auth of its own (`HR_IDENTITY_MODE=off`) | Bound to 127.0.0.1; reachable only through the console proxy | Console middleware gates every route; bearer keys reach `/api/harness/*` only |
| Root container | Required: runner switches to a per-session uid | Railway runs as root by default; no `RAILWAY_RUN_UID` needed |
| Stored DB credentials | Refused unless `HR_SECRET_KEY` is set | Generated per deploy |
| Cookie flags | `HttpOnly; SameSite=Lax`, `Secure` over HTTPS | Verified live |
| Supply chain | CLIs downloaded at first boot; upstream pins versions (and digests for several) | Lean set limits the surface; image pinned by digest |

## Tests

| Suite | Assertions | What it proves |
|---|---|---|
| `tests/static.sh` | 41 | Compose shape, pins, config, docs, secret scan |
| `tests/smoke.sh` | 32 | Lean first boot, gate, login, real opencode + codex turns, API key, custom harness, session follow-up, files |
| `tests/persistence.sh` | 12 | Integration, key, harness, session, file survive a container recreate; CLIs not reinstalled |
| `tests/railway-smoke.sh` | 25 live + 16 after redeploy | The same flows over HTTPS on a clean-room deploy of the template (private mock sidecar), then `--verify` after a redeploy |

## Deploy-time inputs

None required. A provider key is added in the console after deploy.

## Limits

- Free/Trial volumes (0.5 GB) are too small for the CLIs. Hobby or Pro is required.
- Claude Code turns were not exercised end to end (the mock speaks the OpenAI chat and Responses
  formats, not Anthropic Messages). Its CLI is installed and its base is listed.

## Verdict

Shippable.

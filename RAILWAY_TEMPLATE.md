# Railway template configuration

The template's exact configuration. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | HarnessRouter |
| Code | `harnessrouter-2` |
| Template id | `e73808a7-d2f9-45b6-bbcd-322cfe2b232a` |
| Deploy URL | https://railway.com/deploy/harnessrouter-2 |
| Category | AI/ML |
| Card description | Self-hosted API for Codex, Claude Code & OpenCode agents. Lean & tested |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

Generated values use Railway's `secret()` function: `hexN` is `${{secret(N, "abcdef0123456789")}}` and `alnumN` is
`${{secret(N, "a-zA-Z0-9")}}` spelled out. Alphanumeric passwords are used wherever a value is embedded in a
connection URL, so nothing needs percent-encoding. The image is referenced by tag and digest
(see the Source row); `UPSTREAM.md` records how to refresh it.

## Services

### `app`

| Field | Value |
|---|---|
| Source | `harnessrouter/harnessrouter:0.36.0@sha256:42223fddfb1dcad128d1943ab4f8306ec905eeaf282da64417c995d814af24d7` |
| Public domain | target port 3000 |
| Volume | `/data` |
| Healthcheck | `/login`, timeout from `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `PORT` | `3000` |
| `HR_BACKENDS` | `claude,codex,opencode` |
| `HR_AUTH_USER` | `harnessrouter` |
| `HR_AUTH_PASSWORD` | generated, alnum32 |
| `HR_SECRET_KEY` | generated, alnum48 |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `600` |

## Notes

- Stock image, no wrapper. Health check `/login` (the only 200 without a session); 600 s window because the CLI install runs before the console listens.
- `HR_BACKENDS=claude,codex,opencode` (~750 MB in `/data/agent-tools`, ~2 min first boot). Upstream's default is 26 CLIs.
- Volume size cannot be set by a template; it follows the plan (Hobby 5 GB, Pro 50 GB). Free/Trial 0.5 GB is too small.
- A password changed on the Profile page (`/data/selfhost-auth.json`) overrides `HR_AUTH_PASSWORD`.
- Keep `HR_SECRET_KEY` unchanged across upgrades.
- Live e2e used a private mock provider sidecar (`mock.railway.internal:8080`); results: 25/25 full, 16/16 after a redeploy. Upgrade path 0.35.17 -> 0.36.0 checked locally on one volume.

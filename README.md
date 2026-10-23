# HarnessRouter on Railway

One-click Railway template for [HarnessRouter Community Edition](https://github.com/HarnessRouter/harnessrouter),
the self-hosted unified interface for agent harnesses: run Codex, Claude Code, OpenCode and more
through one OpenAI Responses-compatible API, with sessions, streaming, files and cancellation.

> Community-maintained template. Not affiliated with or endorsed by HarnessRouter. This repository
> ships its own generic icon, not the HarnessRouter logo.

- **Image:** official `harnessrouter/harnessrouter`, unmodified, pinned by digest (see [UPSTREAM.md](UPSTREAM.md)).
- **Licence:** HarnessRouter is Apache-2.0. The template's own files are MIT ([LICENSE](LICENSE)).
- **Agent CLIs** are not in the image. The container installs them into the volume on first boot,
  under each CLI's own licence terms (Claude Code: Anthropic's terms).

## What you get

| | |
|---|---|
| Service | One `app` service: console, gateway and runner in one container |
| Public URL | HTTPS Railway domain → console on port 3000 (`/login` is the health check) |
| Storage | One volume at `/data`: SQLite databases, files, workspaces, secret store, installed CLIs |
| Backends | `HR_BACKENDS=claude,codex,opencode` by default (~750 MB on the volume, ~2 min first boot) |
| Login | User `harnessrouter`, password generated per deploy (`HR_AUTH_PASSWORD`) |
| Encryption key | `HR_SECRET_KEY` generated per deploy (encrypts stored database connection strings) |

What this template does differently from a plain image deploy:

- **Lean first boot.** Upstream installs all 26 harness CLIs by default (several GB, some 600+ MB
  each). This template installs three, so it fits a Hobby volume with room to spare and passes its
  health check quickly. Add more with `HR_BACKENDS` whenever you need them.
- **Digest-pinned image**, so a redeploy never silently moves to a new release.
- **No published default password.** The upstream default (`harnessrouter`/`harnessrouter`) is
  never used.
- **Tested end to end** on a live deploy: real opencode and codex turns, API keys, custom harnesses,
  session files, and data surviving a redeploy.

## Deploy

1. Deploy the template. No inputs are required.
2. Wait for the first boot (about 2 minutes while the CLIs install).
3. Open the service URL. Sign in as `harnessrouter` with the `HR_AUTH_PASSWORD` value from the
   service's **Variables** tab.
4. In the console, open the account menu → **Bring your own key** and add a provider key.
5. For API use, create a key under **API Keys**. The API base is `https://<your-domain>/api/harness`.

```bash
curl -sS https://<your-domain>/api/harness/v1/responses \
  -H "Authorization: Bearer $HARNESSROUTER_API_KEY" -H 'content-type: application/json' \
  -d '{"input":"Reply with: it works.","metadata":{"harness_id":"codex"},"model":"gpt-5.4-mini","stream":false}'
```

## Volume size

Railway sets the volume size from your plan, and a template cannot change it: Free/Trial 0.5 GB,
Hobby 5 GB, Pro 50 GB. The lean backend set needs about 0.75 GB plus your data, so **use Hobby or
Pro**; a 0.5 GB volume is too small for the CLIs. If you add backends or keep many workspaces, grow
the volume with **Live Resize** in the volume's settings (no downtime).

## Upgrading

See [MAINTENANCE.md](MAINTENANCE.md#upgrading). In short: back up the volume, change the service
image to the new pinned version, redeploy, and keep `HR_SECRET_KEY` unchanged.

## Security

See [SECURITY.md](SECURITY.md). The console can run agents with your provider keys and read every
transcript, so keep the generated password private and rotate it from the **Profile** page.

## Repository layout

| Path | Purpose |
|---|---|
| `compose.yaml` | Local test topology: the app plus a test-only mock provider |
| `tests/static.sh` | Compose shape, digest pins, configuration, docs and secret scan |
| `tests/smoke.sh` | First boot, login gate, real opencode/codex turns, API key, harness, files |
| `tests/persistence.sh` | State survives recreating the container on the same volume |
| `tests/railway-smoke.sh` | The same flows over HTTPS against a live deploy, plus `--verify` after a redeploy |
| `tests/mock/mock_openai.py` | Stub OpenAI chat + Responses provider (tests only, never deployed by the template) |
| `marketplace/OVERVIEW.md` | Marketplace page |

## Local development

```bash
tests/static.sh
tests/smoke.sh
tests/persistence.sh
```

Needs Docker, `jq`, `curl` and `shellcheck`. The image is about 3 GB.

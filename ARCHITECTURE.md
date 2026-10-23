# Architecture

```
            HTTPS (Railway edge)
                    │
                    ▼  PORT=3000
┌──────────────────────── app (harnessrouter/harnessrouter) ────────────────────────┐
│  console  (Next.js, :3000, user "agent")  ── login gate on every route           │
│      │ loopback                                                                   │
│      ▼                                                                            │
│  gateway  (FastAPI, 127.0.0.1:8080, user "agent")  ── API, keys, integrations     │
│      │ loopback                                                                   │
│      ▼                                                                            │
│  runner   (FastAPI, 127.0.0.1:8081, root) ── spawns agent CLIs, one uid/session   │
└───────────────────────────────────┬──────────────────────────────────────────────┘
                                    │
                         volume /data (SQLite, blobs, secrets,
                         workspaces, agent-tools/ CLIs)
```

One Railway service, one volume, no database or cache service. The image's entrypoint supervises
the three processes; if any one exits, the container exits and Railway restarts it.

## Wiring

| Setting | Value | Why |
|---|---|---|
| Image | `harnessrouter/harnessrouter:<tag>@sha256:…` | Official image, unmodified, digest-pinned |
| `PORT` | `3000` | The console's port; Railway routes the edge and the health check here |
| Health check | `/login` | The only page that answers 200 without a session |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `600` | First boot installs CLIs before anything listens |
| Volume | `/data` | Everything durable, including the installed CLIs |
| `HR_BACKENDS` | `claude,codex,opencode` | Lean first boot; upstream's default is 26 CLIs |
| `HR_AUTH_USER` / `HR_AUTH_PASSWORD` | `harnessrouter` / generated | Console login |
| `HR_SECRET_KEY` | generated | Encrypts stored database connection strings |

## Why no wrapper

The stock image already fits Railway: it listens on `0.0.0.0:$PORT`, needs only one volume, gates
every route with its own login, and starts as root (Railway's default) to drop privileges per
process. Upstream's insecure defaults are fixed with variables, so nothing needs a front door or a
patched entrypoint.

## First boot vs later boots

First boot installs the CLIs named in `HR_BACKENDS` into `/data/agent-tools` (~2 minutes for the
default three), then starts the processes. Later boots check each CLI's version against the pin in
the image, reinstall only what changed, and come up in seconds.

## Auth

- **Console:** `POST /api/selfhost/login` sets an `HttpOnly` `hr_selfhost` cookie (`Secure` over
  HTTPS). Middleware rejects every other route without it.
- **API:** `Authorization: Bearer sk-hr-…` keys minted on the **API Keys** page reach
  `/api/harness/*`; the gateway validates them.
- **Profile changes** write `/data/selfhost-auth.json`, which then takes precedence over
  `HR_AUTH_PASSWORD`.

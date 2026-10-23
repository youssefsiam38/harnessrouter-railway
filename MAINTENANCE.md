# Maintenance

## Upgrading

### For a deployed instance

HarnessRouter releases often (several tags a week). The template pins one version by digest, so your
instance stays on it until you move it.

1. **Back up first.** In Railway, open the volume → **Backups** → create a backup. The volume holds
   the SQLite databases, secret store, workspaces and CLIs. Upstream changes data on some upgrades
   (for example, 0.32.0 purges records deleted more than 30 days earlier), and you cannot downgrade
   cleanly without a backup.
2. **Read the release notes** for every version you skip:
   <https://github.com/HarnessRouter/harnessrouter/releases>.
3. **Change the image.** Service → **Settings** → **Source** → set the image to
   `harnessrouter/harnessrouter:<new-tag>` (add `@sha256:<digest>` to pin it; see
   [UPSTREAM.md](UPSTREAM.md#refreshing-the-digest)). Railway redeploys.
4. **Expect a slower boot** if the release changed a CLI pin: the entrypoint reinstalls only the CLIs
   whose versions differ. The 600 s health-check window covers this for the default backends.
5. **Check:** sign in, run one task, and confirm the log line
   `backends available: claude codex opencode` (or your list).

Keep the same values for:

- `HR_SECRET_KEY` (changing it means reconnecting every stored database), and
- the volume (never delete it to "start fresh" unless you mean it).

Notes:

- A password changed on the **Profile** page is stored in `/data/selfhost-auth.json` and wins over
  `HR_AUTH_PASSWORD`. Changing the variable later has no effect until that file is removed.
- The service has a volume, so each redeploy has a few seconds of downtime (Railway never mounts one
  volume into two deployments).
- **Adding backends:** append to `HR_BACKENDS` (for example `claude,codex,opencode,gemini,hermes`)
  and redeploy. Each adds disk; some (openhands, aider) are 600+ MB. Grow the volume with **Live
  Resize** if needed. Removing a backend from the list hides it; its files stay on the volume.

### For this template repository

1. Resolve the new multi-arch digest ([UPSTREAM.md](UPSTREAM.md#refreshing-the-digest)).
2. Update the pin in `compose.yaml`, `UPSTREAM.md` and `_audit/spec_harnessrouter.py`.
3. Run `tests/static.sh`, `tests/smoke.sh`, `tests/persistence.sh`.
4. Push; wait for CI to pass.
5. Re-point the template's image (`tplkit.patch_template`), deploy it to a clean-room project, run
   `tests/railway-smoke.sh` and `--verify` after a redeploy, then delete the clean-room project.
6. Regenerate `RAILWAY_TEMPLATE.md`.

## Rebuilding the template from scratch

`_audit/spec_harnessrouter.py` → `tplkit.skeleton` → `railway templates create` →
`tplkit.patch_template` → verify. Only the skeleton step sets the volume, domain and health check.

## Gotchas found while building this

- The health check must be `/login`; every other route redirects (307) or answers 401 without a session.
- First boot installs CLIs **before** the console listens, so the health check needs a long window
  (600 s). The default three take about 2 minutes; upstream's full set of 26 can run out of disk or time.
- Bearer API keys reach only `/api/harness/*`; console pages need the cookie.
- The self-host org id is the constant `local` (`POST /api/harness/v1/orgs/local/keys` mints a key).
- Custom providers: `api_format: "openai"` (chat) drives opencode; codex needs `api_format: "responses"`.
- The session cookie is `hr_selfhost`; curl writes `HttpOnly` cookies to a jar as `#HttpOnly_…` lines.

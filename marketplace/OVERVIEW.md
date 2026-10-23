# Deploy and Host HarnessRouter on Railway

HarnessRouter is the self-hosted unified interface for agent harnesses: run Codex, Claude Code, OpenCode and more through one OpenAI Responses-compatible API, with persistent sessions, streaming, files, cancellation and structured failures. This template deploys HarnessRouter Community Edition with a generated console password, a generated encryption key, a lean set of agent CLIs and a persistent volume. It is community-maintained, not affiliated with or endorsed by HarnessRouter, and ships its own generic icon.

## About Hosting HarnessRouter

HarnessRouter runs as one container: a Next.js console on the public port, plus a gateway and an agent runner on loopback. SQLite databases, files, workspaces, the secret store and the installed agent CLIs all live on one Railway volume at `/data`. The agent CLIs are not in the image; the container installs them into the volume on first boot. Upstream installs 26 by default (several GB). This template installs three (`claude,codex,opencode`, about 750 MB), so the first boot takes about 2 minutes and fits a Hobby volume. Add more any time with `HR_BACKENDS`. The upstream default login (`harnessrouter`/`harnessrouter`) is replaced with a generated password.

## Common Use Cases

- Give your product one API for many coding agents and switch harnesses without code changes
- Run Codex, Claude Code or OpenCode tasks from a private browser console with your own provider keys
- Keep agent sessions, workspaces and files on infrastructure you control
- Build custom harnesses with your own prompts, skills, MCP servers and models

## Dependencies for HarnessRouter Hosting

- No external services: the database (SQLite) and file storage live on the included volume.
- A model provider API key of your own (Anthropic, OpenAI, OpenRouter, Google, or any compatible endpoint), added in the console after deploy.
- A paid Railway plan. The CLIs need more than the 0.5 GB volume of the Free/Trial plans; Hobby (5 GB) and Pro (50 GB) volumes fit.

### Deployment Dependencies

- HarnessRouter Community Edition: https://github.com/HarnessRouter/harnessrouter (Apache-2.0)
- Template repository, tests and upgrade guide: https://github.com/youssefsiam38/harnessrouter-railway

### Implementation Details

- Official `harnessrouter/harnessrouter` image, unmodified, pinned by digest (0.36.0).
- `PORT=3000`; health check `/login` with a 600 s window to cover the first-boot CLI install.
- Sign in as `harnessrouter` with the generated `HR_AUTH_PASSWORD` from the service's Variables tab. Change it later on the Profile page.
- `HR_SECRET_KEY` is generated and encrypts stored database connection strings. Keep it unchanged across upgrades.
- API base: `https://<your-domain>/api/harness`, with keys minted on the API Keys page.
- Upgrading: back up the volume, set the service image to a newer tag, redeploy. See MAINTENANCE.md in the template repository.
- Tested in CI and on a live Railway deployment: login gate, real opencode and codex turns against a mock provider, API keys, custom harnesses, session files, and data surviving a redeploy.

## Why Deploy HarnessRouter on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying HarnessRouter on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.

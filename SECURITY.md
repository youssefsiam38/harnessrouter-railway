# Security

## What is at stake

A HarnessRouter console can create agents, read every task transcript and file, and run agent
CLIs with your provider keys inside the container. Treat its password like a provider key.

## What the template does

- Generates `HR_AUTH_PASSWORD` (32 random alphanumerics) per deploy. The upstream default
  `harnessrouter`/`harnessrouter`, which is published in its README, is never used; the tests check
  it is rejected.
- Leaves the image's login gate on (`HR_AUTH_DISABLED` is never set).
- Generates `HR_SECRET_KEY`, so stored database connection strings are encrypted at rest.
- Keeps the gateway and runner on loopback. Only the console is public, over Railway HTTPS, and
  its session cookie is `HttpOnly`, `SameSite=Lax` and `Secure`.
- Pins the image by digest.
- Runs upstream unmodified. Agent processes run under per-session uids, as upstream designs.

## What you should do

- Keep the generated password private. Rotate it from the console's **Profile** page; after that,
  the stored credentials win over the `HR_AUTH_PASSWORD` variable.
- Mint one API key per product backend, never ship a key to browser code, and revoke unused keys.
- **Keep `HR_SECRET_KEY` unchanged.** Changing it means reconnecting every stored database.
- Back up the volume (Railway volume backups) before upgrades. It holds the databases, the secret
  store and every workspace.
- Agents run code. Connect only providers, MCP servers and databases you trust, and limit the
  credentials you give them.

## Reporting

Template issues: open an issue on this repository. HarnessRouter vulnerabilities: follow
[upstream's SECURITY.md](https://github.com/HarnessRouter/harnessrouter/blob/main/SECURITY.md).

# Third-party notices

| Component | Licence | How it is used |
|---|---|---|
| HarnessRouter Community Edition (`harnessrouter/harnessrouter`) | Apache-2.0 | Run unmodified from the official image. Licence and NOTICE in `licenses/`. |
| Agent CLIs (Claude Code, Codex, OpenCode, and any others you add to `HR_BACKENDS`) | Each CLI's own terms (Claude Code: Anthropic's commercial terms; Codex: Apache-2.0; OpenCode: MIT) | Not shipped by this template or the image. The container downloads them at first boot into your volume, so you install them under their terms. |
| `python:3.12-slim` | PSF / Debian licences | Local tests only (runs the mock provider). Not part of the Railway template. |

This repository's own files (tests, docs, the generic icon) are MIT-licensed; see `LICENSE`.

"HarnessRouter" is the upstream project's name, used here only to describe what the template
deploys. This template is community-maintained, not affiliated with or endorsed by the HarnessRouter
project, and does not use its logo.

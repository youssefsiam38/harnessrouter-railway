# Upstream

| | |
|---|---|
| Project | [HarnessRouter/harnessrouter](https://github.com/HarnessRouter/harnessrouter) (Community Edition) |
| Licence | Apache-2.0 ([licenses/HARNESSROUTER-LICENSE](licenses/HARNESSROUTER-LICENSE), [NOTICE](licenses/HARNESSROUTER-NOTICE)) |
| Official image | [`harnessrouter/harnessrouter`](https://hub.docker.com/r/harnessrouter/harnessrouter) (Docker Hub, amd64 + arm64) |
| Pinned tag | `0.36.0` |
| Pinned digest | `sha256:42223fddfb1dcad128d1943ab4f8306ec905eeaf282da64417c995d814af24d7` (multi-arch index) |
| Full reference | `harnessrouter/harnessrouter:0.36.0@sha256:42223fddfb1dcad128d1943ab4f8306ec905eeaf282da64417c995d814af24d7` |

The template uses the image unmodified. No wrapper image is built.

## Refreshing the digest

```bash
curl -s "https://hub.docker.com/v2/repositories/harnessrouter/harnessrouter/tags/<tag>/" | jq -r '.digest, [.images[].architecture]'
```

Use the index digest (it covers both architectures). Then follow [MAINTENANCE.md](MAINTENANCE.md#upgrading).

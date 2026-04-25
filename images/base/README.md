# base

Common base layer for all security-platform-toolchain images.

## Contents

| Layer | Description |
|-------|-------------|
| Ubuntu 24.04 | LTS base OS |
| Python 3 + pip | Script runtime |
| `tini` | PID-1 / signal reaping |
| `jq`, `curl`, `git`, `wget` | Common utilities |
| `jsonschema` (pip) | Schema validation |
| `/usr/local/lib/spt/logging.sh` | Structured log helpers |
| `/usr/local/bin/entrypoint.sh` | Standard entrypoint |
| `/usr/local/bin/emit-job-report` | Job report emitter |
| `/usr/local/share/spt/schemas/` | JSON schemas |

## Non-root user

All tool images run as `spt` (UID 1001 / GID 1001).

## Volume

| Mount | Purpose |
|-------|---------|
| `/artifacts` | Shared output volume |
| `/workspace` | Source code / target (read-only recommended) |

## Build

```bash
# Run from the repository root (context must be repo root so common/ and schemas/ are accessible)
docker build \
  -f images/base/Dockerfile \
  -t registry.internal/security-platform/spt-base:latest \
  .
```

Or simply:

```bash
make base
```

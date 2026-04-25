# gitnexus

**GitNexus** CLI/MCP code intelligence graph tool.  Builds and queries a
graph of code relationships (call graphs, symbol references, dependency edges)
to support platform workflows and MCP tool calls.

## Modes (`GITNEXUS_MODE`)

| Mode | Description |
|------|-------------|
| `clone` (default) | Clone `GIT_REPO` at `GIT_REF` into `/workspace` |
| `upload` | Upload everything under `$ARTIFACTS_DIR` to Nexus |
| `download` | Download a single file (`NEXUS_PATH`) from Nexus |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GITNEXUS_MODE` | `clone` | Operating mode |
| `GIT_REPO` | — | Git clone URL |
| `GIT_REF` | `HEAD` | Branch, tag, or SHA to check out |
| `NEXUS_URL` | — | Base URL of Nexus instance |
| `NEXUS_USER` | — | Nexus username |
| `NEXUS_PASS` | — | Nexus password / API token |
| `NEXUS_REPO` | — | Nexus repository name |
| `NEXUS_PATH` | — | Remote path for download mode |
| `ARTIFACTS_DIR` | `/artifacts` | Output directory |

## Security Note

Pass `NEXUS_PASS` via Docker secrets or an environment file — never hard-code
credentials in the image or docker-compose.yml.

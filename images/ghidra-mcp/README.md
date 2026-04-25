# ghidra-mcp

Reusable bethington/GhidraMCP environment for analyst workflows, Ghidra Server
workflows, and local MCP clients. It is kept separate from `ghidra-exporter`,
which is the controlled batch producer for platform ingestion.

The image includes Ghidra through `spt-ghidra-base` and builds GhidraMCP during
the connected Docker build. Runtime is intended to work without internet access.

Build-time knobs:

| Variable | Default | Purpose |
| --- | --- | --- |
| `GHIDRA_VERSION` | `12.0.4` | Ghidra version used by `ghidra-base` and GhidraMCP build setup |
| `GHIDRA_DATE` | `20260303` | NSA release date suffix for the Ghidra zip |
| `GHIDRA_MCP_REPO` | `https://github.com/bethington/ghidra-mcp.git` | GhidraMCP source repo |
| `GHIDRA_MCP_REF` | `v5.5.0` | Tag, branch, or ref to build |

Runtime modes:

| `GHIDRA_MCP_MODE` | Behavior |
| --- | --- |
| `smoke` | Default. Emits environment and installed-artifact metadata. |
| `bridge` | Runs `bridge_mcp_ghidra.py` for stdio/HTTP/SSE MCP use. |
| `headless` | Runs the GhidraMCP headless HTTP server. |

For headless server use, set `GHIDRA_MCP_BIND_ADDRESS`, `GHIDRA_MCP_PORT`, and
the upstream security variables such as `GHIDRA_MCP_AUTH_TOKEN`,
`GHIDRA_MCP_FILE_ROOT`, and `GHIDRA_MCP_ALLOW_SCRIPTS` as needed.

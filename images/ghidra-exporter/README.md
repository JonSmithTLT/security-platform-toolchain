# ghidra-exporter

Controlled Ghidra export workflows for platform ingestion.

## Modes

| `GHIDRA_EXPORT_MODE` | Target style | Behavior |
| --- | --- | --- |
| `headless-basic` | `GHIDRA_TARGET=/workspace/my_binary` | Runs `analyzeHeadless` and captures logs. |
| `direct-script` | `GHIDRA_TARGET=/workspace/my_binary` | Runs `analyzeHeadless` with optional `GHIDRA_POST_SCRIPT`. |
| `mcp-scripted` | `GHIDRA_MCP_HOST` + `GHIDRA_MCP_PORT` | Connects to an existing Ghidra/MCP context. |

For `mcp-scripted`, server/port means the exporter is connecting to an existing
Ghidra/MCP context. That project may include analyst renames, comments, type
changes, or other enriched state.

Local file or directory mode means the container owns import/analyze/export from
scratch and records `project_state=fresh_headless_analysis`.

Every run writes provenance to:

```text
results/ghidra-exporter/normalized/ghidra-export.json
```

Important fields:

```json
{
  "export_mode": "mcp-scripted",
  "target_mode": "existing_mcp_server",
  "project_state": "possibly_analyst_enriched"
}
```

# gitnexus

Real GitNexus CLI/MCP code intelligence image based on
`abhigyanpatwari/GitNexus`.

The connected Docker build installs the pinned npm package globally
(`GITNEXUS_VERSION=1.6.3` by default) and applies a build-time patch to
`lbug-adapter.js` that enables fully offline LadybugDB extension loading.

`spt-gitnexus` supports offline GitNexus analysis with local LadybugDB
`fts`/`vector` extension loading under `--network none`.

Build-time provenance can be tightened with:

```bash
docker build \
  --build-arg GITNEXUS_VERSION=1.6.3 \
  --build-arg GITNEXUS_SOURCE_COMMIT=<upstream-tag-or-commit-sha> \
  ...
```

Every normal run emits `results/gitnexus/raw/gitnexus-provenance.json` and
records `gitnexus_version`, `source_ref`, and `source_commit` in
`job-report.json`.

## Modes

| `GITNEXUS_MODE` | Behavior |
| --- | --- |
| `version` | Print GitNexus version and emit SPT artifacts. |
| `analyze` | Run `gitnexus analyze` against `GITNEXUS_TARGET`. |
| `status` | Run `gitnexus status`. |
| `list` | Run `gitnexus list`. |
| `setup` | Run `gitnexus setup`. |
| `mcp` | Exec `gitnexus mcp` for stdio MCP use. |
| `serve` | Exec `gitnexus serve` for local HTTP/web UI bridge use. |

Default analyze args are empty because GitNexus CLI flags have changed across
releases. Set `GITNEXUS_ANALYZE_ARGS` only after confirming the pinned
GitNexus version supports those flags.

## LadybugDB Extensions

For full offline GitNexus search/vector behavior, mount the data-bundle
LadybugDB extensions and require them:

```bash
docker run --rm --network none \
  -e GITNEXUS_MODE=analyze \
  -e GITNEXUS_TARGET=/workspace \
  -e GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS=1 \
  -e GITNEXUS_LADYBUG_EXTENSIONS_DIR=/data/ladybug-extensions \
  -e GITNEXUS_OFFLINE=1 \
  -e SPT_OFFLINE=1 \
  -v /opt/spt-data/sources/ladybug-extensions:/data/ladybug-extensions:ro \
  -v "$PWD:/workspace" \
  -v "$PWD/artifacts:/artifacts" \
  "$REGISTRY/spt-gitnexus:$TAG"
```

Set `GITNEXUS_OFFLINE=1` or `SPT_OFFLINE=1` to put the patched extension loader
into offline mode. In offline mode the loader attempts a local `LOAD EXTENSION`
and stops immediately on failure instead of falling back to
`INSTALL` (which would attempt a network fetch from `extension.ladybugdb.com`).

The wrapper stages the mounted files into several Ladybug/Kuzu-compatible local
cache layouts before running `gitnexus analyze`. When
`GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS=1`, the wrapper fails if GitNexus still
logs an external extension download attempt.

The strict smoke records diagnostics in:

```text
results/gitnexus/raw/ladybug-extension-staging.txt
results/gitnexus/normalized/gitnexus-summary.json
```

`ladybug_classification` is one of:

- `extension_load_success`
- `network_fetch_attempted`
- `extensions_present_not_used`
- `extension_abi_mismatch`
- `extension_path_unknown`
- `extensions_missing`

## Example

```bash
docker run --rm --network none \
  -e GITNEXUS_MODE=analyze \
  -e GITNEXUS_TARGET=/workspace \
  -v "$PWD:/workspace" \
  -v "$PWD/artifacts:/artifacts" \
  "$REGISTRY/spt-gitnexus:$TAG"
```

# osv-scanner

Runs OSV Scanner. For offline runs, mount the OSV local DB cache at `/osv-db`
or set `OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY`.

The wrapper maps:

```text
OSV_OFFLINE=1
OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY=/osv-db
```

to native OSV Scanner flags:

```text
OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY=/osv-db \
osv-scanner scan source \
  --offline-vulnerabilities \
  --format json \
  --output-file /artifacts/results/osv-scanner/raw/osv-scanner.json \
  /workspace
```

Prepare the DB cache on a connected machine with OSV Scanner's
`--download-offline-databases` workflow. Some richer dependency resolution
paths may be unavailable in offline mode.

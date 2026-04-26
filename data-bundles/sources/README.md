# Data Sources

This directory is the staging area for connected-side data fetches. Generated
content under this directory is intentionally ignored by Git.

Run:

```bash
make data-fetch TAG=<tag>
make data-bundle TAG=<tag>
make data-verify TAG=<tag>
```

The generated data may include advisory PoC text, exploit commands, webshell
snippets, suspicious indicators, and security scanner fixtures. See
`../SECURITY_NOTES.md` before transferring or scanning the bundle.

GitNexus/LadybugDB extension payloads, when fetched, live under
`ladybug-extensions/` and are used to avoid runtime `fts`/`vector` extension
downloads in air-gapped runs.

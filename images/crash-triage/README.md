# crash-triage

Turns sanitizer/crash evidence into normalized triage artifacts and a markdown
dossier.

First-class smoke path parses ASAN logs and emits:

- `normalized/crash-triage.json`
- `normalized/stacktrace.json`
- `normalized/crash-signature.json`
- `reports/triage.md`

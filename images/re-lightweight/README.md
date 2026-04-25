# re-lightweight

Cheap offline binary/file triage using `file`, `strings`, `sha256sum`,
binutils, and ExifTool.

Outputs an inventory JSONL file plus bounded strings extracts for the first
`RE_MAX_FILES` files under `RE_TARGET`.

# Release Checklist: v0.1.1

Use this checklist on the connected build host before publishing release
assets. The release is considered publishable only after image, data, functional,
bundle, and restore validation pass.

## 1. Set Release Variables

```bash
export REGISTRY=registry.internal/security-platform
export TAG=0.1.1
export DATA_DIR=data-bundles/sources
```

The automated release driver can run this checklist end to end:

```bash
make release-smoke REGISTRY=$REGISTRY TAG=$TAG DATA_DIR=$DATA_DIR
```

It fetches data, runs smoke tests, exports bundles, splits large tarballs,
verifies checksums, and writes:

```text
offline-bundles/out/spt-release-$TAG.upload-assets.txt
offline-bundles/out/spt-release-$TAG.gh-upload.sh
```

Use the manual sections below when you need to rerun or debug individual
stages.

The restore-side driver validates the generated assets from the consumer side:

```bash
make release-restore REGISTRY=$REGISTRY TAG=$TAG RUN_FUNCTIONAL=1
```

It verifies split parts, loads the image bundle, runs offline startup checks,
extracts the data bundle, runs data-bundle smoke, and optionally runs the full
functional smoke from the restored data directory.

## 2. Refresh Data Bundle Sources

```bash
make data-fetch TAG=$TAG DATA_DIR=$DATA_DIR
make data-bundle-smoke TAG=$TAG DATA_DIR=$DATA_DIR
```

Expected result:

- OSV offline DBs are present.
- GitHub Advisory Database is present.
- YARA, Semgrep, and CodeQL data are present.
- LadybugDB `fts` and `vector` extensions are present.

## 3. Build And Validate Images

```bash
make build-all REGISTRY=$REGISTRY TAG=$TAG
make verify-offline REGISTRY=$REGISTRY TAG=$TAG
make functional-smoke REGISTRY=$REGISTRY TAG=$TAG DATA_DIR=$DATA_DIR
make smoke-honggfuzz REGISTRY=$REGISTRY TAG=$TAG || true
```

Expected result:

- `verify-offline` starts every image with `--network none`.
- `functional-smoke` passes schema validation and fixture assertions.
- GitNexus indexes a real fixture git repo, loads Ladybug extensions offline,
  emits index evidence, and does not attempt `extension.ladybugdb.com`.
- AFL++ and libFuzzer run real tiny fuzz campaigns.
- honggfuzz is installed and reports `engine_status=experimental`.

## 4. Export Bundles

```bash
make bundle REGISTRY=$REGISTRY TAG=$TAG
make verify-bundle TAG=$TAG

make data-bundle TAG=$TAG DATA_DIR=$DATA_DIR
make data-verify TAG=$TAG
```

Expected outputs:

```text
offline-bundles/out/spt-bundle-$TAG.tar
offline-bundles/out/spt-bundle-$TAG.tar.sha256
offline-bundles/out/spt-bundle-$TAG.manifest.json
data-bundles/out/spt-data-bundle-$TAG.tar
data-bundles/out/spt-data-bundle-$TAG.tar.sha256
```

## 5. Split Large Release Assets

GitHub Release assets have a size limit. Split any tarball over the limit:

```bash
cd offline-bundles/out
split -b 1900M spt-bundle-$TAG.tar spt-bundle-$TAG.tar.part-
sha256sum spt-bundle-$TAG.tar.part-* > spt-bundle-$TAG.parts.sha256
cd ../..
```

If the data bundle is over the release asset size limit:

```bash
cd data-bundles/out
split -b 1900M spt-data-bundle-$TAG.tar spt-data-bundle-$TAG.tar.part-
sha256sum spt-data-bundle-$TAG.tar.part-* > spt-data-bundle-$TAG.parts.sha256
cd ../..
```

## 6. Restore Validation From Generated Artifacts

Preferred path:

```bash
make release-restore REGISTRY=$REGISTRY TAG=$TAG RUN_FUNCTIONAL=1
```

The manual equivalent is below for debugging.

Reassemble split parts if applicable:

```bash
cat offline-bundles/out/spt-bundle-$TAG.tar.part-* > offline-bundles/out/spt-bundle-$TAG.tar
sha256sum -c offline-bundles/out/spt-bundle-$TAG.tar.sha256
```

Load the generated image bundle into Docker:

```bash
docker load -i offline-bundles/out/spt-bundle-$TAG.tar
make verify-offline REGISTRY=$REGISTRY TAG=$TAG
```

Optionally run the functional smoke from the loaded images:

```bash
make functional-smoke REGISTRY=$REGISTRY TAG=$TAG DATA_DIR=$DATA_DIR
```

## 7. Publish Release Assets

Create or update the GitHub Release:

```bash
gh release create v$TAG \
  offline-bundles/out/spt-bundle-$TAG.tar.part-* \
  offline-bundles/out/spt-bundle-$TAG.parts.sha256 \
  offline-bundles/out/spt-bundle-$TAG.tar.sha256 \
  offline-bundles/out/spt-bundle-$TAG.manifest.json \
  data-bundles/out/spt-data-bundle-$TAG.tar \
  data-bundles/out/spt-data-bundle-$TAG.tar.sha256 \
  --title "SPT offline bundle $TAG" \
  --notes-file RELEASE_NOTES_0.1.1.md
```

Use `gh release upload v$TAG ... --clobber` for replacement uploads.

## 8. Final Sign-Off

Record the following in the release notes or release discussion:

- Image bundle checksum.
- Data bundle checksum.
- Functional smoke result.
- Restore validation result.
- Known limitations from `KNOWN_LIMITATIONS.md`.
- Whether the data bundle is full or sanitized.

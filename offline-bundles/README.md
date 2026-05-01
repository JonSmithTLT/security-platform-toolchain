# Offline Bundles

This directory is the destination for **air-gapped / offline image bundles**
created by `make bundle`. Bundles are built on a connected machine, then loaded
and run on hosts without internet access. No bundle files are committed to git;
they are generated locally and distributed via Nexus, S3, or physical media.

---

## Creating a bundle

```bash
# Build all images first
make build-all REGISTRY=registry.internal/security-platform TAG=1.2.3

# Create a tar archive containing all images
make bundle REGISTRY=registry.internal/security-platform TAG=1.2.3

# Output: offline-bundles/out/spt-bundle-1.2.3.tar.gz
#         offline-bundles/out/spt-bundle-1.2.3.tar.gz.sha256
#         offline-bundles/out/spt-bundle-1.2.3.manifest.json
```

The bundle target builds the images, smoke-tests them with Docker networking
disabled, calls `docker save` for every image, and writes:

| File | Description |
|------|-------------|
| `out/spt-bundle-<TAG>.tar.gz` | Compressed Docker image archive |
| `out/spt-bundle-<TAG>.tar.gz.sha256` | SHA-256 checksum for integrity verification |
| `out/spt-bundle-<TAG>.manifest.json` | `docker image inspect` inventory for the bundled images |

To keep an offline image store for expensive release artifacts, store a
completed bundle in the content-addressed artifact cache:

```bash
make image-bundle-cache-store TAG=1.2.3
```

The command prints the `sha256:<digest>` for the bundle. A later run can
restore the tarball, checksum, manifest, and split parts by digest:

```bash
make image-bundle-cache-restore TAG=1.2.3 IMAGE_BUNDLE_DIGEST=sha256:<digest>
make image-bundle-cache-info IMAGE_BUNDLE_DIGEST=sha256:<digest>
```

Data bundle release artifacts use the matching cache targets:

```bash
make data-bundle-cache-store TAG=1.2.3
make data-bundle-cache-restore TAG=1.2.3 DATA_BUNDLE_DIGEST=sha256:<digest>
```

Derived offline intelligence artifacts can also be cached independently:

```bash
make cve-index-cache-store
make cve-index-cache-restore CVE_INDEX_DIGEST=sha256:<digest>
make release-sboms-cache-store TAG=1.2.3
make release-sboms-cache-restore TAG=1.2.3 RELEASE_SBOMS_DIGEST=sha256:<digest>
```

Inspect and maintain the local cache with:

```bash
make artifact-cache-list
make artifact-cache-size
make artifact-cache-verify
make artifact-cache-prune ARTIFACT_CACHE_PRUNE_DAYS=30 CONFIRM=yes
```

Dataset fetches for GitHub Advisory DB and OSV DB reuse the same cache. Use
`FORCE_FETCH=1` when you intentionally want a fresh upstream download.

For repeatable offline workflows, `scripts/spt-pipeline.py` can validate and
run YAML-defined container steps with `--network none` by default:

```bash
make pipeline-validate PIPELINE_FILE=examples/pipelines/pipeline-smoke.yaml
make pipeline-dry-run PIPELINE_FILE=examples/pipelines/pipeline-smoke.yaml
```

---

## Registry namespace workflow

For very large bundles, keep the tarball out of Git and publish images to one
registry namespace:

```bash
make push-registry \
  REGISTRY=registry.internal/security-platform \
  TARGET_REGISTRY=docker.io/<namespace> \
  TAG=1.2.3
```

Then recreate the single transfer tarball from that namespace on a connected
machine:

```bash
make pull-bundle \
  SOURCE_REGISTRY=docker.io/<namespace> \
  TAG=1.2.3
```

This writes the same bundle tar, checksum, manifest, and image list under
`offline-bundles/out/`.

---

## Restoring a bundle (air-gapped host)

For release-candidate validation, use the restore driver:

```bash
make release-restore \
  REGISTRY=registry.internal/security-platform \
  TAG=1.2.3 \
  BUNDLE_DIR=offline-bundles/out \
  DATA_BUNDLE_DIR=data-bundles/out \
  RUN_FUNCTIONAL=1
```

It verifies split image/data assets, reassembles tarballs when needed, loads
the images, confirms all images start with `--network none`, extracts the data
bundle, runs data-bundle smoke, and optionally runs the full functional smoke.

The manual equivalent is:

```bash
# 1. Verify integrity
sha256sum -c spt-bundle-1.2.3.tar.gz.sha256

# 2. Load all images into the local Docker daemon
make load-bundle TAG=1.2.3

# 3. Confirm images can start without Docker networking
make verify-offline TAG=1.2.3
```

If the image bundle was split into GitHub Release asset parts, reassemble it
first:

```bash
sha256sum -c spt-bundle-1.2.3.parts.sha256
cat spt-bundle-1.2.3.tar.gz.part-* > spt-bundle-1.2.3.tar.gz
sha256sum -c spt-bundle-1.2.3.tar.gz.sha256
docker load -i spt-bundle-1.2.3.tar.gz
make verify-offline TAG=1.2.3
```

For a release-candidate validation pass, also run the functional smoke from the
loaded images with the staged data bundle mounted:

```bash
make functional-smoke \
  REGISTRY=registry.internal/security-platform \
  TAG=1.2.3 \
  DATA_DIR=/opt/spt-data/sources
```

---

## Pushing to an internal registry after restore

```bash
INTERNAL_REGISTRY=registry.internal.example.com:5000

for img in base python-wheelhouse-py311 frontend-node-toolchain python-runtime schema-validator result-normalizers c-cpp-analysis coverage-tools harness-builder fuzzing protocol-fuzzing crash-triage replay-runner sbom osv-scanner secrets image-scanner re-lightweight yara intel-ingest rag-indexer diff-impact dependency-review ghidra-base ghidra-exporter ghidra-mcp eval-runner gitnexus semgrep codeql corpus-tools symbolic; do
    docker tag registry.internal/security-platform/spt-${img}:1.2.3 \
               ${INTERNAL_REGISTRY}/spt-${img}:1.2.3
    docker push ${INTERNAL_REGISTRY}/spt-${img}:1.2.3
done
```

---

## Directory structure

```
offline-bundles/
├── README.md        ← this file
└── out/             ← generated by `make bundle` (git-ignored)
    ├── spt-bundle-<TAG>.tar.gz
    ├── spt-bundle-<TAG>.tar.gz.sha256
    └── spt-bundle-<TAG>.manifest.json
```

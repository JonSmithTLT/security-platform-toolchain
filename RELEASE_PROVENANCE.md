# Release Provenance And Reproducibility

SPT release artifacts should be stable enough to compare, cache, sign, and
audit across connected and air-gapped environments.

## Deterministic Build Metadata

`SOURCE_DATE_EPOCH` is the release timestamp input. By default it is derived
from the current Git commit timestamp, falling back to the current clock only
outside a Git checkout.

The Makefile uses it for:

- `org.opencontainers.image.created`
- tar archive mtimes
- deterministic tar ordering and ownership for data bundles
- gzip header normalization

Expected allowed drift:

- Docker layer digests can still vary when upstream package managers or base
  image tags change.
- Release ledgers and evidence summaries intentionally record execution time.
- Scanner outputs can vary with tool versions and data bundle freshness.

## Signing And Attestation

Image signing uses `cosign` in key-pair mode by default because offline
environments need predictable verification material.

Connected release side:

```bash
make release-sign-images COSIGN_KEY=cosign.key
make release-attest-images COSIGN_KEY=cosign.key
```

Verification side:

```bash
make release-verify-image-signatures COSIGN_KEY=cosign.pub
```

Attestation predicates are written under:

```text
artifacts/release-evidence/<TAG>/provenance/
```

They describe source revision, build metadata, image references, image digests
when available, and bundle manifest checksums. They are evidence, not a
replacement for human release review.

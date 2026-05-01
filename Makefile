# security-platform-toolchain Makefile
# Local overrides (never committed): create Makefile.local with your personal
# REGISTRY, TAG, DATA_DIR, NATIVE_WORKTREE, etc.
-include Makefile.local

REGISTRY   ?= registry.internal/security-platform
TAG        ?= latest
BASE_IMAGE ?= $(REGISTRY)/spt-base:$(TAG)
IMAGES     := base python-wheelhouse-py311 frontend-node-toolchain python-runtime schema-validator result-normalizers c-cpp-analysis coverage-tools harness-builder fuzzing protocol-fuzzing crash-triage replay-runner sbom osv-scanner secrets image-scanner re-lightweight yara intel-ingest rag-indexer diff-impact dependency-review ghidra-base ghidra-exporter ghidra-mcp eval-runner gitnexus semgrep codeql corpus-tools symbolic
TARGET_REGISTRY ?= $(REGISTRY)
SOURCE_REGISTRY ?= $(REGISTRY)
GHIDRA_VERSION ?= 12.0.4
GHIDRA_DATE    ?= 20260303
GHIDRA_MCP_REPO ?= https://github.com/bethington/ghidra-mcp.git
GHIDRA_MCP_REF  ?= v5.5.0
HONGGFUZZ_REPO ?= https://github.com/google/honggfuzz.git
HONGGFUZZ_REF  ?= master
INCLUDE_GITHUB_ADVISORY_DB ?= 0
NVD_INCREMENTAL     ?= 0
GIT_REVISION ?= $(shell git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct 2>/dev/null || date +%s)
BUILD_CREATED ?= $(shell date -u -d "@$(SOURCE_DATE_EPOCH)" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')
SPT_SCHEMA_VERSION ?= 1.0.0
OCI_SOURCE ?= https://github.com/JonSmithTLT/security-platform-toolchain
OCI_LICENSE ?= MIT
OCI_LABEL_ARGS = \
    --label org.opencontainers.image.source="$(OCI_SOURCE)" \
    --label org.opencontainers.image.revision="$(GIT_REVISION)" \
    --label org.opencontainers.image.version="$(TAG)" \
    --label org.opencontainers.image.created="$(BUILD_CREATED)" \
    --label org.opencontainers.image.licenses="$(OCI_LICENSE)" \
    --label org.security-platform-toolchain.schema-version="$(SPT_SCHEMA_VERSION)"
COMMA := ,
REGISTRY_CACHE ?= 0
REGISTRY_CACHE_REF_PREFIX ?= $(REGISTRY)/spt-build-cache
DOCKER_CACHE_ARGS = $(if $(filter 1,$(REGISTRY_CACHE)),--cache-from type=registry$(COMMA)ref=$(REGISTRY_CACHE_REF_PREFIX)-$@:$(TAG) --cache-to type=registry$(COMMA)ref=$(REGISTRY_CACHE_REF_PREFIX)-$@:$(TAG)$(COMMA)mode=max,)
DOCKER_BUILD = $(if $(filter 1,$(REGISTRY_CACHE)),docker buildx build --load $(OCI_LABEL_ARGS) $(DOCKER_CACHE_ARGS),docker build $(OCI_LABEL_ARGS))

## ── Bundle paths ────────────────────────────────────────────────────────────
BUNDLE_DIR          ?= offline-bundles/out
RESTORE_DIR         ?= artifacts/release-restore/$(TAG)
RESTORED_DATA_DIR   ?= $(RESTORE_DIR)/spt-data
SKIP_DOCKER_LOAD    ?= 0
SKIP_VERIFY_OFFLINE ?= 0
SKIP_DATA_EXTRACT   ?= 0
SKIP_DOCTOR         ?= 0
SKIP_FETCH          ?= 0
SKIP_BUILD          ?= 0
SKIP_FUNCTIONAL     ?= 0
SKIP_BUNDLE         ?= 0
SKIP_HONGGFUZZ      ?= 1
RESUME_FROM         ?=
RUN_FUNCTIONAL      ?= 0
COMPREHENSIVE_RUN_FUNCTIONAL ?= 1
RUN_WHEELHOUSE_SMOKE ?= 1
RUN_FRONTEND_NPM_SMOKE ?= 1
RUN_RESTORE         ?= 0
BUNDLE_TAR          = $(BUNDLE_DIR)/spt-bundle-$(TAG).tar.gz
BUNDLE_MANIFEST     = $(BUNDLE_DIR)/spt-bundle-$(TAG).manifest.json
IMAGE_BUNDLE_DIGEST ?=
DATA_BUNDLE_DIGEST  ?=
SPT_ARTIFACT_CACHE  ?= $(HOME)/.spt-artifact-cache
ARTIFACT_CACHE_PRUNE_DAYS ?= 30
GPG_KEY             ?=
RELEASE_SUMMARY_OUT ?= artifacts/release-summary/$(TAG)/release-summary.md
DATA_DIR            ?= data-bundles/sources
DATA_BUNDLE_DIR     ?= data-bundles/out
DATA_BUNDLE_NAME    ?= spt-data-bundle
DATA_BUNDLE_TAR     = $(DATA_BUNDLE_DIR)/$(DATA_BUNDLE_NAME)-$(TAG).tar.gz
DATA_SANITIZED_BUNDLE_NAME ?= spt-data-sanitized-bundle
DATA_SANITIZED_STAGE ?= $(DATA_BUNDLE_DIR)/sanitized-$(TAG)
DATA_SANITIZED_DIR   ?= $(DATA_SANITIZED_STAGE)/sources
DATA_SANITIZED_TAR   = $(DATA_BUNDLE_DIR)/$(DATA_SANITIZED_BUNDLE_NAME)-$(TAG).tar.gz
DATA_DELTA_TAR      = $(DATA_BUNDLE_DIR)/spt-data-delta-$(TAG).tar.gz
DATA_TAR_PARENT     = $(dir $(abspath $(DATA_DIR)))
DATA_TAR_NAME       = $(notdir $(abspath $(DATA_DIR)))
BASE_DATA_SOURCE_SUMS ?=
DATA_MANIFEST_CHECKSUM_MODE ?= dataset
RELEASE_LEDGER      ?= artifacts/release-ledger/$(TAG)/release-stages.jsonl
SPLIT_SIZE          ?= 1900M
MIN_FREE_GB         ?= 30
ALLOW_SLOW_WORKTREE ?= 0
NATIVE_WORKTREE     ?= $(HOME)/spt-native-worktree
ALLOW_NATIVE_DELETE ?= 0
GZIP_CMD               := $(shell command -v pigz 2>/dev/null || echo gzip)
GZIP_ARGS              ?= -n
TAR_REPRO_ARGS         ?= --sort=name --mtime=@$(SOURCE_DATE_EPOCH) --owner=0 --group=0 --numeric-owner
PYTHON_RUNTIME_IMAGE   ?= $(REGISTRY)/spt-python-runtime:$(TAG)
WHEELHOUSE_IMAGE       ?= $(REGISTRY)/spt-python-wheelhouse-py311:$(TAG)
FRONTEND_NODE_IMAGE    ?= $(REGISTRY)/spt-frontend-node-toolchain:$(TAG)
RESET_NATIVE_WORKTREE ?= 0
BUILD_JOBS          ?= $(shell nproc 2>/dev/null || echo 4)
MAX_IMAGE_MIB       ?= 4096
ALLOW_FAILED_EVIDENCE ?= 0
CVE_INDEX_OUT       ?= data-bundles/out/spt-cve-index.sqlite
CVE_INDEX_DIGEST    ?=
CVE_INDEX_LIMIT     ?=
CVE_INDEX_SMOKE_OUT ?= artifacts/cve-index-smoke
CVE_API_HOST        ?= 127.0.0.1
CVE_API_PORT        ?= 8088
RELEASE_SBOMS_DIGEST ?=
COSIGN_KEY          ?=
REQUIRE_IMAGE_SIGNATURES ?= 0
TOOL_CATALOG_OUT ?= artifacts/tool-catalog
PIPELINE_FILE ?= examples/pipelines/pipeline-smoke.yaml
PIPELINE_PLAYBOOKS := examples/pipelines/dependency-triage.yaml examples/pipelines/fuzz-crash-replay.yaml examples/pipelines/protocol-fuzzing.yaml examples/pipelines/re-export-rag.yaml examples/pipelines/release-evidence-review.yaml
PLATFORM_HANDOFF_DIR ?= artifacts/platform-handoff
PLATFORM_HANDOFF_TAR ?= $(PLATFORM_HANDOFF_DIR)/spt-platform-handoff-$(TAG).tar
ALLOW_EGRESS_AUDIT_FINDINGS ?= 0

.PHONY: all build-all build-report registry-cache-build help \
    doctor native-worktree native-release-smoke \
    lint test test-normalizers test-offline verify-offline \
	functional-smoke smoke-honggfuzz data-bundle-smoke gitnexus-ladybug-smoke gitnexus-git-smoke offline-egress-audit \
    release-smoke release-restore comprehensive-smoke release-upload release-summary release-tui release-ledger-summary release-evidence release-provenance release-sign-images release-verify-image-signatures release-attest-images release-sboms-cache-store release-sboms-cache-restore release-sboms-cache-info release-policy-check scan-platform container-structure-test \
    python-runtime \
    python-wheelhouse-fetch python-wheelhouse-image python-wheelhouse-smoke python-wheelhouse-verify python-wheelhouse-plan \
    frontend-npm-fetch frontend-node-toolchain frontend-npm-smoke frontend-npm-verify frontend-stack-plan \
	data-fetch data-fetch-quick data-fetch-full data-bundle data-bundle-sanitized data-bundle-sign data-bundle-verify-signature data-delta-bundle data-verify data-check-freshness data-bundle-cache-store data-bundle-cache-restore data-bundle-cache-info \
	cve-index-smoke cve-api \
	tool-catalog \
	candidate-correlations \
	vulnerability-enrichments \
	pipeline-validate pipeline-dry-run pipeline-run-sample pipeline-smoke pipeline-playbooks-validate \
	platform-handoff-bundle \
    bundle bundle-save load-bundle image-list pull-bundle image-bundle-cache-store image-bundle-cache-restore image-bundle-cache-info push push-registry \
    image-sizes tool-versions-declared tool-versions-installed tool-drift-check backlog-status license-inventory cve-index cve-index-cache-store cve-index-cache-restore cve-index-cache-info \
    artifact-cache-list artifact-cache-size artifact-cache-verify artifact-cache-prune \
    clean clean-bundles clean-artifacts clean-data-sources clean-all-generated \
    $(IMAGES)

all: build-all

## ── Help ────────────────────────────────────────────────────────────────────

help: ## Show available targets and key variables
	@printf "\nSecurity Platform Toolchain\n"
	@printf "Usage: make [target] [REGISTRY=...] [TAG=...] [DATA_DIR=...]\n\n"
	@printf "Current values: REGISTRY=$(REGISTRY)  TAG=$(TAG)  DATA_DIR=$(DATA_DIR)\n\n"
	@grep -hE '^[a-zA-Z][a-zA-Z0-9_/-]*:.*?## .*$$' $(MAKEFILE_LIST) \
	    | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-35s\033[0m %s\n", $$1, $$2}' \
	    | sort
	@printf "\n"

doctor: ## Run release/build preflight checks
	@BUNDLE_DIR="$(BUNDLE_DIR)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" DATA_DIR="$(DATA_DIR)" MIN_FREE_GB="$(MIN_FREE_GB)" ALLOW_SLOW_WORKTREE="$(ALLOW_SLOW_WORKTREE)" bash scripts/doctor.sh

native-worktree: ## Sync repo to native WSL/Linux storage for faster release builds
	@NATIVE_WORKTREE="$(NATIVE_WORKTREE)" ALLOW_NATIVE_DELETE="$(ALLOW_NATIVE_DELETE)" RESET_NATIVE_WORKTREE="$(RESET_NATIVE_WORKTREE)" bash scripts/prepare-native-worktree.sh

native-release-smoke: native-worktree ## Sync to native WSL/Linux storage, then run release-smoke there
	@cd "$(NATIVE_WORKTREE)" && $(MAKE) release-smoke REGISTRY="$(REGISTRY)" TAG="$(TAG)" DATA_DIR="$(abspath $(DATA_DIR))" BUILD_JOBS="$(BUILD_JOBS)" RESUME_FROM="$(RESUME_FROM)" INCLUDE_GITHUB_ADVISORY_DB="$(INCLUDE_GITHUB_ADVISORY_DB)"

## ── Build ───────────────────────────────────────────────────────────────────

build-all: $(IMAGES) ## Build all images (parallel: make -j 4 build-all)

build-report: ## Build images serially and write per-image timing/size metrics
	@REGISTRY="$(REGISTRY)" TAG="$(TAG)" IMAGES="$(IMAGES)" bash scripts/build-with-metrics.sh

registry-cache-build: ## Build all images with BuildKit registry cache export/import
	@$(MAKE) build-all REGISTRY_CACHE=1

base: ## Build spt-base
	$(DOCKER_BUILD) -t $(REGISTRY)/spt-base:$(TAG) -f images/base/Dockerfile .

schema-validator: python-runtime ## Build spt-schema-validator
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(PYTHON_RUNTIME_IMAGE) -t $(REGISTRY)/spt-schema-validator:$(TAG) -f images/schema-validator/Dockerfile .

result-normalizers: python-runtime ## Build spt-result-normalizers
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(PYTHON_RUNTIME_IMAGE) -t $(REGISTRY)/spt-result-normalizers:$(TAG) -f images/result-normalizers/Dockerfile .

c-cpp-analysis: base ## Build spt-c-cpp-analysis
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-c-cpp-analysis:$(TAG) -f images/c-cpp-analysis/Dockerfile .

coverage-tools: base ## Build spt-coverage-tools
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-coverage-tools:$(TAG) -f images/coverage-tools/Dockerfile .

fuzzing: base ## Build spt-fuzzing (AFL++, libFuzzer, honggfuzz)
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) --build-arg HONGGFUZZ_REPO=$(HONGGFUZZ_REPO) --build-arg HONGGFUZZ_REF=$(HONGGFUZZ_REF) -t $(REGISTRY)/spt-fuzzing:$(TAG) -f images/fuzzing/Dockerfile .

harness-builder: base ## Build spt-harness-builder
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-harness-builder:$(TAG) -f images/harness-builder/Dockerfile .

protocol-fuzzing: base ## Build spt-protocol-fuzzing
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-protocol-fuzzing:$(TAG) -f images/protocol-fuzzing/Dockerfile .

crash-triage: base ## Build spt-crash-triage
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-crash-triage:$(TAG) -f images/crash-triage/Dockerfile .

replay-runner: base ## Build spt-replay-runner
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-replay-runner:$(TAG) -f images/replay-runner/Dockerfile .

sbom: base ## Build spt-sbom (Syft CycloneDX)
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-sbom:$(TAG) -f images/sbom/Dockerfile .

osv-scanner: base ## Build spt-osv-scanner
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-osv-scanner:$(TAG) -f images/osv-scanner/Dockerfile .

secrets: base ## Build spt-secrets (Gitleaks, TruffleHog)
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-secrets:$(TAG) -f images/secrets/Dockerfile .

image-scanner: base ## Build spt-image-scanner (Grype)
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-image-scanner:$(TAG) -f images/image-scanner/Dockerfile .

re-lightweight: base ## Build spt-re-lightweight
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-re-lightweight:$(TAG) -f images/re-lightweight/Dockerfile .

yara: base ## Build spt-yara
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-yara:$(TAG) -f images/yara/Dockerfile .

intel-ingest: python-runtime ## Build spt-intel-ingest
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(PYTHON_RUNTIME_IMAGE) -t $(REGISTRY)/spt-intel-ingest:$(TAG) -f images/intel-ingest/Dockerfile .

rag-indexer: python-runtime ## Build spt-rag-indexer
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(PYTHON_RUNTIME_IMAGE) -t $(REGISTRY)/spt-rag-indexer:$(TAG) -f images/rag-indexer/Dockerfile .

diff-impact: python-runtime ## Build spt-diff-impact
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(PYTHON_RUNTIME_IMAGE) -t $(REGISTRY)/spt-diff-impact:$(TAG) -f images/diff-impact/Dockerfile .

dependency-review: base ## Build spt-dependency-review
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-dependency-review:$(TAG) -f images/dependency-review/Dockerfile .

ghidra-base: base ## Build spt-ghidra-base
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) --build-arg GHIDRA_VERSION=$(GHIDRA_VERSION) --build-arg GHIDRA_DATE=$(GHIDRA_DATE) -t $(REGISTRY)/spt-ghidra-base:$(TAG) -f images/ghidra-base/Dockerfile .

ghidra-exporter: ghidra-base ## Build spt-ghidra-exporter
	$(DOCKER_BUILD) --build-arg GHIDRA_BASE_IMAGE=$(REGISTRY)/spt-ghidra-base:$(TAG) -t $(REGISTRY)/spt-ghidra-exporter:$(TAG) -f images/ghidra-exporter/Dockerfile .

ghidra-mcp: ghidra-base ## Build spt-ghidra-mcp
	$(DOCKER_BUILD) --build-arg GHIDRA_BASE_IMAGE=$(REGISTRY)/spt-ghidra-base:$(TAG) --build-arg GHIDRA_VERSION=$(GHIDRA_VERSION) --build-arg GHIDRA_MCP_REPO=$(GHIDRA_MCP_REPO) --build-arg GHIDRA_MCP_REF=$(GHIDRA_MCP_REF) -t $(REGISTRY)/spt-ghidra-mcp:$(TAG) -f images/ghidra-mcp/Dockerfile .

eval-runner: python-runtime ## Build spt-eval-runner
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(PYTHON_RUNTIME_IMAGE) -t $(REGISTRY)/spt-eval-runner:$(TAG) -f images/eval-runner/Dockerfile .

gitnexus: base ## Build spt-gitnexus (offline LadybugDB patch applied at build time)
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-gitnexus:$(TAG) -f images/gitnexus/Dockerfile .

semgrep: base ## Build spt-semgrep
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-semgrep:$(TAG) -f images/semgrep/Dockerfile .

codeql: base ## Build spt-codeql
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-codeql:$(TAG) -f images/codeql/Dockerfile .

corpus-tools: base ## Build spt-corpus-tools
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-corpus-tools:$(TAG) -f images/corpus-tools/Dockerfile .

symbolic: python-runtime ## Build spt-symbolic
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(PYTHON_RUNTIME_IMAGE) -t $(REGISTRY)/spt-symbolic:$(TAG) -f images/symbolic/Dockerfile .

## ── Lint ────────────────────────────────────────────────────────────────────

lint: ## Lint Dockerfiles (hadolint), shell scripts (shellcheck), schemas, and Semgrep rules
	@echo "==> Linting Dockerfiles with hadolint"
	@for img in $(IMAGES); do \
	    echo "  -> images/$$img/Dockerfile"; \
	    hadolint images/$$img/Dockerfile || exit 1; \
	done
	@echo "==> Linting shell scripts with shellcheck"
	@find common/ -name '*.sh' -exec shellcheck {} +
	@echo "==> Validating JSON schemas"
	@find schemas/ -name '*.json' -exec python3 -c \
	    "import json,sys; json.load(open(sys.argv[1])); print('OK', sys.argv[1])" {} \;
	@echo "==> Linting Semgrep rules"
	@semgrep --validate --config rules/semgrep/
	@echo "Lint passed."

## ── Test ────────────────────────────────────────────────────────────────────

test: ## Smoke-test all images and run unit tests
	@echo "==> Smoke-testing images"
	@for img in $(IMAGES); do \
	    name="spt-$$img"; \
	    echo "  -> $(REGISTRY)/$$name:$(TAG)"; \
	    docker run --rm $(REGISTRY)/$$name:$(TAG) /bin/true || exit 1; \
	done
	@echo "==> Running emit-job-report.py unit tests"
	@python3 -m pytest common/ -v
	@echo "Tests passed."

test-normalizers: ## Run golden fixture contract tests for result normalizers
	@python3 scripts/test-normalizer-fixtures.py

test-offline verify-offline: ## Smoke-test all images with --network none
	@echo "==> Smoke-testing images with Docker network disabled"
	@for img in $(IMAGES); do \
	    name="spt-$$img"; \
	    echo "  -> $(REGISTRY)/$$name:$(TAG) (--network none)"; \
	    docker run --rm --network none $(REGISTRY)/$$name:$(TAG) /bin/true || exit 1; \
	done
	@echo "Offline smoke test passed."

functional-smoke: ## Run full functional smoke test suite against all images
	@bash examples/functional-smoke/run-functional-smoke.sh "$(REGISTRY)" "$(TAG)" "$(DATA_DIR)"

offline-egress-audit: ## Audit offline smoke logs for observable outbound network attempts
	@python3 scripts/offline-egress-audit.py \
	    --registry "$(REGISTRY)" \
	    --tag "$(TAG)" \
	    --data-dir "$(DATA_DIR)" \
	    --logs-root "artifacts/functional-smoke" \
	    --out-dir "artifacts/offline-egress-audit/$(TAG)" \
	    --run-functional-smoke \
	    $(if $(filter 1,$(ALLOW_EGRESS_AUDIT_FINDINGS)),--allow-findings,)

gitnexus-ladybug-smoke: ## Prove offline LadybugDB extension loading under --network none
	@bash examples/gitnexus-ladybug-smoke/run-gitnexus-ladybug-smoke.sh "$(REGISTRY)" "$(TAG)" "$(DATA_DIR)"

gitnexus-git-smoke: ## Prove real git repo indexing with LadybugDB extensions offline
	@bash examples/gitnexus-git-smoke/run-gitnexus-git-smoke.sh "$(REGISTRY)" "$(TAG)" "$(DATA_DIR)"

smoke-honggfuzz: ## Run experimental honggfuzz smoke (non-gating)
	@mkdir -p artifacts/honggfuzz-smoke && chmod 777 artifacts/honggfuzz-smoke
	@echo "==> Experimental honggfuzz smoke (non-gating)"
	@docker run --rm --network none \
	    -e JOB_ID=experimental-honggfuzz \
	    -e ARTIFACTS_DIR=/artifacts \
	    -e FUZZ_ENGINE=honggfuzz \
	    -e FUZZ_TARGET=/bin/true \
	    -v "$$(pwd)/artifacts/honggfuzz-smoke:/artifacts" \
	    $(REGISTRY)/spt-fuzzing:$(TAG) || echo "honggfuzz experimental smoke skipped/failed"

data-bundle-smoke: ## Verify data bundle integrity
	@bash scripts/data-bundle-smoke.sh "$(DATA_DIR)"

## ── Python Wheelhouse (CPython 3.11 / linux_x86_64) ────────────────────────

python-runtime: base python-wheelhouse-image ## Build spt-python-runtime
	$(DOCKER_BUILD) \
	    --build-arg BASE_IMAGE=$(BASE_IMAGE) \
	    --build-arg WHEELHOUSE_IMAGE=$(WHEELHOUSE_IMAGE) \
	    -t $(PYTHON_RUNTIME_IMAGE) \
	    -f images/python-runtime/Dockerfile .

python-wheelhouse-fetch: ## Compile lock files and download CPython 3.11 wheels (requires internet + Docker)
	@bash data-bundles/fetch/fetch-python-wheels.sh "$(DATA_DIR)"

python-wheelhouse-image: ## Build the spt-python-wheelhouse-py311 data carrier image
	@test -d "$(DATA_DIR)/python-wheels/py311" && test -f "$(DATA_DIR)/python-wheels/py311/locks/core-python.lock" || \
	    { printf '==> Wheelhouse data not found under %s/python-wheels/py311; fetching/restoring it now\n' "$(DATA_DIR)" >&2; \
	      $(MAKE) python-wheelhouse-fetch DATA_DIR="$(DATA_DIR)"; }
	@test -f "$(DATA_DIR)/python-wheels/py311/locks/core-python.lock" || \
	    { printf 'ERROR: wheelhouse locks are missing after fetch: %s/python-wheels/py311/locks/core-python.lock\n' "$(DATA_DIR)" >&2; \
	      printf 'Run: FORCE_FETCH=1 make python-wheelhouse-fetch DATA_DIR=%s\n' "$(DATA_DIR)" >&2; exit 2; }
	@if [ "$(abspath $(DATA_DIR))" != "$(abspath data-bundles/sources)" ]; then \
	    printf '==> Staging wheelhouse from %s into Docker build context\n' "$(DATA_DIR)"; \
	    mkdir -p data-bundles/sources/python-wheels; \
	    rm -rf data-bundles/sources/python-wheels/py311; \
	    cp -a "$(DATA_DIR)/python-wheels/py311" data-bundles/sources/python-wheels/; \
	fi
	$(DOCKER_BUILD) \
	    -t $(REGISTRY)/spt-python-wheelhouse-py311:$(TAG) \
	    -f images/python-wheelhouse-py311/Dockerfile .

python-wheelhouse-py311: python-wheelhouse-image ## Alias target for IMAGES/bundle inclusion

python-wheelhouse-smoke: ## Offline install and import smoke for all wheel groups
	@bash examples/python-wheelhouse-smoke/run-python-wheelhouse-smoke.sh "$(REGISTRY)" "$(TAG)"

python-wheelhouse-verify: ## Verify SHA256SUMS of fetched wheels
	@docker run --rm --network none \
	    -v "$(abspath $(DATA_DIR))/python-wheels/py311:/wheels:ro" \
	    busybox \
	    sh -c "cd /wheels && sha256sum -c -s SHA256SUMS && echo 'SHA256SUMS OK'"

python-wheelhouse-plan: ## Show the CPython 3.11 team wheelhouse refresh plan path
	@printf 'docs/python-311-wheelhouse-refresh.md\n'

## ── Frontend Node Toolchain (Node 22 / npm cache) ───────────────────────────

frontend-npm-fetch: ## Resolve frontend package-lock and populate offline npm cache
	@bash data-bundles/fetch/fetch-frontend-npm-cache.sh "$(DATA_DIR)"

frontend-node-toolchain: ## Build spt-frontend-node-toolchain carrier/toolchain image
	@test -d "$(DATA_DIR)/frontend-npm/node22/npm-cache" && test -f "$(DATA_DIR)/frontend-npm/node22/package/package-lock.json" || \
	    { printf '==> Frontend npm cache not found under %s/frontend-npm/node22; fetching it now\n' "$(DATA_DIR)" >&2; \
	      $(MAKE) frontend-npm-fetch DATA_DIR="$(DATA_DIR)"; }
	@test -f "$(DATA_DIR)/frontend-npm/node22/frontend-npm-manifest.json" || \
	    { printf 'ERROR: frontend npm manifest is missing: %s/frontend-npm/node22/frontend-npm-manifest.json\n' "$(DATA_DIR)" >&2; \
	      printf 'Run: FORCE_FETCH=1 make frontend-npm-fetch DATA_DIR=%s\n' "$(DATA_DIR)" >&2; exit 2; }
	@if [ "$(abspath $(DATA_DIR))" != "$(abspath data-bundles/sources)" ]; then \
	    printf '==> Staging frontend npm cache from %s into Docker build context\n' "$(DATA_DIR)"; \
	    mkdir -p data-bundles/sources/frontend-npm; \
	    rm -rf data-bundles/sources/frontend-npm/node22; \
	    cp -a "$(DATA_DIR)/frontend-npm/node22" data-bundles/sources/frontend-npm/; \
	fi
	$(DOCKER_BUILD) \
	    -t $(FRONTEND_NODE_IMAGE) \
	    -f images/frontend-node-toolchain/Dockerfile .

frontend-npm-smoke: ## Offline npm install/import smoke for frontend dependency cache
	@bash examples/frontend-npm-smoke/run-frontend-npm-smoke.sh "$(REGISTRY)" "$(TAG)"

frontend-npm-verify: ## Verify SHA256SUMS of fetched frontend npm cache
	@docker run --rm --network none \
	    -v "$(abspath $(DATA_DIR))/frontend-npm/node22:/frontend-npm:ro" \
	    busybox \
	    sh -c "cd /frontend-npm && sha256sum -c -s SHA256SUMS && echo 'frontend npm SHA256SUMS OK'"

frontend-stack-plan: ## Show the frontend stack/toolchain docs
	@printf 'docs/frontend-node-toolchain.md\n'

## ── Inspection ──────────────────────────────────────────────────────────────

image-sizes: ## Print a markdown table of virtual image sizes for all built images
	@printf "| %-42s | %s |\n" "Image" "Size"
	@printf "|%-44s|%s|\n" "$(shell printf -- '-%.0s' {1..43})" "------"
	@for img in $(IMAGES); do \
	    name="$(REGISTRY)/spt-$$img:$(TAG)"; \
	    size=$$(docker images --format "{{.Size}}" "$$name" 2>/dev/null); \
	    [ -n "$$size" ] || size="(not built)"; \
	    printf "| %-42s | %s |\n" "spt-$$img:$(TAG)" "$$size"; \
	done

tool-versions-declared: ## Print declared tool versions from Dockerfile ARGs and pinned variables
	@printf "\nDeclared tool versions (from Dockerfile ARGs — not verified against installed binaries):\n\n"
	@printf "| %-28s | %-35s | %s |\n" "Image" "Variable" "Declared Value"
	@printf "|%-30s|%-37s|%s|\n" "------------------------------" "-------------------------------------" "---"
	@for img in $(IMAGES); do \
	    df="images/$$img/Dockerfile"; \
	    [ -f "$$df" ] || continue; \
	    while IFS= read -r line; do \
	        case "$$line" in \
	            ARG\ *VERSION*=*|ARG\ *_REF*=*|ARG\ *_COMMIT*=*|ARG\ *_TAG*=*) \
	                key=$$(printf '%s' "$$line" | sed 's/ARG //; s/=.*//'); \
	                val=$$(printf '%s' "$$line" | sed 's/[^=]*=//'); \
	                [ -n "$$val" ] && printf "| %-28s | %-35s | %s |\n" "$$img" "$$key" "$$val"; \
	                ;; \
	        esac; \
	    done < "$$df"; \
	done
	@printf "\nRun 'make tool-versions-installed' once images are built for authoritative version probes.\n\n"

tool-versions-installed: ## Probe installed tool versions from built images
	@REGISTRY="$(REGISTRY)" TAG="$(TAG)" bash scripts/tool-version-inventory.sh installed

tool-drift-check: ## Fail if installed tool probes fail or declared versions drift
	@REGISTRY="$(REGISTRY)" TAG="$(TAG)" bash scripts/tool-version-inventory.sh drift-check

backlog-status: ## Compare FUTURE_WORK Tier 1 checkboxes with repo evidence
	@python3 scripts/backlog-status.py

artifact-cache-list: ## List content-addressed artifact cache entries
	@python3 scripts/artifact-cache-admin.py --cache-root "$(SPT_ARTIFACT_CACHE)" list

artifact-cache-size: ## Show content-addressed artifact cache size by type
	@python3 scripts/artifact-cache-admin.py --cache-root "$(SPT_ARTIFACT_CACHE)" size

artifact-cache-verify: ## Verify all content-addressed artifact cache checksums
	@python3 scripts/artifact-cache-admin.py --cache-root "$(SPT_ARTIFACT_CACHE)" verify

artifact-cache-prune: ## DESTRUCTIVE: prune old cache entries; set CONFIRM=yes
	@python3 scripts/artifact-cache-admin.py --cache-root "$(SPT_ARTIFACT_CACHE)" prune --older-than-days "$(ARTIFACT_CACHE_PRUNE_DAYS)" --confirm "$(CONFIRM)"

license-inventory: ## Generate lightweight tool, wheel, and dataset license inventory
	@python3 scripts/license-inventory.py --data-dir "$(DATA_DIR)" --out-dir "artifacts/license-inventory"

container-structure-test: ## Validate built image structure via docker inspect
	@python3 scripts/container-structure-test.py \
	    --registry "$(REGISTRY)" \
	    --tag "$(TAG)" \
	    --images "$(IMAGES)" \
	    --out-dir "artifacts/container-structure"

cve-index: ## Build offline CVE cross-reference SQLite index
	@python3 scripts/build-cve-index.py --data-dir "$(DATA_DIR)" --out "$(CVE_INDEX_OUT)" $(if $(CVE_INDEX_LIMIT),--max-records-per-source "$(CVE_INDEX_LIMIT)",)
	@sha256sum "$(CVE_INDEX_OUT)" > "$(CVE_INDEX_OUT).sha256"
	@cat "$(CVE_INDEX_OUT).sha256"

cve-index-cache-store: ## Store CVE SQLite index in the content-addressed cache
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" CVE_INDEX_OUT="$(CVE_INDEX_OUT)" bash scripts/cache-cve-index.sh store

cve-index-cache-restore: ## Restore CVE SQLite index from cache (set CVE_INDEX_DIGEST=sha256:...)
	@test -n "$(CVE_INDEX_DIGEST)" || { echo "CVE_INDEX_DIGEST is required"; exit 2; }
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" CVE_INDEX_OUT="$(CVE_INDEX_OUT)" CVE_INDEX_DIGEST="$(CVE_INDEX_DIGEST)" bash scripts/cache-cve-index.sh restore

cve-index-cache-info: ## Show cached CVE index metadata (set CVE_INDEX_DIGEST=sha256:...)
	@test -n "$(CVE_INDEX_DIGEST)" || { echo "CVE_INDEX_DIGEST is required"; exit 2; }
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" CVE_INDEX_OUT="$(CVE_INDEX_OUT)" CVE_INDEX_DIGEST="$(CVE_INDEX_DIGEST)" bash scripts/cache-cve-index.sh info

cve-index-smoke: ## Query fixture lockfile against offline CVE index and emit enrichment candidates
	@python3 scripts/cve-index-smoke.py \
	    --index "$(CVE_INDEX_OUT)" \
	    --fixture "examples/cve-index-smoke/requirements.txt" \
	    --out-dir "$(CVE_INDEX_SMOKE_OUT)"

cve-api: ## Serve the read-only local CVE index API with FastAPI
	@python3 scripts/spt-cve-api.py --index "$(CVE_INDEX_OUT)" --host "$(CVE_API_HOST)" --port "$(CVE_API_PORT)"

tool-catalog: ## Generate MCP/tool catalog from wrappers, image metadata, and examples
	@python3 scripts/generate-tool-catalog.py \
	    --registry "$(REGISTRY)" \
	    --tag "$(TAG)" \
	    --out-dir "$(TOOL_CATALOG_OUT)"

candidate-correlations: ## Generate soft candidate-correlations.json artifacts from normalized findings
	@python3 scripts/generate-candidate-correlations.py --results-dir "artifacts/results" --out-dir "artifacts/results"

vulnerability-enrichments: ## Generate offline CVSS/EPSS/KEV enrichment candidates from tool-result CVEs
	@python3 scripts/generate-vulnerability-enrichments.py --index "$(CVE_INDEX_OUT)" --results-dir "artifacts/results" --out-dir "artifacts/results"

pipeline-validate: ## Validate an SPT pipeline YAML definition
	@python3 scripts/spt-pipeline.py validate "$(PIPELINE_FILE)"

pipeline-dry-run: ## Render an SPT pipeline run without starting containers
	@python3 scripts/spt-pipeline.py dry-run "$(PIPELINE_FILE)"

pipeline-run-sample: ## Run the sample two-step SPT pipeline with Docker
	@python3 scripts/spt-pipeline.py run "examples/pipelines/pipeline-smoke.yaml"

pipeline-smoke: pipeline-validate pipeline-dry-run ## Host smoke for the pipeline parser and report writer

pipeline-playbooks-validate: ## Validate curated offline analyst pipeline playbooks
	@for playbook in $(PIPELINE_PLAYBOOKS); do \
	    python3 scripts/spt-pipeline.py validate "$$playbook" || exit 1; \
	done

## ── Release ─────────────────────────────────────────────────────────────────

release-smoke: ## Run full release smoke (build + verify + bundle)
	@TAG="$(TAG)" REGISTRY="$(REGISTRY)" DATA_DIR="$(DATA_DIR)" BUNDLE_DIR="$(BUNDLE_DIR)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" RELEASE_LEDGER="$(RELEASE_LEDGER)" SPLIT_SIZE="$(SPLIT_SIZE)" MIN_FREE_GB="$(MIN_FREE_GB)" ALLOW_SLOW_WORKTREE="$(ALLOW_SLOW_WORKTREE)" BUILD_JOBS="$(BUILD_JOBS)" RESUME_FROM="$(RESUME_FROM)" SKIP_DOCTOR="$(SKIP_DOCTOR)" SKIP_FETCH="$(SKIP_FETCH)" SKIP_BUILD="$(SKIP_BUILD)" SKIP_FUNCTIONAL="$(SKIP_FUNCTIONAL)" SKIP_BUNDLE="$(SKIP_BUNDLE)" SKIP_HONGGFUZZ="$(SKIP_HONGGFUZZ)" bash scripts/release-smoke-build.sh

release-restore: ## Restore and validate a release bundle
	@TAG="$(TAG)" REGISTRY="$(REGISTRY)" BUNDLE_DIR="$(BUNDLE_DIR)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" RESTORE_DIR="$(RESTORE_DIR)" RESTORED_DATA_DIR="$(RESTORED_DATA_DIR)" SKIP_DOCKER_LOAD="$(SKIP_DOCKER_LOAD)" SKIP_VERIFY_OFFLINE="$(SKIP_VERIFY_OFFLINE)" SKIP_DATA_EXTRACT="$(SKIP_DATA_EXTRACT)" RUN_FUNCTIONAL="$(RUN_FUNCTIONAL)" bash scripts/restore-release-bundle.sh

comprehensive-smoke: ## Run broad post-build/post-release checks and write a compact report
	@TAG="$(TAG)" REGISTRY="$(REGISTRY)" DATA_DIR="$(DATA_DIR)" BUNDLE_DIR="$(BUNDLE_DIR)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" RUN_FUNCTIONAL="$(COMPREHENSIVE_RUN_FUNCTIONAL)" RUN_WHEELHOUSE_SMOKE="$(RUN_WHEELHOUSE_SMOKE)" RUN_FRONTEND_NPM_SMOKE="$(RUN_FRONTEND_NPM_SMOKE)" RUN_RESTORE="$(RUN_RESTORE)" bash scripts/comprehensive-smoke.sh

release-upload: ## Create/update GitHub release and upload assets from manifest
	@TAG="$(TAG)" BUNDLE_DIR="$(BUNDLE_DIR)" bash scripts/release-upload-helper.sh

release-summary: ## Generate compact markdown release evidence summary
	@python3 scripts/generate-release-summary.py \
	    --tag "$(TAG)" \
	    --bundle-dir "$(BUNDLE_DIR)" \
	    --data-bundle-dir "$(DATA_BUNDLE_DIR)" \
	    --release-ledger "$(RELEASE_LEDGER)" \
	    --evidence-dir "artifacts/release-evidence/$(TAG)" \
	    --out "$(RELEASE_SUMMARY_OUT)"

release-tui: ## Open the local release ledger terminal viewer
	@python3 scripts/release-ledger-tui.py --tag "$(TAG)" --ledger "$(RELEASE_LEDGER)" --bundle-dir "$(BUNDLE_DIR)" --data-bundle-dir "$(DATA_BUNDLE_DIR)"

release-ledger-summary: ## Print a noninteractive release ledger summary
	@python3 scripts/release-ledger-tui.py --summary --tag "$(TAG)" --ledger "$(RELEASE_LEDGER)" --bundle-dir "$(BUNDLE_DIR)" --data-bundle-dir "$(DATA_BUNDLE_DIR)"

release-evidence: ## Collect SBOMs, scans, inventories, and manifests for built images
	@REGISTRY="$(REGISTRY)" TAG="$(TAG)" IMAGES="$(IMAGES)" bash scripts/collect-release-evidence.sh

release-provenance: ## Generate SLSA-style provenance predicates for built images
	@python3 scripts/release-provenance.py \
	    --registry "$(REGISTRY)" \
	    --tag "$(TAG)" \
	    --images "$(IMAGES)" \
	    --out-dir "artifacts/release-evidence/$(TAG)/provenance" \
	    --git-revision "$(GIT_REVISION)" \
	    --source-date-epoch "$(SOURCE_DATE_EPOCH)" \
	    --image-manifest "$(BUNDLE_MANIFEST)" \
	    --data-manifest "$(DATA_BUNDLE_DIR)/spt-data-bundle-$(TAG).manifest.json" \
	    --release-ledger "$(RELEASE_LEDGER)"

release-sign-images: ## Sign release image references with cosign key-pair mode
	@REGISTRY="$(REGISTRY)" TAG="$(TAG)" IMAGES="$(IMAGES)" COSIGN_KEY="$(COSIGN_KEY)" bash scripts/cosign-release-images.sh sign

release-verify-image-signatures: ## Verify release image signatures with cosign
	@REGISTRY="$(REGISTRY)" TAG="$(TAG)" IMAGES="$(IMAGES)" COSIGN_KEY="$(COSIGN_KEY)" bash scripts/cosign-release-images.sh verify

release-attest-images: release-provenance ## Attach SLSA-style provenance attestations with cosign
	@REGISTRY="$(REGISTRY)" TAG="$(TAG)" IMAGES="$(IMAGES)" COSIGN_KEY="$(COSIGN_KEY)" bash scripts/cosign-release-images.sh attest

release-sboms-cache-store: ## Store generated release SBOM evidence in the content-addressed cache
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" TAG="$(TAG)" RELEASE_EVIDENCE_DIR="artifacts/release-evidence/$(TAG)" bash scripts/cache-release-sboms.sh store

release-sboms-cache-restore: ## Restore release SBOM evidence from cache (set RELEASE_SBOMS_DIGEST=sha256:...)
	@test -n "$(RELEASE_SBOMS_DIGEST)" || { echo "RELEASE_SBOMS_DIGEST is required"; exit 2; }
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" TAG="$(TAG)" RELEASE_EVIDENCE_DIR="artifacts/release-evidence/$(TAG)" RELEASE_SBOMS_DIGEST="$(RELEASE_SBOMS_DIGEST)" bash scripts/cache-release-sboms.sh restore

release-sboms-cache-info: ## Show cached release SBOM metadata (set RELEASE_SBOMS_DIGEST=sha256:...)
	@test -n "$(RELEASE_SBOMS_DIGEST)" || { echo "RELEASE_SBOMS_DIGEST is required"; exit 2; }
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" TAG="$(TAG)" RELEASE_EVIDENCE_DIR="artifacts/release-evidence/$(TAG)" RELEASE_SBOMS_DIGEST="$(RELEASE_SBOMS_DIGEST)" bash scripts/cache-release-sboms.sh info

release-policy-check: ## Gate release evidence against size and required-artifact policy
	@python3 scripts/release-policy-check.py \
	    --evidence-dir "artifacts/release-evidence/$(TAG)" \
	    --registry "$(REGISTRY)" \
	    --tag "$(TAG)" \
	    --images "$(IMAGES)" \
	    --max-image-mib "$(MAX_IMAGE_MIB)" \
	    --require-image-signatures "$(REQUIRE_IMAGE_SIGNATURES)" \
	    $(if $(filter 1,$(ALLOW_FAILED_EVIDENCE)),--allow-failed-evidence,)

platform-handoff-bundle: release-evidence ## Package importer-friendly handoff contract + bundle
	@python3 scripts/build-platform-handoff-bundle.py \
	    --tag "$(TAG)" \
	    --registry "$(REGISTRY)" \
	    --results-dir "artifacts/results" \
	    --release-evidence-dir "artifacts/release-evidence/$(TAG)" \
	    --offline-bundle-dir "$(BUNDLE_DIR)" \
	    --data-bundle-dir "$(DATA_BUNDLE_DIR)" \
	    --out-dir "$(PLATFORM_HANDOFF_DIR)/$(TAG)" \
	    --tar-out "$(PLATFORM_HANDOFF_TAR)"

scan-platform: release-evidence ## Alias for platform self-scanning release evidence

## ── Bundle (offline / air-gap) ──────────────────────────────────────────────

bundle: build-all verify-offline bundle-save ## Build all images, verify offline, and save bundle tar

bundle-save: ## Save all images to a bundle tar + SHA256
	@mkdir -p $(BUNDLE_DIR)
	@echo "==> Saving all images to $(BUNDLE_TAR)"
	@docker save \
	    $(foreach img,$(IMAGES),$(REGISTRY)/spt-$(img):$(TAG)) \
	    | $(GZIP_CMD) $(GZIP_ARGS) > $(BUNDLE_TAR)
	@echo "Bundle written to $(BUNDLE_TAR)"
	@echo "==> Writing image inventory to $(BUNDLE_MANIFEST)"
	@docker image inspect \
	    $(foreach img,$(IMAGES),$(REGISTRY)/spt-$(img):$(TAG)) \
	    > $(BUNDLE_MANIFEST)
	@echo "==> Generating SHA-256 checksum"
	@sha256sum $(BUNDLE_TAR) > $(BUNDLE_TAR).sha256
	@cat $(BUNDLE_TAR).sha256

image-bundle-cache-store: ## Store image bundle artifacts in the content-addressed cache
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" TAG="$(TAG)" BUNDLE_DIR="$(BUNDLE_DIR)" BUNDLE_TAR="$(BUNDLE_TAR)" BUNDLE_MANIFEST="$(BUNDLE_MANIFEST)" bash scripts/cache-image-bundle.sh store

image-bundle-cache-restore: ## Restore image bundle artifacts from cache (set IMAGE_BUNDLE_DIGEST=sha256:...)
	@test -n "$(IMAGE_BUNDLE_DIGEST)" || { echo "IMAGE_BUNDLE_DIGEST is required"; exit 2; }
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" TAG="$(TAG)" BUNDLE_DIR="$(BUNDLE_DIR)" BUNDLE_TAR="$(BUNDLE_TAR)" BUNDLE_MANIFEST="$(BUNDLE_MANIFEST)" IMAGE_BUNDLE_DIGEST="$(IMAGE_BUNDLE_DIGEST)" bash scripts/cache-image-bundle.sh restore

image-bundle-cache-info: ## Show cached image bundle metadata (set IMAGE_BUNDLE_DIGEST=sha256:...)
	@test -n "$(IMAGE_BUNDLE_DIGEST)" || { echo "IMAGE_BUNDLE_DIGEST is required"; exit 2; }
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" TAG="$(TAG)" BUNDLE_DIR="$(BUNDLE_DIR)" BUNDLE_TAR="$(BUNDLE_TAR)" BUNDLE_MANIFEST="$(BUNDLE_MANIFEST)" IMAGE_BUNDLE_DIGEST="$(IMAGE_BUNDLE_DIGEST)" bash scripts/cache-image-bundle.sh info

load-bundle: ## Load images from bundle tar into local Docker
	@echo "==> Loading images from $(BUNDLE_TAR)"
	@docker load -i $(BUNDLE_TAR)

image-list: ## Write image list to file (used by pull-bundle)
	@mkdir -p $(BUNDLE_DIR)
	@for img in $(IMAGES); do \
	    echo "$(SOURCE_REGISTRY)/spt-$$img:$(TAG)"; \
	done > $(BUNDLE_DIR)/spt-images-$(TAG).txt
	@echo "Image list written to $(BUNDLE_DIR)/spt-images-$(TAG).txt"

pull-bundle: image-list ## Pull images from SOURCE_REGISTRY and save as bundle tar
	@mkdir -p $(BUNDLE_DIR)
	@echo "==> Pulling images from $(SOURCE_REGISTRY)"
	@while read -r image; do \
	    echo "  -> $$image"; \
	    docker pull "$$image" || exit 1; \
	done < $(BUNDLE_DIR)/spt-images-$(TAG).txt
	@echo "==> Saving pulled images to $(BUNDLE_TAR)"
	@docker save $$(cat $(BUNDLE_DIR)/spt-images-$(TAG).txt) | $(GZIP_CMD) $(GZIP_ARGS) > $(BUNDLE_TAR)
	@docker image inspect $$(cat $(BUNDLE_DIR)/spt-images-$(TAG).txt) > $(BUNDLE_MANIFEST)
	@sha256sum $(BUNDLE_TAR) > $(BUNDLE_TAR).sha256
	@cat $(BUNDLE_TAR).sha256

## ── Data ────────────────────────────────────────────────────────────────────

data-fetch: ## Fetch standard data sources (set INCLUDE_GITHUB_ADVISORY_DB=1 for full advisory data)
	@INCLUDE_GITHUB_ADVISORY_DB=$(INCLUDE_GITHUB_ADVISORY_DB) NVD_INCREMENTAL=$(NVD_INCREMENTAL) bash data-bundles/fetch/fetch-all.sh "$(DATA_DIR)"

data-fetch-quick: ## Fetch standard data sources, skipping the large GitHub Advisory DB
	@INCLUDE_GITHUB_ADVISORY_DB=0 NVD_INCREMENTAL=$(NVD_INCREMENTAL) bash data-bundles/fetch/fetch-all.sh "$(DATA_DIR)"

data-fetch-full: ## Fetch all data sources, including the large GitHub Advisory DB
	@INCLUDE_GITHUB_ADVISORY_DB=1 NVD_INCREMENTAL=$(NVD_INCREMENTAL) bash data-bundles/fetch/fetch-all.sh "$(DATA_DIR)"

data-bundle: ## Create a data bundle tar from sources
	@mkdir -p $(DATA_BUNDLE_DIR)
	@TAG="$(TAG)" DATA_DIR="$(DATA_DIR)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" DATA_BUNDLE_NAME="$(DATA_BUNDLE_NAME)" DATA_MANIFEST_CHECKSUM_MODE="$(DATA_MANIFEST_CHECKSUM_MODE)" bash scripts/write-data-bundle-manifest.sh
	@echo "==> Creating data bundle $(DATA_BUNDLE_TAR)"
	@tar $(TAR_REPRO_ARGS) --transform 's|^$(DATA_TAR_NAME)|sources|' -c -C "$(DATA_TAR_PARENT)" "$(DATA_TAR_NAME)" | $(GZIP_CMD) $(GZIP_ARGS) > $(DATA_BUNDLE_TAR)
	@sha256sum $(DATA_BUNDLE_TAR) > $(DATA_BUNDLE_TAR).sha256
	@cat $(DATA_BUNDLE_TAR).sha256

data-bundle-cache-store: ## Store data bundle artifacts in the content-addressed cache
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" TAG="$(TAG)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" DATA_BUNDLE_NAME="$(DATA_BUNDLE_NAME)" DATA_BUNDLE_TAR="$(DATA_BUNDLE_TAR)" bash scripts/cache-data-bundle.sh store

data-bundle-cache-restore: ## Restore data bundle artifacts from cache (set DATA_BUNDLE_DIGEST=sha256:...)
	@test -n "$(DATA_BUNDLE_DIGEST)" || { echo "DATA_BUNDLE_DIGEST is required"; exit 2; }
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" TAG="$(TAG)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" DATA_BUNDLE_NAME="$(DATA_BUNDLE_NAME)" DATA_BUNDLE_TAR="$(DATA_BUNDLE_TAR)" DATA_BUNDLE_DIGEST="$(DATA_BUNDLE_DIGEST)" bash scripts/cache-data-bundle.sh restore

data-bundle-cache-info: ## Show cached data bundle metadata (set DATA_BUNDLE_DIGEST=sha256:...)
	@test -n "$(DATA_BUNDLE_DIGEST)" || { echo "DATA_BUNDLE_DIGEST is required"; exit 2; }
	@SPT_ARTIFACT_CACHE="$(SPT_ARTIFACT_CACHE)" TAG="$(TAG)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" DATA_BUNDLE_NAME="$(DATA_BUNDLE_NAME)" DATA_BUNDLE_TAR="$(DATA_BUNDLE_TAR)" DATA_BUNDLE_DIGEST="$(DATA_BUNDLE_DIGEST)" bash scripts/cache-data-bundle.sh info

data-bundle-sanitized: ## Create sanitized advisory/intel data bundle variant
	@mkdir -p $(DATA_BUNDLE_DIR)
	@python3 scripts/create-sanitized-data-view.py \
	    --input-dir "$(DATA_DIR)" \
	    --output-dir "$(DATA_SANITIZED_DIR)" \
	    --report-out "$(DATA_BUNDLE_DIR)/$(DATA_SANITIZED_BUNDLE_NAME)-$(TAG).sanitization-report.json"
	@TAG="$(TAG)" DATA_DIR="$(DATA_SANITIZED_DIR)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" DATA_BUNDLE_NAME="$(DATA_SANITIZED_BUNDLE_NAME)" SANITIZED=true DATA_MANIFEST_CHECKSUM_MODE="$(DATA_MANIFEST_CHECKSUM_MODE)" bash scripts/write-data-bundle-manifest.sh
	@echo "==> Creating sanitized data bundle $(DATA_SANITIZED_TAR)"
	@tar $(TAR_REPRO_ARGS) -c -C $(DATA_SANITIZED_STAGE) sources | $(GZIP_CMD) $(GZIP_ARGS) > $(DATA_SANITIZED_TAR)
	@sha256sum $(DATA_SANITIZED_TAR) > $(DATA_SANITIZED_TAR).sha256
	@cat $(DATA_SANITIZED_TAR).sha256

data-bundle-sign: ## Sign the data bundle manifest with detached GPG signature
	@TAG="$(TAG)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" DATA_BUNDLE_NAME="$(DATA_BUNDLE_NAME)" GPG_KEY="$(GPG_KEY)" bash scripts/sign-data-bundle.sh

data-bundle-verify-signature: ## Verify the data bundle manifest detached GPG signature
	@TAG="$(TAG)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" DATA_BUNDLE_NAME="$(DATA_BUNDLE_NAME)" VERIFY_ONLY=1 bash scripts/sign-data-bundle.sh

data-delta-bundle: ## Create a data delta bundle from prior source checksums
	@test -n "$(BASE_DATA_SOURCE_SUMS)" || { echo "BASE_DATA_SOURCE_SUMS is required"; exit 2; }
	@mkdir -p $(DATA_BUNDLE_DIR)
	@python3 scripts/create-data-delta-bundle.py \
	    --data-dir "$(DATA_DIR)" \
	    --base-source-checksums "$(BASE_DATA_SOURCE_SUMS)" \
	    --out "$(DATA_DELTA_TAR)" \
	    --manifest-out "$(DATA_BUNDLE_DIR)/spt-data-delta-$(TAG).manifest.json" \
	    --tag "$(TAG)"
	@sha256sum $(DATA_DELTA_TAR) > $(DATA_DELTA_TAR).sha256
	@cat $(DATA_DELTA_TAR).sha256

data-verify: ## Verify data bundle checksum
	@echo "==> Verifying data bundle checksum"
	@sha256sum -c $(DATA_BUNDLE_TAR).sha256

data-check-freshness: ## Report fetched dataset age vs expected update cadence
	@python3 scripts/data-check-freshness.py "$(DATA_DIR)" "artifacts/data-freshness"

## ── Push ────────────────────────────────────────────────────────────────────

push: build-all ## Build and push all images to REGISTRY
	@for img in $(IMAGES); do \
	    docker push $(REGISTRY)/spt-$$img:$(TAG); \
	done

push-registry: ## Tag and push all images to TARGET_REGISTRY
	@echo "==> Tagging and pushing images to $(TARGET_REGISTRY)"
	@for img in $(IMAGES); do \
	    src="$(REGISTRY)/spt-$$img:$(TAG)"; \
	    dst="$(TARGET_REGISTRY)/spt-$$img:$(TAG)"; \
	    echo "  -> $$dst"; \
	    docker tag "$$src" "$$dst" || exit 1; \
	    docker push "$$dst" || exit 1; \
	done

## ── Clean ───────────────────────────────────────────────────────────────────

clean: clean-bundles ## Remove bundle output (offline-bundles/out and data-bundles/out)

clean-bundles: ## Remove offline-bundles/out and data-bundles/out
	@bash scripts/clean-paths.sh "$(BUNDLE_DIR)" "$(DATA_BUNDLE_DIR)"

clean-artifacts: ## Remove smoke and restore artifacts (artifacts/)
	@bash scripts/clean-paths.sh artifacts

clean-data-sources: ## DESTRUCTIVE: Remove data-bundles/sources — requires CONFIRM=yes
	@test "$(CONFIRM)" = "yes" || \
	    { printf "ERROR: clean-data-sources deletes all fetched data.\nRun: make clean-data-sources CONFIRM=yes\n" >&2; exit 1; }
	@bash scripts/clean-paths.sh data-bundles/sources

clean-all-generated: ## DESTRUCTIVE: Remove all generated output — requires CONFIRM=yes
	@test "$(CONFIRM)" = "yes" || \
	    { printf "ERROR: clean-all-generated deletes bundles, artifacts, and data sources.\nRun: make clean-all-generated CONFIRM=yes\n" >&2; exit 1; }
	@$(MAKE) clean-bundles
	@$(MAKE) clean-artifacts
	@$(MAKE) clean-data-sources CONFIRM=yes
	@echo "==> All generated output removed."

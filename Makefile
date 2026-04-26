# security-platform-toolchain Makefile

REGISTRY   ?= registry.internal/security-platform
TAG        ?= latest
BASE_IMAGE ?= $(REGISTRY)/spt-base:$(TAG)
IMAGES     := base schema-validator result-normalizers c-cpp-analysis coverage-tools harness-builder fuzzing protocol-fuzzing crash-triage replay-runner sbom osv-scanner secrets image-scanner re-lightweight yara intel-ingest rag-indexer diff-impact ghidra-base ghidra-exporter ghidra-mcp eval-runner gitnexus semgrep codeql corpus-tools symbolic
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
BUILD_CREATED ?= $(shell date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)
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
DOCKER_BUILD = docker build $(OCI_LABEL_ARGS)

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
SKIP_HONGGFUZZ      ?= 0
RESUME_FROM         ?=
RUN_FUNCTIONAL      ?= 0
BUNDLE_TAR          = $(BUNDLE_DIR)/spt-bundle-$(TAG).tar
BUNDLE_MANIFEST     = $(BUNDLE_DIR)/spt-bundle-$(TAG).manifest.json
DATA_DIR            ?= data-bundles/sources
DATA_BUNDLE_DIR     ?= data-bundles/out
DATA_BUNDLE_TAR     = $(DATA_BUNDLE_DIR)/spt-data-bundle-$(TAG).tar
DATA_MANIFEST_CHECKSUM_MODE ?= dataset
RELEASE_LEDGER      ?= artifacts/release-ledger/$(TAG)/release-stages.jsonl
SPLIT_SIZE          ?= 1900M
MIN_FREE_GB         ?= 30
ALLOW_SLOW_WORKTREE ?= 0
NATIVE_WORKTREE     ?= $(HOME)/spt-build/security-platform-toolchain
ALLOW_NATIVE_DELETE ?= 0
RESET_NATIVE_WORKTREE ?= 0
BUILD_JOBS          ?= 4
MAX_IMAGE_MIB       ?= 4096
ALLOW_FAILED_EVIDENCE ?= 0

.PHONY: all build-all build-report help \
    doctor native-worktree native-release-smoke \
    lint test test-offline verify-offline \
    functional-smoke smoke-honggfuzz data-bundle-smoke gitnexus-ladybug-smoke gitnexus-git-smoke \
    release-smoke release-restore release-evidence release-policy-check scan-platform \
    python-wheelhouse-fetch python-wheelhouse-image python-wheelhouse-smoke python-wheelhouse-verify \
    data-fetch data-fetch-quick data-fetch-full data-bundle data-verify data-check-freshness \
    bundle bundle-save load-bundle image-list pull-bundle push push-registry \
    image-sizes tool-versions-declared tool-versions-installed tool-drift-check backlog-status \
    clean clean-bundles clean-artifacts clean-data-sources clean-all-generated \
    $(IMAGES)

all: build-all

## ── Help ────────────────────────────────────────────────────────────────────

help: ## Show available targets and key variables
	@printf "\nSecurity Platform Toolchain\n"
	@printf "Usage: make [target] [REGISTRY=...] [TAG=...] [DATA_DIR=...]\n\n"
	@printf "Current values: REGISTRY=$(REGISTRY)  TAG=$(TAG)  DATA_DIR=$(DATA_DIR)\n\n"
	@grep -E '^[a-zA-Z][a-zA-Z0-9_/-]*:.*?## .*$$' $(MAKEFILE_LIST) \
	    | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-35s\033[0m %s\n", $$1, $$2}' \
	    | sort
	@printf "\n"

doctor: ## Run release/build preflight checks
	@BUNDLE_DIR="$(BUNDLE_DIR)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" DATA_DIR="$(DATA_DIR)" MIN_FREE_GB="$(MIN_FREE_GB)" ALLOW_SLOW_WORKTREE="$(ALLOW_SLOW_WORKTREE)" bash scripts/doctor.sh

native-worktree: ## Sync repo to native WSL/Linux storage for faster release builds
	@NATIVE_WORKTREE="$(NATIVE_WORKTREE)" ALLOW_NATIVE_DELETE="$(ALLOW_NATIVE_DELETE)" RESET_NATIVE_WORKTREE="$(RESET_NATIVE_WORKTREE)" bash scripts/prepare-native-worktree.sh

native-release-smoke: native-worktree ## Sync to native WSL/Linux storage, then run release-smoke there
	@cd "$(NATIVE_WORKTREE)" && $(MAKE) release-smoke REGISTRY="$(REGISTRY)" TAG="$(TAG)" DATA_DIR="$(DATA_DIR)" BUILD_JOBS="$(BUILD_JOBS)" RESUME_FROM="$(RESUME_FROM)" INCLUDE_GITHUB_ADVISORY_DB="$(INCLUDE_GITHUB_ADVISORY_DB)"

## ── Build ───────────────────────────────────────────────────────────────────

build-all: $(IMAGES) ## Build all images (parallel: make -j 4 build-all)

build-report: ## Build images serially and write per-image timing/size metrics
	@REGISTRY="$(REGISTRY)" TAG="$(TAG)" IMAGES="$(IMAGES)" bash scripts/build-with-metrics.sh

base: ## Build spt-base
	$(DOCKER_BUILD) -t $(REGISTRY)/spt-base:$(TAG) -f images/base/Dockerfile .

schema-validator: base ## Build spt-schema-validator
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-schema-validator:$(TAG) -f images/schema-validator/Dockerfile .

result-normalizers: base ## Build spt-result-normalizers
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-result-normalizers:$(TAG) -f images/result-normalizers/Dockerfile .

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

intel-ingest: base ## Build spt-intel-ingest
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-intel-ingest:$(TAG) -f images/intel-ingest/Dockerfile .

rag-indexer: base ## Build spt-rag-indexer
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-rag-indexer:$(TAG) -f images/rag-indexer/Dockerfile .

diff-impact: base ## Build spt-diff-impact
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-diff-impact:$(TAG) -f images/diff-impact/Dockerfile .

ghidra-base: base ## Build spt-ghidra-base
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) --build-arg GHIDRA_VERSION=$(GHIDRA_VERSION) --build-arg GHIDRA_DATE=$(GHIDRA_DATE) -t $(REGISTRY)/spt-ghidra-base:$(TAG) -f images/ghidra-base/Dockerfile .

ghidra-exporter: ghidra-base ## Build spt-ghidra-exporter
	$(DOCKER_BUILD) --build-arg GHIDRA_BASE_IMAGE=$(REGISTRY)/spt-ghidra-base:$(TAG) -t $(REGISTRY)/spt-ghidra-exporter:$(TAG) -f images/ghidra-exporter/Dockerfile .

ghidra-mcp: ghidra-base ## Build spt-ghidra-mcp
	$(DOCKER_BUILD) --build-arg GHIDRA_BASE_IMAGE=$(REGISTRY)/spt-ghidra-base:$(TAG) --build-arg GHIDRA_VERSION=$(GHIDRA_VERSION) --build-arg GHIDRA_MCP_REPO=$(GHIDRA_MCP_REPO) --build-arg GHIDRA_MCP_REF=$(GHIDRA_MCP_REF) -t $(REGISTRY)/spt-ghidra-mcp:$(TAG) -f images/ghidra-mcp/Dockerfile .

eval-runner: base ## Build spt-eval-runner
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-eval-runner:$(TAG) -f images/eval-runner/Dockerfile .

gitnexus: base ## Build spt-gitnexus (offline LadybugDB patch applied at build time)
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-gitnexus:$(TAG) -f images/gitnexus/Dockerfile .

semgrep: base ## Build spt-semgrep
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-semgrep:$(TAG) -f images/semgrep/Dockerfile .

codeql: base ## Build spt-codeql
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-codeql:$(TAG) -f images/codeql/Dockerfile .

corpus-tools: base ## Build spt-corpus-tools
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-corpus-tools:$(TAG) -f images/corpus-tools/Dockerfile .

symbolic: base ## Build spt-symbolic
	$(DOCKER_BUILD) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-symbolic:$(TAG) -f images/symbolic/Dockerfile .

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

gitnexus-ladybug-smoke: ## Prove offline LadybugDB extension loading under --network none
	@bash examples/gitnexus-ladybug-smoke/run-gitnexus-ladybug-smoke.sh "$(REGISTRY)" "$(TAG)" "$(DATA_DIR)"

gitnexus-git-smoke: ## Prove real git repo indexing with LadybugDB extensions offline
	@bash examples/gitnexus-git-smoke/run-gitnexus-git-smoke.sh "$(REGISTRY)" "$(TAG)" "$(DATA_DIR)"

smoke-honggfuzz: ## Run experimental honggfuzz smoke (non-gating)
	@mkdir -p artifacts/honggfuzz-smoke
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

python-wheelhouse-fetch: ## Compile lock files and download CPython 3.11 wheels (requires internet + Docker)
	@bash data-bundles/fetch/fetch-python-wheels.sh "$(DATA_DIR)"

python-wheelhouse-image: ## Build the spt-python-wheelhouse-py311 data carrier image
	$(DOCKER_BUILD) \
	    -t $(REGISTRY)/spt-python-wheelhouse-py311:$(TAG) \
	    -f images/python-wheelhouse-py311/Dockerfile .

python-wheelhouse-smoke: ## Offline install and import smoke for all wheel groups
	@bash examples/python-wheelhouse-smoke/run-python-wheelhouse-smoke.sh "$(REGISTRY)" "$(TAG)"

python-wheelhouse-verify: ## Verify SHA256SUMS of fetched wheels
	@docker run --rm --network none \
	    -v "$(DATA_DIR)/python-wheels/py311:/wheels:ro" \
	    busybox \
	    sh -c "cd /wheels && sha256sum -c SHA256SUMS --quiet && echo 'SHA256SUMS OK'"

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

## ── Release ─────────────────────────────────────────────────────────────────

release-smoke: ## Run full release smoke (build + verify + bundle)
	@TAG="$(TAG)" REGISTRY="$(REGISTRY)" DATA_DIR="$(DATA_DIR)" BUNDLE_DIR="$(BUNDLE_DIR)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" RELEASE_LEDGER="$(RELEASE_LEDGER)" SPLIT_SIZE="$(SPLIT_SIZE)" MIN_FREE_GB="$(MIN_FREE_GB)" ALLOW_SLOW_WORKTREE="$(ALLOW_SLOW_WORKTREE)" BUILD_JOBS="$(BUILD_JOBS)" RESUME_FROM="$(RESUME_FROM)" SKIP_DOCTOR="$(SKIP_DOCTOR)" SKIP_FETCH="$(SKIP_FETCH)" SKIP_BUILD="$(SKIP_BUILD)" SKIP_FUNCTIONAL="$(SKIP_FUNCTIONAL)" SKIP_BUNDLE="$(SKIP_BUNDLE)" SKIP_HONGGFUZZ="$(SKIP_HONGGFUZZ)" bash scripts/release-smoke-build.sh

release-restore: ## Restore and validate a release bundle
	@TAG="$(TAG)" REGISTRY="$(REGISTRY)" BUNDLE_DIR="$(BUNDLE_DIR)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" RESTORE_DIR="$(RESTORE_DIR)" RESTORED_DATA_DIR="$(RESTORED_DATA_DIR)" SKIP_DOCKER_LOAD="$(SKIP_DOCKER_LOAD)" SKIP_VERIFY_OFFLINE="$(SKIP_VERIFY_OFFLINE)" SKIP_DATA_EXTRACT="$(SKIP_DATA_EXTRACT)" RUN_FUNCTIONAL="$(RUN_FUNCTIONAL)" bash scripts/restore-release-bundle.sh

release-evidence: ## Collect SBOMs, scans, inventories, and manifests for built images
	@REGISTRY="$(REGISTRY)" TAG="$(TAG)" IMAGES="$(IMAGES)" bash scripts/collect-release-evidence.sh

release-policy-check: ## Gate release evidence against size and required-artifact policy
	@python3 scripts/release-policy-check.py \
	    --evidence-dir "artifacts/release-evidence/$(TAG)" \
	    --registry "$(REGISTRY)" \
	    --tag "$(TAG)" \
	    --images "$(IMAGES)" \
	    --max-image-mib "$(MAX_IMAGE_MIB)" \
	    $(if $(filter 1,$(ALLOW_FAILED_EVIDENCE)),--allow-failed-evidence,)

scan-platform: release-evidence ## Alias for platform self-scanning release evidence

## ── Bundle (offline / air-gap) ──────────────────────────────────────────────

bundle: build-all verify-offline bundle-save ## Build all images, verify offline, and save bundle tar

bundle-save: ## Save all images to a bundle tar + SHA256
	@mkdir -p $(BUNDLE_DIR)
	@echo "==> Saving all images to $(BUNDLE_TAR)"
	@docker save \
	    $(foreach img,$(IMAGES),$(REGISTRY)/spt-$(img):$(TAG)) \
	    -o $(BUNDLE_TAR)
	@echo "Bundle written to $(BUNDLE_TAR)"
	@echo "==> Writing image inventory to $(BUNDLE_MANIFEST)"
	@docker image inspect \
	    $(foreach img,$(IMAGES),$(REGISTRY)/spt-$(img):$(TAG)) \
	    > $(BUNDLE_MANIFEST)
	@echo "==> Generating SHA-256 checksum"
	@sha256sum $(BUNDLE_TAR) > $(BUNDLE_TAR).sha256
	@cat $(BUNDLE_TAR).sha256

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
	@docker save $$(cat $(BUNDLE_DIR)/spt-images-$(TAG).txt) -o $(BUNDLE_TAR)
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
	@TAG="$(TAG)" DATA_DIR="$(DATA_DIR)" DATA_BUNDLE_DIR="$(DATA_BUNDLE_DIR)" DATA_MANIFEST_CHECKSUM_MODE="$(DATA_MANIFEST_CHECKSUM_MODE)" bash scripts/write-data-bundle-manifest.sh
	@echo "==> Creating data bundle $(DATA_BUNDLE_TAR)"
	@tar -cf $(DATA_BUNDLE_TAR) -C data-bundles sources
	@sha256sum $(DATA_BUNDLE_TAR) > $(DATA_BUNDLE_TAR).sha256
	@cat $(DATA_BUNDLE_TAR).sha256

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
	@echo "==> Removing bundle output directories"
	@rm -rf $(BUNDLE_DIR) $(DATA_BUNDLE_DIR)

clean-artifacts: ## Remove smoke and restore artifacts (artifacts/)
	@echo "==> Removing artifacts/"
	@rm -rf artifacts/

clean-data-sources: ## DESTRUCTIVE: Remove data-bundles/sources — requires CONFIRM=yes
	@test "$(CONFIRM)" = "yes" || \
	    { printf "ERROR: clean-data-sources deletes all fetched data.\nRun: make clean-data-sources CONFIRM=yes\n" >&2; exit 1; }
	@echo "==> Removing data-bundles/sources"
	@rm -rf data-bundles/sources

clean-all-generated: ## DESTRUCTIVE: Remove all generated output — requires CONFIRM=yes
	@test "$(CONFIRM)" = "yes" || \
	    { printf "ERROR: clean-all-generated deletes bundles, artifacts, and data sources.\nRun: make clean-all-generated CONFIRM=yes\n" >&2; exit 1; }
	@$(MAKE) clean-bundles
	@$(MAKE) clean-artifacts
	@$(MAKE) clean-data-sources CONFIRM=yes
	@echo "==> All generated output removed."

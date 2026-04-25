# security-platform-toolchain Makefile
# Targets: build-all, per-image builds, lint, test, bundle

REGISTRY   ?= registry.internal/security-platform
TAG        ?= latest
BASE_IMAGE ?= $(REGISTRY)/spt-base:$(TAG)
IMAGES     := base schema-validator result-normalizers c-cpp-analysis coverage-tools fuzzing replay-runner sbom osv-scanner secrets image-scanner re-lightweight yara intel-ingest rag-indexer diff-impact ghidra-base ghidra-exporter ghidra-mcp eval-runner gitnexus semgrep codeql corpus-tools symbolic
TARGET_REGISTRY ?= $(REGISTRY)
SOURCE_REGISTRY ?= $(REGISTRY)

.PHONY: all build-all lint test test-offline verify-offline functional-smoke bundle load-bundle image-list pull-bundle push push-registry clean $(IMAGES)

all: build-all

## ── Build ──────────────────────────────────────────────────────────────────

build-all: $(IMAGES)

base:
	docker build -t $(REGISTRY)/spt-base:$(TAG) -f images/base/Dockerfile .

schema-validator: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-schema-validator:$(TAG) -f images/schema-validator/Dockerfile .

result-normalizers: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-result-normalizers:$(TAG) -f images/result-normalizers/Dockerfile .

c-cpp-analysis: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-c-cpp-analysis:$(TAG) -f images/c-cpp-analysis/Dockerfile .

coverage-tools: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-coverage-tools:$(TAG) -f images/coverage-tools/Dockerfile .

fuzzing: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-fuzzing:$(TAG) -f images/fuzzing/Dockerfile .

replay-runner: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-replay-runner:$(TAG) -f images/replay-runner/Dockerfile .

sbom: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-sbom:$(TAG) -f images/sbom/Dockerfile .

osv-scanner: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-osv-scanner:$(TAG) -f images/osv-scanner/Dockerfile .

secrets: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-secrets:$(TAG) -f images/secrets/Dockerfile .

image-scanner: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-image-scanner:$(TAG) -f images/image-scanner/Dockerfile .

re-lightweight: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-re-lightweight:$(TAG) -f images/re-lightweight/Dockerfile .

yara: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-yara:$(TAG) -f images/yara/Dockerfile .

intel-ingest: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-intel-ingest:$(TAG) -f images/intel-ingest/Dockerfile .

rag-indexer: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-rag-indexer:$(TAG) -f images/rag-indexer/Dockerfile .

diff-impact: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-diff-impact:$(TAG) -f images/diff-impact/Dockerfile .

ghidra-base: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-ghidra-base:$(TAG) -f images/ghidra-base/Dockerfile .

ghidra-exporter: ghidra-base
	docker build --build-arg GHIDRA_BASE_IMAGE=$(REGISTRY)/spt-ghidra-base:$(TAG) -t $(REGISTRY)/spt-ghidra-exporter:$(TAG) -f images/ghidra-exporter/Dockerfile .

ghidra-mcp: ghidra-base
	docker build --build-arg GHIDRA_BASE_IMAGE=$(REGISTRY)/spt-ghidra-base:$(TAG) -t $(REGISTRY)/spt-ghidra-mcp:$(TAG) -f images/ghidra-mcp/Dockerfile .

eval-runner: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-eval-runner:$(TAG) -f images/eval-runner/Dockerfile .

gitnexus: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-gitnexus:$(TAG) -f images/gitnexus/Dockerfile .

semgrep: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-semgrep:$(TAG) -f images/semgrep/Dockerfile .

codeql: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-codeql:$(TAG) -f images/codeql/Dockerfile .

corpus-tools: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-corpus-tools:$(TAG) -f images/corpus-tools/Dockerfile .

symbolic: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-symbolic:$(TAG) -f images/symbolic/Dockerfile .

## ── Lint ───────────────────────────────────────────────────────────────────

lint:
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

## ── Test ───────────────────────────────────────────────────────────────────

test:
	@echo "==> Smoke-testing images"
	@for img in $(IMAGES); do \
	    name="spt-$$img"; \
	    echo "  -> $(REGISTRY)/$$name:$(TAG)"; \
	    docker run --rm $(REGISTRY)/$$name:$(TAG) /bin/true || exit 1; \
	done
	@echo "==> Running emit-job-report.py unit tests"
	@python3 -m pytest common/ -v
	@echo "Tests passed."

test-offline verify-offline:
	@echo "==> Smoke-testing images with Docker network disabled"
	@for img in $(IMAGES); do \
	    name="spt-$$img"; \
	    echo "  -> $(REGISTRY)/$$name:$(TAG) (--network none)"; \
	    docker run --rm --network none $(REGISTRY)/$$name:$(TAG) /bin/true || exit 1; \
	done
	@echo "Offline smoke test passed."

functional-smoke:
	@bash examples/functional-smoke/run-functional-smoke.sh "$(REGISTRY)" "$(TAG)"

## ── Bundle (offline / air-gap) ─────────────────────────────────────────────

BUNDLE_DIR ?= offline-bundles/out
BUNDLE_TAR  = $(BUNDLE_DIR)/spt-bundle-$(TAG).tar
BUNDLE_MANIFEST = $(BUNDLE_DIR)/spt-bundle-$(TAG).manifest.json
DATA_DIR ?= data-bundles/sources
DATA_BUNDLE_DIR ?= data-bundles/out
DATA_BUNDLE_TAR = $(DATA_BUNDLE_DIR)/spt-data-bundle-$(TAG).tar

bundle: build-all verify-offline
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

load-bundle:
	@echo "==> Loading images from $(BUNDLE_TAR)"
	@docker load -i $(BUNDLE_TAR)

image-list:
	@mkdir -p $(BUNDLE_DIR)
	@for img in $(IMAGES); do \
	    echo "$(SOURCE_REGISTRY)/spt-$$img:$(TAG)"; \
	done > $(BUNDLE_DIR)/spt-images-$(TAG).txt
	@echo "Image list written to $(BUNDLE_DIR)/spt-images-$(TAG).txt"

pull-bundle: image-list
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

data-fetch:
	@bash data-bundles/fetch/fetch-all.sh "$(DATA_DIR)"

data-bundle:
	@mkdir -p $(DATA_BUNDLE_DIR)
	@echo "==> Creating data bundle $(DATA_BUNDLE_TAR)"
	@tar -cf $(DATA_BUNDLE_TAR) -C data-bundles sources
	@sha256sum $(DATA_BUNDLE_TAR) > $(DATA_BUNDLE_TAR).sha256
	@cat $(DATA_BUNDLE_TAR).sha256

data-verify:
	@echo "==> Verifying data bundle checksum"
	@sha256sum -c $(DATA_BUNDLE_TAR).sha256

## ── Push ───────────────────────────────────────────────────────────────────

push: build-all
	@for img in $(IMAGES); do \
	    docker push $(REGISTRY)/spt-$$img:$(TAG); \
	done

push-registry:
	@echo "==> Tagging and pushing images to $(TARGET_REGISTRY)"
	@for img in $(IMAGES); do \
	    src="$(REGISTRY)/spt-$$img:$(TAG)"; \
	    dst="$(TARGET_REGISTRY)/spt-$$img:$(TAG)"; \
	    echo "  -> $$dst"; \
	    docker tag "$$src" "$$dst" || exit 1; \
	    docker push "$$dst" || exit 1; \
	done

## ── Helpers ─────────────────────────────────────────────────────────────────

clean:
	@echo "==> Removing generated bundle artifacts"
	@rm -rf $(BUNDLE_DIR)

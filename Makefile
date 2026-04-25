# security-platform-toolchain Makefile
# Targets: build-all, per-image builds, lint, test, bundle

REGISTRY   ?= registry.internal/security-platform
TAG        ?= latest
BASE_IMAGE ?= $(REGISTRY)/spt-base:$(TAG)
IMAGES     := base c-cpp-analysis fuzzing gitnexus semgrep codeql sbom secrets corpus-tools replay-runner symbolic

.PHONY: all build-all lint test test-offline verify-offline bundle load-bundle push clean $(IMAGES)

all: build-all

## ── Build ──────────────────────────────────────────────────────────────────

build-all: $(IMAGES)

base:
	docker build -t $(REGISTRY)/spt-base:$(TAG) -f images/base/Dockerfile .

c-cpp-analysis: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-c-cpp-analysis:$(TAG) -f images/c-cpp-analysis/Dockerfile .

fuzzing: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-fuzzing:$(TAG) -f images/fuzzing/Dockerfile .

gitnexus: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-gitnexus:$(TAG) -f images/gitnexus/Dockerfile .

semgrep: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-semgrep:$(TAG) -f images/semgrep/Dockerfile .

codeql: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-codeql:$(TAG) -f images/codeql/Dockerfile .

sbom: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-sbom:$(TAG) -f images/sbom/Dockerfile .

secrets: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-secrets:$(TAG) -f images/secrets/Dockerfile .

corpus-tools: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-corpus-tools:$(TAG) -f images/corpus-tools/Dockerfile .

replay-runner: base
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(REGISTRY)/spt-replay-runner:$(TAG) -f images/replay-runner/Dockerfile .

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

## ── Bundle (offline / air-gap) ─────────────────────────────────────────────

BUNDLE_DIR ?= offline-bundles/out
BUNDLE_TAR  = $(BUNDLE_DIR)/spt-bundle-$(TAG).tar
BUNDLE_MANIFEST = $(BUNDLE_DIR)/spt-bundle-$(TAG).manifest.json

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

## ── Push ───────────────────────────────────────────────────────────────────

push: build-all
	@for img in $(IMAGES); do \
	    docker push $(REGISTRY)/spt-$$img:$(TAG); \
	done

## ── Helpers ─────────────────────────────────────────────────────────────────

clean:
	@echo "==> Removing generated bundle artifacts"
	@rm -rf $(BUNDLE_DIR)

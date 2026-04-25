# security-platform-toolchain Makefile
# Targets: build-all, per-image builds, lint, test, bundle

REGISTRY   ?= ghcr.io/jonsmithtlt
TAG        ?= latest
IMAGES     := base c-cpp-analysis fuzzing gitnexus semgrep codeql sbom secrets corpus-tools replay-runner symbolic

.PHONY: all build-all lint test bundle $(IMAGES)

all: build-all

## ── Build ──────────────────────────────────────────────────────────────────

build-all: $(IMAGES)

base:
	docker build -t $(REGISTRY)/spt-base:$(TAG) images/base/

c-cpp-analysis: base
	docker build -t $(REGISTRY)/spt-c-cpp-analysis:$(TAG) images/c-cpp-analysis/

fuzzing: base
	docker build -t $(REGISTRY)/spt-fuzzing:$(TAG) images/fuzzing/

gitnexus: base
	docker build -t $(REGISTRY)/spt-gitnexus:$(TAG) images/gitnexus/

semgrep: base
	docker build -t $(REGISTRY)/spt-semgrep:$(TAG) images/semgrep/

codeql: base
	docker build -t $(REGISTRY)/spt-codeql:$(TAG) images/codeql/

sbom: base
	docker build -t $(REGISTRY)/spt-sbom:$(TAG) images/sbom/

secrets: base
	docker build -t $(REGISTRY)/spt-secrets:$(TAG) images/secrets/

corpus-tools: base
	docker build -t $(REGISTRY)/spt-corpus-tools:$(TAG) images/corpus-tools/

replay-runner: base
	docker build -t $(REGISTRY)/spt-replay-runner:$(TAG) images/replay-runner/

symbolic: base
	docker build -t $(REGISTRY)/spt-symbolic:$(TAG) images/symbolic/

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

## ── Bundle (offline / air-gap) ─────────────────────────────────────────────

BUNDLE_DIR ?= offline-bundles/out
BUNDLE_TAR  = $(BUNDLE_DIR)/spt-bundle-$(TAG).tar

bundle: build-all
	@mkdir -p $(BUNDLE_DIR)
	@echo "==> Saving all images to $(BUNDLE_TAR)"
	@docker save \
	    $(foreach img,$(IMAGES),$(REGISTRY)/spt-$(img):$(TAG)) \
	    -o $(BUNDLE_TAR)
	@echo "Bundle written to $(BUNDLE_TAR)"
	@echo "==> Generating SHA-256 checksum"
	@sha256sum $(BUNDLE_TAR) > $(BUNDLE_TAR).sha256
	@cat $(BUNDLE_TAR).sha256

## ── Push ───────────────────────────────────────────────────────────────────

push: build-all
	@for img in $(IMAGES); do \
	    docker push $(REGISTRY)/spt-$$img:$(TAG); \
	done

## ── Helpers ─────────────────────────────────────────────────────────────────

clean:
	@echo "==> Removing generated bundle artefacts"
	@rm -rf $(BUNDLE_DIR)

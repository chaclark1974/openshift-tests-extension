# OTE Shell Test Framework — Reusable Makefile Include
#
# Usage in your project Makefile:
#   OTE_BINARY    := my-tests
#   OTE_PRODUCT   := my-product
#   OTE_CMD_PATH  := ./cmd/my-tests/...
#   OTE_ORG_REPO  := openshift/my-tests
#   include ../ci/ote-shell.mk
#
# Optional overrides:
#   OTE_SCRIPTS_DIR := scripts    (default: scripts)
#   OTE_SUITE       := my-product/all  (default: $(OTE_PRODUCT)/all)
#   OTE_CI_REFS_DIR := ci/step-registry  (default: ci/step-registry)

OTE_SCRIPTS_DIR ?= scripts
OTE_SUITE       ?= $(OTE_PRODUCT)/all
OTE_CI_REFS_DIR ?= ci/step-registry

GO_COMPLIANCE_POLICY ?= exempt_all

.PHONY: ote-build ote-test ote-validate ote-lint ote-ci ote-generate-refs

ote-build:
	GO_COMPLIANCE_POLICY="$(GO_COMPLIANCE_POLICY)" go build -o $(OTE_BINARY) $(OTE_CMD_PATH)

ote-test: ote-build
ifdef ARTIFACT_DIR
	$(eval TIMESTAMP := $(shell date +%Y%m%d-%H%M%S))
	./$(OTE_BINARY) run-suite $(OTE_SUITE) \
		--junit-path $(ARTIFACT_DIR)/junit_$(TIMESTAMP).xml \
		--html-path $(ARTIFACT_DIR)/results-summary-$(TIMESTAMP).html
else
	./$(OTE_BINARY) run-suite $(OTE_SUITE)
endif

ote-validate: ote-build
	@echo "==> Validating extension info..."
	@./$(OTE_BINARY) info
	@echo ""
	@echo "==> Listing tests..."
	@./$(OTE_BINARY) list tests --names
	@echo ""
	@echo "==> Listing suites..."
	@./$(OTE_BINARY) list suites
	@echo ""
	@echo "==> Validation passed."

ote-lint:
	@echo "==> Linting shell scripts in $(OTE_SCRIPTS_DIR)/..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		find $(OTE_SCRIPTS_DIR) -name '*.sh' -exec shellcheck -e SC2317 {} +; \
		echo "==> Lint passed."; \
	else \
		echo "WARN: shellcheck not installed, skipping lint"; \
	fi

ote-ci: ote-build ote-validate ote-lint ote-test
	@echo "==> CI pipeline complete."

ote-generate-refs: ote-build
	@mkdir -p $(OTE_CI_REFS_DIR)
	./$(OTE_BINARY) generate-ci-refs \
		--org-repo $(OTE_ORG_REPO) \
		--output-dir $(OTE_CI_REFS_DIR)

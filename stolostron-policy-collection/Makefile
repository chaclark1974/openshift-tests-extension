BINARY := stolostron-policy-collection

IMAGE_REPO ?= quay.io/stolostron/policy-collection-tests
IMAGE_TAG  ?= latest

.PHONY: build test list validate clean lint-scripts ci image

build:
	GO_COMPLIANCE_POLICY="exempt_all" go build -o $(BINARY) ./cmd/stolostron-policy-collection/...

test: build
ifdef ARTIFACT_DIR
	$(eval TIMESTAMP := $(shell date +%Y%m%d-%H%M%S))
	./$(BINARY) run-suite policy-collection/all \
		--junit-path $(ARTIFACT_DIR)/junit_policy-collection_$(TIMESTAMP).xml \
		--html-path $(ARTIFACT_DIR)/results-policy-collection-$(TIMESTAMP).html
else
	./$(BINARY) run-suite policy-collection/all
endif

list: build
	./$(BINARY) list tests

validate: build
	@echo "==> Validating extension info..."
	@./$(BINARY) info
	@echo ""
	@echo "==> Listing tests..."
	@./$(BINARY) list tests --output names
	@echo ""
	@echo "==> Listing suites..."
	@./$(BINARY) list suites
	@echo ""
	@echo "==> Validation passed."

lint-scripts:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "==> Running shellcheck..."; \
		shellcheck -e SC2317 scripts/*.sh; \
		echo "==> shellcheck passed."; \
	else \
		echo "Warning: shellcheck not installed, skipping lint"; \
	fi

ci: build validate lint-scripts

image: build
	@echo "==> Building container image $(IMAGE_REPO):$(IMAGE_TAG)..."
	podman build -t $(IMAGE_REPO):$(IMAGE_TAG) -f Dockerfile ..
	@echo "==> Image built: $(IMAGE_REPO):$(IMAGE_TAG)"

clean:
	rm -f $(BINARY)

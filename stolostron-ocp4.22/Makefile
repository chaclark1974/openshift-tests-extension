BINARY := stolostron-ocp4.22

.PHONY: build test list validate clean lint-scripts

build:
	GO_COMPLIANCE_POLICY="exempt_all" go build -o $(BINARY) ./cmd/stolostron-ocp4.22/...

test: build
	./$(BINARY) run-suite policy-collection/all

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
		shellcheck scripts/*.sh; \
		echo "==> shellcheck passed."; \
	else \
		echo "Warning: shellcheck not installed, skipping lint"; \
	fi

clean:
	rm -f $(BINARY)

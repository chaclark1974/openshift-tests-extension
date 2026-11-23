BINARY  := ote--interop
# Version symbols live in the OTE framework module, not this one.
OTE_PKG := github.com/openshift-eng/openshift-tests-extension

# The --component identifier for this extension (product:kind:name).
COMPONENT := acm:layered-product:acm-tests

GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
GIT_TREE_STATE := $(shell if git diff --quiet 2>/dev/null; then echo clean; else echo dirty; fi)

LDFLAGS := -X '$(OTE_PKG)/pkg/version.CommitFromGit=$(GIT_COMMIT)' \
           -X '$(OTE_PKG)/pkg/version.BuildDate=$(BUILD_DATE)' \
           -X '$(OTE_PKG)/pkg/version.GitTreeState=$(GIT_TREE_STATE)'

.PHONY: build test list validate clean

build:
	# GO_COMPLIANCE_POLICY="exempt_all" is for test binaries only (disables FIPS
	# policies for this compile); do not set it globally.
	GO_COMPLIANCE_POLICY="exempt_all" go build -ldflags "$(LDFLAGS)" -o $(BINARY) ./cmd/ote--interop/...

test: build
	./$(BINARY) run-suite acm/policy/opp-bundle

list: build
	./$(BINARY) list tests --component $(COMPONENT)

validate: build
	@echo "==> info"
	./$(BINARY) info --component $(COMPONENT)
	@echo "==> list tests"
	./$(BINARY) list tests --component $(COMPONENT) --output names
	@echo "==> list suites"
	./$(BINARY) list suites --component $(COMPONENT)
	@echo "==> Validation passed."

clean:
	rm -f $(BINARY)

GO_PKG_NAME := github.com/openshift-eng/openshift-tests-extension

GIT_COMMIT := $(shell git rev-parse --short HEAD)
BUILD_DATE := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
GIT_TREE_STATE := $(shell if git diff --quiet; then echo clean; else echo dirty; fi)

LDFLAGS := -X '$(GO_PKG_NAME)/pkg/version.CommitFromGit=$(GIT_COMMIT)' \
           -X '$(GO_PKG_NAME)/pkg/version.BuildDate=$(BUILD_DATE)' \
           -X '$(GO_PKG_NAME)/pkg/version.GitTreeState=$(GIT_TREE_STATE)'

.PHONY: verify test lint lint-shell clean unit integration integration-shell integration-orchestrator example-tests framework-tests fixture-tests ote-onboard ote-validate-ci images products

all: unit build integration

verify: lint

build: example-tests framework-tests

example-tests:
	# GO_COMPLIANCE_POLICY="exempt_all" must only be used for test related binaries.
	# It prevents various FIPS compliance policies from being applied to this compilation.
	# Do not set globally.
	GO_COMPLIANCE_POLICY="exempt_all" go build -ldflags "$(LDFLAGS)" ./cmd/example-tests/...

framework-tests:
	# GO_COMPLIANCE_POLICY="exempt_all" must only be used for test related binaries.
	# It prevents various FIPS compliance policies from being applied to this compilation.
	# Do not set globally.
	GO_COMPLIANCE_POLICY="exempt_all" go build -ldflags "$(LDFLAGS)" ./cmd/framework-tests/...

test: unit integration

unit:
	go test ./...

integration: build
ifeq ($(OPENSHIFT_CI), true)
	$(eval TIMESTAMP := $(shell date +%Y%m%d-%H%M%S))
	./framework-tests run-suite openshift-tests-extension/framework --junit-path $(ARTIFACT_DIR)/junit_$(TIMESTAMP).xml --html-path $(ARTIFACT_DIR)/results-summary-$(TIMESTAMP).html
else
	./framework-tests run-suite openshift-tests-extension/framework
endif

lint:
	./hack/go-lint.sh run ./...

lint-shell:
	@echo "==> Running shellcheck on all product scripts..."
	@shellcheck -e SC2317 \
		cnv-tests/scripts/*.sh \
		virt-tests/scripts/*.sh \
		opp-tests/scripts/*.sh \
		stolostron-policy-collection/scripts/*.sh \
		interop-tests/scripts/*.sh \
		ote-scaffold.sh
	@echo "==> All shell scripts passed shellcheck."

ote-onboard:
	GO_COMPLIANCE_POLICY="exempt_all" go build -ldflags "$(LDFLAGS)" -o ote-onboard ./cmd/ote-onboard/...

ote-validate-ci:
	GO_COMPLIANCE_POLICY="exempt_all" go build -ldflags "$(LDFLAGS)" -o ote-validate-ci ./cmd/ote-validate-ci/...

fixture-tests:
	GO_COMPLIANCE_POLICY="exempt_all" go build -ldflags "$(LDFLAGS)" ./cmd/fixture-tests/...

products:
	cd cnv-tests && make build
	cd virt-tests && make build
	cd opp-tests && make build
	cd stolostron-policy-collection && make build
	cd interop-tests && make build

integration-shell: build fixture-tests
	GO_COMPLIANCE_POLICY="exempt_all" go build -ldflags "$(LDFLAGS)" -o integration-tests ./test/integration/cmd/integration-tests/...
	./integration-tests run-suite integration/all
	rm -f integration-tests

integration-orchestrator: build fixture-tests products
	GO_COMPLIANCE_POLICY="exempt_all" go build -ldflags "$(LDFLAGS)" -o integration-tests ./test/integration/cmd/integration-tests/...
	./integration-tests run-suite integration/orchestrator
	rm -f integration-tests

images:
	cd cnv-tests && make image
	cd virt-tests && make image
	cd opp-tests && make image
	cd stolostron-policy-collection && make image

clean:
	rm -f example-tests framework-tests fixture-tests integration-tests ote-onboard ote-validate-ci

#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# ------------------------------------------------------------------
# OTE Shell Test Scaffolding Script
# Generates a complete OTE extension project for shell-based tests.
# ------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $0 --name NAME --product PRODUCT --org ORG [--kind KIND]

Generates a complete OTE extension project for shell-based tests
using the non-payload path.

Required:
  --name       Binary/project name (e.g., "acme-tests")
  --product    Product identifier   (e.g., "acme")
  --org        Go module prefix     (e.g., "github.com/acme-corp")

Optional:
  --kind         Component kind (default: "external")
                 Options: external, layered-product, standalone
  --ci-org-repo  GitHub org/repo for CI step registry ref generation
                 (e.g., "openshift/acme-tests")
EOF
    exit 1
}

declare name="" product="" org="" kind="external" ciOrgRepo=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)         name="$2";         shift 2 ;;
        --product)      product="$2";      shift 2 ;;
        --org)          org="$2";          shift 2 ;;
        --kind)         kind="$2";         shift 2 ;;
        --ci-org-repo)  ciOrgRepo="$2";    shift 2 ;;
        -h|--help) usage ;;
        *)         echo "Unknown flag: $1"; usage ;;
    esac
done

[[ -z "$name" || -z "$product" || -z "$org" ]] && usage

declare module="${org}/${name}"
declare projectDir="${name}"

if [[ -d "$projectDir" ]]; then
    echo "Error: directory ${projectDir}/ already exists. Remove it first or choose a different name."
    exit 1
fi

echo "==> Generating OTE project: ${projectDir}"
echo "    Module:  ${module}"
echo "    Product: ${product}"
echo "    Kind:    ${kind}"

mkdir -p "${projectDir}/cmd/${name}"
mkdir -p "${projectDir}/scripts"

# ----------------------------------------------------------------
# go.mod
# ----------------------------------------------------------------
cat > "${projectDir}/go.mod" <<GOMOD
module ${module}

go 1.23

require (
	github.com/openshift-eng/openshift-tests-extension v0.0.0
	github.com/spf13/cobra v1.8.1
)

replace github.com/openshift-eng/openshift-tests-extension => ../
GOMOD

# ----------------------------------------------------------------
# cmd/<name>/main.go
# ----------------------------------------------------------------
cat > "${projectDir}/cmd/${name}/main.go" <<MAIN_GO
package main

import (
	"fmt"
	"os"
	"time"

	"github.com/spf13/cobra"

	"github.com/openshift-eng/openshift-tests-extension/pkg/cmd"
	e "github.com/openshift-eng/openshift-tests-extension/pkg/extension"
	et "github.com/openshift-eng/openshift-tests-extension/pkg/extension/extensiontests"
	"github.com/openshift-eng/openshift-tests-extension/pkg/shell"
)

const (
	manifestPath = "tests.json"
	scriptsDir   = "scripts"
	product      = "${product}"
	kind         = "${kind}"
	binaryName   = "${name}"
)

func main() {
	registry := e.NewRegistry()
	ext := e.NewExtension(product, kind, binaryName)

	// Load tests from manifest if it exists, otherwise auto-discover scripts
	var specs et.ExtensionTestSpecs
	var suites []shell.SuiteEntry
	var err error

	if _, statErr := os.Stat(manifestPath); statErr == nil {
		specs, suites, err = shell.LoadManifest(manifestPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error loading manifest: %v\n", err)
			os.Exit(1)
		}
	} else {
		specs, err = shell.DiscoverScripts(scriptsDir, "sig-"+product)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error discovering scripts: %v\n", err)
			os.Exit(1)
		}
	}

	// Register suites from manifest
	for _, s := range suites {
		suite := e.Suite{
			Name:        s.Name,
			Description: s.Description,
			Parents:     s.Parents,
			Qualifiers:  s.Qualifiers,
			Parallelism: s.Parallelism,
		}
		if s.TestTimeout != "" {
			if d, err := time.ParseDuration(s.TestTimeout); err == nil {
				suite.TestTimeout = &d
			}
		}
		if len(s.Parents) > 0 {
			ext.AddSuite(suite)
		} else {
			ext.AddGlobalSuite(suite)
		}
	}

	// Always add a default "all" suite if no suites were defined
	if len(suites) == 0 {
		ext.AddSuite(e.Suite{
			Name:        product + "/all",
			Description: "All " + product + " tests",
		})
		ext.AddSuite(e.Suite{
			Name:        product + "/smoke",
			Description: "Smoke tests for " + product,
			Qualifiers: []string{
				\`labels.exists(l, l=="SMOKE")\`,
			},
		})
	}

	ext.AddSpecs(specs)
	registry.Register(ext)

	root := &cobra.Command{
		Long: product + " Test Extension (OTE)",
	}
	root.AddCommand(cmd.DefaultExtensionCommands(registry)...)

	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}
MAIN_GO

# ----------------------------------------------------------------
# tests.json
# ----------------------------------------------------------------
cat > "${projectDir}/tests.json" <<MANIFEST
{
  "defaults": {
    "tags": {
      "product": "${product}"
    },
    "lifecycle": "blocking",
    "timeout": "10m"
  },
  "tests": [
    {
      "name": "[sig-${product}] example test should pass",
      "script": "scripts/example-pass.sh",
      "labels": ["SMOKE"]
    },
    {
      "name": "[sig-${product}] example test should skip when not applicable",
      "script": "scripts/example-skip.sh"
    }
  ],
  "suites": [
    {
      "name": "${product}/all",
      "description": "All ${product} tests"
    },
    {
      "name": "${product}/smoke",
      "description": "Smoke tests for ${product}",
      "qualifiers": ["labels.exists(l, l==\"SMOKE\")"]
    }
  ]
}
MANIFEST

# ----------------------------------------------------------------
# Example shell scripts
# ----------------------------------------------------------------
cat > "${projectDir}/scripts/example-pass.sh" <<'SCRIPT'
#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true
echo "Running example passing test"
echo "All checks passed."
exit 0
true
SCRIPT

cat > "${projectDir}/scripts/example-skip.sh" <<'SCRIPT'
#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true
if [[ -z "${REQUIRED_ENV_VAR:-}" ]]; then
    echo "REQUIRED_ENV_VAR not set, skipping test"
    exit 2
fi
echo "Running test with REQUIRED_ENV_VAR=${REQUIRED_ENV_VAR}"
exit 0
true
SCRIPT

chmod +x "${projectDir}/scripts/"*.sh

# ----------------------------------------------------------------
# Makefile
# ----------------------------------------------------------------
cat > "${projectDir}/Makefile" <<MAKEFILE
BINARY := ${name}
IMAGE_REPO ?= quay.io/openshift/${name}
IMAGE_TAG  ?= latest

.PHONY: build test list validate clean lint-scripts ci image

build:
	GO_COMPLIANCE_POLICY="exempt_all" go build -o \$(BINARY) ./cmd/${name}/...

test: build
ifdef ARTIFACT_DIR
	\$(eval TIMESTAMP := \$(shell date +%Y%m%d-%H%M%S))
	./\$(BINARY) run-suite ${product}/all \\
		--junit-path \$(ARTIFACT_DIR)/junit_${product}_\$(TIMESTAMP).xml \\
		--html-path \$(ARTIFACT_DIR)/results-${product}-\$(TIMESTAMP).html
else
	./\$(BINARY) run-suite ${product}/all
endif

list: build
	./\$(BINARY) list tests

validate: build
	@echo "==> Validating extension info..."
	@./\$(BINARY) info
	@echo ""
	@echo "==> Listing tests..."
	@./\$(BINARY) list tests --output names
	@echo ""
	@echo "==> Listing suites..."
	@./\$(BINARY) list suites
	@echo ""
	@echo "==> Validation passed."

lint-scripts:
	@if command -v shellcheck >/dev/null 2>&1; then \\
		echo "==> Running shellcheck..."; \\
		shellcheck -e SC2317 scripts/*.sh; \\
		echo "==> shellcheck passed."; \\
	else \\
		echo "Warning: shellcheck not installed, skipping lint"; \\
	fi

ci: build validate lint-scripts

image: build
	@echo "==> Building container image \$(IMAGE_REPO):\$(IMAGE_TAG)..."
	podman build -t \$(IMAGE_REPO):\$(IMAGE_TAG) -f Dockerfile ..
	@echo "==> Image built: \$(IMAGE_REPO):\$(IMAGE_TAG)"

clean:
	rm -f \$(BINARY)
MAKEFILE

# ----------------------------------------------------------------
# Dockerfile
# ----------------------------------------------------------------
cat > "${projectDir}/Dockerfile" <<DOCKERFILE
FROM registry.access.redhat.com/ubi9/go-toolset:1.23 AS builder
WORKDIR /build
COPY . .
WORKDIR /build/${name}
RUN GO_COMPLIANCE_POLICY="exempt_all" go build -o ${name} ./cmd/${name}/...

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
COPY --from=builder /build/${name}/${name} /usr/local/bin/${name}
COPY --from=builder /build/${name}/scripts /opt/tests/scripts
COPY --from=builder /build/${name}/tests.json /opt/tests/tests.json
WORKDIR /opt/tests
ENTRYPOINT ["${name}"]
DOCKERFILE

# ----------------------------------------------------------------
# CI step registry refs (optional)
# ----------------------------------------------------------------
if [[ -n "${ciOrgRepo}" ]]; then
    echo "==> Generating CI step registry refs..."
    mkdir -p "${projectDir}/ci/step-registry"

    for suiteSuffix in all smoke; do
        declare suiteName="${product}/${suiteSuffix}"
        declare repoName
        repoName=$(echo "${ciOrgRepo}" | cut -d'/' -f2)
        declare refName="${repoName}-${product}-${suiteSuffix}"

        cat > "${projectDir}/ci/step-registry/${refName}-ref.yaml" <<CIREF
ref: ${refName}
as: ${refName}
from: ${name}
commands: ${refName}-commands.sh
resources:
  requests:
    cpu: 100m
    memory: 200Mi
documentation: "Runs the ${suiteName} suite from ${name}"
CIREF

        cat > "${projectDir}/ci/step-registry/${refName}-commands.sh" <<CICMD
#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

${name} run-suite ${suiteName}
true
CICMD
        chmod +x "${projectDir}/ci/step-registry/${refName}-commands.sh"
    done
fi

# ----------------------------------------------------------------
# Done
# ----------------------------------------------------------------
echo ""
echo "==> Project generated at: ${projectDir}/"
echo ""
echo "Next steps:"
echo "  cd ${projectDir}"
echo "  go mod tidy"
echo "  make build"
echo "  make validate"
echo ""
echo "To add tests:"
echo "  1. Add shell scripts to scripts/"
echo "  2. Add entries to tests.json"
echo "  3. make build && make test"

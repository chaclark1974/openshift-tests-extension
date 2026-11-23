package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/openshift-eng/openshift-tests-extension/pkg/cmd"
	e "github.com/openshift-eng/openshift-tests-extension/pkg/extension"

	"github.com/stolostron/cluster-lifecycle-e2e/openshift-tests-ext/pkg/adapter"
	scenarios "github.com/stolostron/cluster-lifecycle-e2e/openshift-tests-ext/test/interop"
)

func main() {
	registry := e.NewRegistry()

	// Scenario-JSON-driven: all specs come from the embedded interop_scenarios.json,
	// turned into OTE specs by the generic exec adapter, grouped by product.
	byProduct, err := adapter.BuildSpecsByProductFS(scenarios.ScenarioFS)
	if err != nil {
		panic(fmt.Sprintf("failed to build specs from embedded scenarios: %v", err))
	}

	// ----- ACM extension (first registered => default component) -----
	acmExt := e.NewExtension("acm", "layered-product", "acm-tests")
	acmExt.AddSuite(e.Suite{Name: "acm/opp", Description: "ACM tests in the OPP bundle",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`labels.exists(l, l=="OPP")`}})
	acmExt.AddSuite(e.Suite{Name: "acm/virt", Description: "ACM tests in the ACM+Virt bundle",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`labels.exists(l, l=="ACM-VIRT")`}})
	acmExt.AddSuite(e.Suite{Name: "acm/upgrade", Description: "ACM operator upgrade tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "acm-upgrade"`}})
	acmExt.AddSuite(e.Suite{Name: "acm/policy", Description: "ACM governance/policy tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "acm-policy"`}})
	acmExt.AddSuite(e.Suite{Name: "acm/e2e", Description: "ACM end-to-end tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "acm-e2e"`}})
	acmExt.AddSuite(e.Suite{Name: "acm/gre", Description: "ACM GRE tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "acm-gre"`}})
	acmExt.AddSuite(e.Suite{Name: "acm/lifecycle", Description: "ACM cluster/application lifecycle tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "acm-lifecycle"`}})
	acmExt.AddSuite(e.Suite{Name: "acm/policy-set", Description: "ACM PolicySet tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "acm-policy-set"`}})
	acmExt.AddSuite(e.Suite{Name: "acm/smoke", Description: "ACM smoke tests (fast, across all areas)",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`labels.exists(l, l=="SMOKE")`}})
	acmExt.AddSuite(e.Suite{Name: "acm/policy-smoke", Description: "ACM policy-area smoke tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "acm-policy" && labels.exists(l, l=="SMOKE")`}})
	acmExt.AddSpecs(byProduct["acm"])
	registry.Register(acmExt)

	// ----- Quay extension -----
	quayExt := e.NewExtension("quay", "layered-product", "quay-tests")
	quayExt.AddSuite(e.Suite{Name: "quay/web-e2e", Description: "All Quay web e2e tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`labels.exists(l, l=="QUAY-E2E")`}})
	quayExt.AddSuite(e.Suite{Name: "quay/opp", Description: "Quay tests in the OPP bundle",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`labels.exists(l, l=="OPP")`}})
	quayExt.AddSuite(e.Suite{Name: "quay/repository", Description: "Quay repository tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "quay-repository"`}})
	quayExt.AddSuite(e.Suite{Name: "quay/organization", Description: "Quay organization tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "quay-organization"`}})
	quayExt.AddSuite(e.Suite{Name: "quay/robot", Description: "Quay robot account tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "quay-robot"`}})
	quayExt.AddSpecs(byProduct["quay"])
	registry.Register(quayExt)

	// ----- ACS (StackRox) extension -----
	acsExt := e.NewExtension("acs", "layered-product", "acs-tests")
	acsExt.AddSuite(e.Suite{Name: "acs/qa-e2e", Description: "All ACS qa-e2e tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`labels.exists(l, l=="ACS-E2E")`}})
	acsExt.AddSuite(e.Suite{Name: "acs/vulnerability", Description: "ACS vulnerability management tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "acs-vulnerability"`}})
	acsExt.AddSuite(e.Suite{Name: "acs/compliance", Description: "ACS compliance tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "acs-compliance"`}})
	acsExt.AddSuite(e.Suite{Name: "acs/network", Description: "ACS network tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "acs-network"`}})
	acsExt.AddSuite(e.Suite{Name: "acs/admission", Description: "ACS admission control tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "acs-admission"`}})
	acsExt.AddSuite(e.Suite{Name: "acs/smoke", Description: "ACS smoke tests (fast, across all areas)",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`labels.exists(l, l=="SMOKE")`}})
	acsExt.AddSpecs(byProduct["acs"])
	registry.Register(acsExt)

	// ----- ODF (OpenShift Data Foundation) extension -----
	odfExt := e.NewExtension("odf", "layered-product", "odf-tests")
	odfExt.AddSuite(e.Suite{Name: "odf/ocs-ci", Description: "All ODF ocs-ci tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`labels.exists(l, l=="ODF-E2E")`}})
	odfExt.AddSuite(e.Suite{Name: "odf/block", Description: "ODF block (RBD) tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "odf-block"`}})
	odfExt.AddSuite(e.Suite{Name: "odf/file", Description: "ODF file (CephFS) tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "odf-file"`}})
	odfExt.AddSuite(e.Suite{Name: "odf/object", Description: "ODF object (RGW/NooBaa) tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "odf-object"`}})
	odfExt.AddSuite(e.Suite{Name: "odf/cephhealth", Description: "ODF Ceph health tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "odf-cephhealth"`}})
	odfExt.AddSuite(e.Suite{Name: "odf/smoke", Description: "ODF smoke tests (fast, across all areas)",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`labels.exists(l, l=="SMOKE")`}})
	odfExt.AddSpecs(byProduct["odf"])
	registry.Register(odfExt)

	// ----- CNV (Container-native Virtualization) extension -----
	cnvExt := e.NewExtension("cnv", "layered-product", "cnv-tests")
	cnvExt.AddSuite(e.Suite{Name: "cnv/e2e", Description: "All CNV e2e tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`labels.exists(l, l=="CNV-E2E")`}})
	cnvExt.AddSuite(e.Suite{Name: "cnv/vm", Description: "CNV VirtualMachine tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "cnv-vm"`}})
	cnvExt.AddSuite(e.Suite{Name: "cnv/storage", Description: "CNV storage tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "cnv-storage"`}})
	cnvExt.AddSuite(e.Suite{Name: "cnv/network", Description: "CNV network tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "cnv-network"`}})
	cnvExt.AddSuite(e.Suite{Name: "cnv/migration", Description: "CNV live-migration tests",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`tags["category"] == "cnv-migration"`}})
	cnvExt.AddSuite(e.Suite{Name: "cnv/smoke", Description: "CNV smoke tests (fast, across all areas)",
		Parents: []string{"openshift/conformance/parallel"}, Qualifiers: []string{`labels.exists(l, l=="SMOKE")`}})
	cnvExt.AddSpecs(byProduct["cnv"])
	registry.Register(cnvExt)

	root := &cobra.Command{
		Use:  "ote--interop",
		Long: "OpenShift Tests Extension interop binary (ACM + Quay + ACS + ODF + CNV), scenario-JSON-driven",
	}
	root.AddCommand(cmd.DefaultExtensionCommands(registry)...)

	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}

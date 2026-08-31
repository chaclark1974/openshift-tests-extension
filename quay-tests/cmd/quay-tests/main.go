package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/openshift-eng/openshift-tests-extension/pkg/cmd"
	e "github.com/openshift-eng/openshift-tests-extension/pkg/extension"
	et "github.com/openshift-eng/openshift-tests-extension/pkg/extension/extensiontests"
	"github.com/openshift-eng/openshift-tests-extension/pkg/shell"
)

const (
	manifestPath = "tests.json"
	scriptsDir   = "scripts"
	product      = "quay"
	kind         = "external"
	binaryName   = "quay-tests"
)

func main() {
	registry := e.NewRegistry()
	ext := e.NewExtension(product, kind, binaryName)

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

	for _, s := range suites {
		suite := e.Suite{
			Name:        s.Name,
			Description: s.Description,
			Parents:     s.Parents,
			Qualifiers:  s.Qualifiers,
		}
		if len(s.Parents) > 0 {
			ext.AddSuite(suite)
		} else {
			ext.AddGlobalSuite(suite)
		}
	}

	if len(suites) == 0 {
		ext.AddSuite(e.Suite{
			Name:        product + "/all",
			Description: "All " + product + " tests",
		})
		ext.AddSuite(e.Suite{
			Name:        product + "/smoke",
			Description: "Smoke tests for " + product,
			Qualifiers: []string{
				`labels.exists(l, l=="SMOKE")`,
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

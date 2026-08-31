package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/openshift-eng/openshift-tests-extension/pkg/cmd"
	e "github.com/openshift-eng/openshift-tests-extension/pkg/extension"
	"github.com/openshift-eng/openshift-tests-extension/pkg/shell"
)

const (
	manifestPath = "test/integration/tests.json"
	product      = "integration"
	kind         = "external"
	binaryName   = "integration-tests"
)

func main() {
	registry := e.NewRegistry()
	ext := e.NewExtension(product, kind, binaryName)

	specs, suites, err := shell.LoadManifest(manifestPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error loading manifest: %v\n", err)
		os.Exit(1)
	}

	for _, s := range suites {
		ext.AddSuite(e.Suite{
			Name:        s.Name,
			Description: s.Description,
			Qualifiers:  s.Qualifiers,
		})
	}

	ext.AddSpecs(specs)
	registry.Register(ext)

	root := &cobra.Command{
		Long: "OTE Shell Framework Integration Tests",
	}
	root.AddCommand(cmd.DefaultExtensionCommands(registry)...)

	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}

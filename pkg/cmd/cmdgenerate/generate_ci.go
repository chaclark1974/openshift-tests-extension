package cmdgenerate

import (
	"fmt"

	"github.com/spf13/cobra"

	"github.com/openshift-eng/openshift-tests-extension/pkg/extension"
	"github.com/openshift-eng/openshift-tests-extension/pkg/shell"
	"github.com/openshift-eng/openshift-tests-extension/pkg/shell/stepregistry"
)

// NewGenerateCIRefsCommand creates a command that generates step registry ref files.
func NewGenerateCIRefsCommand(registry *extension.Registry) *cobra.Command {
	var orgRepo, imageName, outputDir string

	cmd := &cobra.Command{
		Use:   "generate-ci-refs",
		Short: "Generate OpenShift CI step registry ref files for this extension",
		RunE: func(cmd *cobra.Command, args []string) error {
			ext := registry.Get(extension.DefaultExtension)
			if ext == nil {
				return fmt.Errorf("no extension registered")
			}

			var suites []shell.SuiteEntry
			for _, s := range ext.Suites {
				suites = append(suites, shell.SuiteEntry{
					Name:        s.Name,
					Description: s.Description,
				})
			}

			cfg := stepregistry.RefConfig{
				OrgRepo:    orgRepo,
				BinaryName: ext.Component.Name,
				ImageName:  imageName,
				OutputDir:  outputDir,
			}
			if cfg.ImageName == "" {
				cfg.ImageName = ext.Component.Name
			}

			if err := stepregistry.GenerateRefs(cfg, suites); err != nil {
				return err
			}

			fmt.Fprintf(cmd.OutOrStdout(), "Generated step registry refs in %s/\n", outputDir)
			for _, s := range suites {
				refName := stepregistry.MakeRefName(orgRepo, s.Name)
				fmt.Fprintf(cmd.OutOrStdout(), "  %s-ref.yaml\n", refName)
				fmt.Fprintf(cmd.OutOrStdout(), "  %s-commands.sh\n", refName)
			}
			return nil
		},
	}

	cmd.Flags().StringVar(&orgRepo, "org-repo", "", "GitHub org/repo (e.g. openshift/acme-tests)")
	cmd.Flags().StringVar(&imageName, "image-name", "", "CI image name (defaults to binary name)")
	cmd.Flags().StringVar(&outputDir, "output-dir", "ci/step-registry", "Output directory for ref files")
	_ = cmd.MarkFlagRequired("org-repo")

	return cmd
}

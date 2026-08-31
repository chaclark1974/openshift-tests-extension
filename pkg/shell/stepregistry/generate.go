package stepregistry

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/openshift-eng/openshift-tests-extension/pkg/shell"
	"gopkg.in/yaml.v3"
)

// RefConfig holds configuration for generating step registry refs.
type RefConfig struct {
	OrgRepo    string
	BinaryName string
	ImageName  string
	OutputDir  string
}

// StepRef represents a ci-operator step registry ref YAML structure.
type StepRef struct {
	Ref           string         `yaml:"ref"`
	As            string         `yaml:"as"`
	From          string         `yaml:"from"`
	Commands      string         `yaml:"commands"`
	Resources     StepResources  `yaml:"resources"`
	Documentation string         `yaml:"documentation,omitempty"`
}

// StepResources defines resource requests for a step.
type StepResources struct {
	Requests StepResourceValues `yaml:"requests"`
}

// StepResourceValues defines CPU and memory requests.
type StepResourceValues struct {
	CPU    string `yaml:"cpu"`
	Memory string `yaml:"memory"`
}

// GenerateRefs produces step registry ref files for an OTE extension.
func GenerateRefs(cfg RefConfig, suites []shell.SuiteEntry) error {
	if err := os.MkdirAll(cfg.OutputDir, 0755); err != nil {
		return fmt.Errorf("creating output dir: %w", err)
	}

	if cfg.ImageName == "" {
		cfg.ImageName = cfg.BinaryName
	}

	for _, suite := range suites {
		refName := MakeRefName(cfg.OrgRepo, suite.Name)
		ref := StepRef{
			Ref:      refName,
			As:       refName,
			From:     cfg.ImageName,
			Commands: refName + "-commands.sh",
			Resources: StepResources{
				Requests: StepResourceValues{CPU: "100m", Memory: "200Mi"},
			},
			Documentation: fmt.Sprintf("Runs the %s suite from %s", suite.Name, cfg.BinaryName),
		}

		refPath := filepath.Join(cfg.OutputDir, refName+"-ref.yaml")
		if err := writeYAML(refPath, ref); err != nil {
			return err
		}

		cmdContent := fmt.Sprintf("#!/bin/bash\nset -euxo pipefail\nshopt -s inherit_errexit 2>/dev/null || true\n\n%s run-suite %s\ntrue\n", cfg.BinaryName, suite.Name)
		cmdPath := filepath.Join(cfg.OutputDir, refName+"-commands.sh")
		if err := os.WriteFile(cmdPath, []byte(cmdContent), 0755); err != nil {
			return fmt.Errorf("writing commands.sh: %w", err)
		}
	}

	return nil
}

// MakeRefName converts an org/repo and suite name into a step registry ref name.
func MakeRefName(orgRepo, suiteName string) string {
	parts := strings.SplitN(orgRepo, "/", 2)
	repo := parts[len(parts)-1]
	suite := strings.ReplaceAll(suiteName, "/", "-")
	return repo + "-" + suite
}

func writeYAML(path string, v interface{}) error {
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("creating %s: %w", path, err)
	}
	defer f.Close()

	enc := yaml.NewEncoder(f)
	enc.SetIndent(2)
	defer enc.Close()
	return enc.Encode(v)
}

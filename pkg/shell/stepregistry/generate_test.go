package stepregistry

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/openshift-eng/openshift-tests-extension/pkg/shell"
)

func TestMakeRefName(t *testing.T) {
	tests := []struct {
		orgRepo   string
		suiteName string
		want      string
	}{
		{"openshift/quay-tests", "quay/all", "quay-tests-quay-all"},
		{"openshift/quay-tests", "quay/smoke", "quay-tests-quay-smoke"},
		{"stolostron/acme-tests", "acme/conformance/parallel", "acme-tests-acme-conformance-parallel"},
		{"myorg", "suite", "myorg-suite"},
	}

	for _, tt := range tests {
		got := MakeRefName(tt.orgRepo, tt.suiteName)
		if got != tt.want {
			t.Errorf("MakeRefName(%q, %q) = %q, want %q", tt.orgRepo, tt.suiteName, got, tt.want)
		}
	}
}

func TestGenerateRefs(t *testing.T) {
	dir := t.TempDir()
	suites := []shell.SuiteEntry{
		{Name: "acme/all", Description: "All tests"},
	}

	cfg := RefConfig{
		OrgRepo:    "openshift/acme-tests",
		BinaryName: "acme-tests",
		OutputDir:  dir,
	}

	if err := GenerateRefs(cfg, suites); err != nil {
		t.Fatalf("GenerateRefs: %v", err)
	}

	refPath := filepath.Join(dir, "acme-tests-acme-all-ref.yaml")
	data, err := os.ReadFile(refPath)
	if err != nil {
		t.Fatalf("reading ref yaml: %v", err)
	}
	content := string(data)

	if !strings.Contains(content, "ref: acme-tests-acme-all") {
		t.Errorf("ref yaml missing ref name, got:\n%s", content)
	}
	if !strings.Contains(content, "from: acme-tests") {
		t.Errorf("ref yaml missing from field, got:\n%s", content)
	}
	if !strings.Contains(content, "cpu: 100m") {
		t.Errorf("ref yaml missing resources, got:\n%s", content)
	}

	cmdPath := filepath.Join(dir, "acme-tests-acme-all-commands.sh")
	cmdData, err := os.ReadFile(cmdPath)
	if err != nil {
		t.Fatalf("reading commands.sh: %v", err)
	}
	cmdContent := string(cmdData)

	if !strings.Contains(cmdContent, "acme-tests run-suite acme/all") {
		t.Errorf("commands.sh missing run-suite command, got:\n%s", cmdContent)
	}
	if !strings.Contains(cmdContent, "set -euxo pipefail") {
		t.Errorf("commands.sh missing safety flags, got:\n%s", cmdContent)
	}

	info, _ := os.Stat(cmdPath)
	if info.Mode()&0111 == 0 {
		t.Error("commands.sh is not executable")
	}
}

func TestGenerateRefs_MultiSuite(t *testing.T) {
	dir := t.TempDir()
	suites := []shell.SuiteEntry{
		{Name: "p/all"},
		{Name: "p/smoke"},
		{Name: "p/conformance"},
	}

	cfg := RefConfig{
		OrgRepo:    "org/my-tests",
		BinaryName: "my-tests",
		ImageName:  "custom-image",
		OutputDir:  dir,
	}

	if err := GenerateRefs(cfg, suites); err != nil {
		t.Fatalf("GenerateRefs: %v", err)
	}

	entries, _ := os.ReadDir(dir)
	if len(entries) != 6 {
		t.Errorf("expected 6 files (3 suites x 2), got %d", len(entries))
	}

	refData, _ := os.ReadFile(filepath.Join(dir, "my-tests-p-smoke-ref.yaml"))
	if !strings.Contains(string(refData), "from: custom-image") {
		t.Errorf("expected custom image name in ref, got:\n%s", string(refData))
	}
}

func TestGenerateRefs_EmptySuites(t *testing.T) {
	dir := t.TempDir()
	cfg := RefConfig{
		OrgRepo:    "org/tests",
		BinaryName: "tests",
		OutputDir:  dir,
	}

	if err := GenerateRefs(cfg, nil); err != nil {
		t.Fatalf("GenerateRefs with no suites: %v", err)
	}

	entries, _ := os.ReadDir(dir)
	if len(entries) != 0 {
		t.Errorf("expected 0 files for empty suites, got %d", len(entries))
	}
}

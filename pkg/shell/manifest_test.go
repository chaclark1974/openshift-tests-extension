package shell

import (
	"os"
	"path/filepath"
	"testing"

	et "github.com/openshift-eng/openshift-tests-extension/pkg/extension/extensiontests"
)

func TestParseManifest_Basic(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	writeScript(t, dir, "b.sh", "#!/bin/bash\nexit 0\n")

	manifest := `{
		"defaults": {
			"tags": {"product": "acme"},
			"lifecycle": "blocking"
		},
		"tests": [
			{"name": "[sig-acme] test one", "script": "a.sh", "labels": ["SMOKE"]},
			{"name": "[sig-acme] test two", "script": "b.sh"}
		]
	}`

	specs, suites, err := ParseManifest([]byte(manifest), dir)
	if err != nil {
		t.Fatal(err)
	}

	if len(specs) != 2 {
		t.Fatalf("expected 2 specs, got %d", len(specs))
	}
	if len(suites) != 0 {
		t.Fatalf("expected 0 suites, got %d", len(suites))
	}

	if specs[0].Name != "[sig-acme] test one" {
		t.Errorf("unexpected name: %s", specs[0].Name)
	}
	if !specs[0].Labels.Has("SMOKE") {
		t.Error("expected SMOKE label from test entry")
	}
	if specs[0].Tags["product"] != "acme" {
		t.Error("expected product tag from defaults")
	}
	if specs[1].Tags["product"] != "acme" {
		t.Error("expected product tag propagated to second test")
	}
}

func TestParseManifest_DefaultsMerging(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")

	manifest := `{
		"defaults": {
			"labels": ["DEFAULT-LABEL"],
			"tags": {"team": "platform", "tier": "0"},
			"lifecycle": "informing"
		},
		"tests": [
			{
				"name": "[sig-test] merge test",
				"script": "a.sh",
				"labels": ["SMOKE"],
				"tags": {"tier": "1"},
				"lifecycle": "blocking"
			}
		]
	}`

	specs, _, err := ParseManifest([]byte(manifest), dir)
	if err != nil {
		t.Fatal(err)
	}

	spec := specs[0]
	if !spec.Labels.Has("DEFAULT-LABEL") {
		t.Error("expected default label to be merged")
	}
	if !spec.Labels.Has("SMOKE") {
		t.Error("expected per-test label to be present")
	}
	if spec.Tags["team"] != "platform" {
		t.Error("expected default tag 'team' to carry through")
	}
	if spec.Tags["tier"] != "1" {
		t.Error("expected per-test tag 'tier' to override default")
	}
	if spec.Lifecycle != et.LifecycleBlocking {
		t.Errorf("expected per-test lifecycle override to blocking, got %s", spec.Lifecycle)
	}
}

func TestParseManifest_EnvironmentSelectors(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")

	manifest := `{
		"tests": [
			{
				"name": "[sig-test] env test",
				"script": "a.sh",
				"include": "platform==\"aws\"",
				"exclude": "topology==\"single\""
			}
		]
	}`

	specs, _, err := ParseManifest([]byte(manifest), dir)
	if err != nil {
		t.Fatal(err)
	}

	if specs[0].EnvironmentSelector.Include != `platform=="aws"` {
		t.Errorf("unexpected include: %s", specs[0].EnvironmentSelector.Include)
	}
	if specs[0].EnvironmentSelector.Exclude != `topology=="single"` {
		t.Errorf("unexpected exclude: %s", specs[0].EnvironmentSelector.Exclude)
	}
}

func TestParseManifest_Timeout(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	writeScript(t, dir, "b.sh", "#!/bin/bash\nexit 0\n")

	manifest := `{
		"defaults": {"timeout": "5m"},
		"tests": [
			{"name": "[sig-test] default timeout", "script": "a.sh"},
			{"name": "[sig-test] custom timeout", "script": "b.sh", "timeout": "30s"}
		]
	}`

	specs, _, err := ParseManifest([]byte(manifest), dir)
	if err != nil {
		t.Fatal(err)
	}

	if specs[0].Timeout != 5*60*1e9 {
		t.Errorf("expected 5m default timeout, got %v", specs[0].Timeout)
	}
	if specs[1].Timeout != 30*1e9 {
		t.Errorf("expected 30s per-test timeout, got %v", specs[1].Timeout)
	}
}

func TestParseManifest_Suites(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")

	manifest := `{
		"tests": [
			{"name": "[sig-test] one", "script": "a.sh"}
		],
		"suites": [
			{
				"name": "product/smoke",
				"description": "Smoke tests",
				"qualifiers": ["labels.exists(l, l==\"SMOKE\")"],
				"parents": ["openshift/conformance/parallel"]
			}
		]
	}`

	_, suites, err := ParseManifest([]byte(manifest), dir)
	if err != nil {
		t.Fatal(err)
	}

	if len(suites) != 1 {
		t.Fatalf("expected 1 suite, got %d", len(suites))
	}
	if suites[0].Name != "product/smoke" {
		t.Errorf("unexpected suite name: %s", suites[0].Name)
	}
	if len(suites[0].Parents) != 1 || suites[0].Parents[0] != "openshift/conformance/parallel" {
		t.Errorf("unexpected parents: %v", suites[0].Parents)
	}
}

func TestParseManifest_MissingName(t *testing.T) {
	manifest := `{"tests": [{"script": "a.sh"}]}`
	_, _, err := ParseManifest([]byte(manifest), ".")
	if err == nil {
		t.Fatal("expected error for missing name")
	}
}

func TestParseManifest_MissingScript(t *testing.T) {
	manifest := `{"tests": [{"name": "test"}]}`
	_, _, err := ParseManifest([]byte(manifest), ".")
	if err == nil {
		t.Fatal("expected error for missing script")
	}
}

func TestParseManifest_InvalidTimeout(t *testing.T) {
	manifest := `{"defaults": {"timeout": "notaduration"}, "tests": [{"name": "test", "script": "a.sh"}]}`
	_, _, err := ParseManifest([]byte(manifest), ".")
	if err == nil {
		t.Fatal("expected error for invalid timeout")
	}
}

func TestParseManifest_InvalidJSON(t *testing.T) {
	_, _, err := ParseManifest([]byte("not json"), ".")
	if err == nil {
		t.Fatal("expected error for invalid JSON")
	}
}

func TestLoadManifest(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")

	manifest := `{"tests": [{"name": "[sig-test] loaded", "script": "a.sh"}]}`
	manifestPath := filepath.Join(dir, "tests.json")
	if err := os.WriteFile(manifestPath, []byte(manifest), 0644); err != nil {
		t.Fatal(err)
	}

	specs, _, err := LoadManifest(manifestPath)
	if err != nil {
		t.Fatal(err)
	}
	if len(specs) != 1 {
		t.Fatalf("expected 1 spec, got %d", len(specs))
	}
	if specs[0].Name != "[sig-test] loaded" {
		t.Errorf("unexpected name: %s", specs[0].Name)
	}
}

func TestLoadManifest_FileNotFound(t *testing.T) {
	_, _, err := LoadManifest("/nonexistent/tests.json")
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestDiscoverScripts(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "check-api.sh", "#!/bin/bash\nexit 0\n")
	writeScript(t, dir, "validate-dns.sh", "#!/bin/bash\nexit 0\n")
	writeScript(t, dir, "not-a-script.txt", "hello")

	specs, err := DiscoverScripts(dir, "sig-test")
	if err != nil {
		t.Fatal(err)
	}

	if len(specs) != 2 {
		t.Fatalf("expected 2 specs (only .sh files), got %d", len(specs))
	}

	names := map[string]bool{}
	for _, s := range specs {
		names[s.Name] = true
	}
	if !names["[sig-test] check api"] {
		t.Error("expected [sig-test] check api")
	}
	if !names["[sig-test] validate dns"] {
		t.Error("expected [sig-test] validate dns")
	}
}

func TestDiscoverScripts_EmptyDir(t *testing.T) {
	dir := t.TempDir()
	_, err := DiscoverScripts(dir, "sig-test")
	if err == nil {
		t.Fatal("expected error for empty directory")
	}
}

func TestDiscoverScripts_NonexistentDir(t *testing.T) {
	_, err := DiscoverScripts("/nonexistent/dir", "sig-test")
	if err == nil {
		t.Fatal("expected error for nonexistent directory")
	}
}

func TestParseManifest_EnvMerging(t *testing.T) {
	manifest := `{
		"defaults": {"env": {"A": "1", "B": "2"}},
		"tests": [
			{"name": "[sig-test] env test", "script": "a.sh", "env": {"B": "3", "C": "4"}}
		]
	}`

	specs, _, err := ParseManifest([]byte(manifest), ".")
	if err != nil {
		t.Fatal(err)
	}

	// We can't inspect env directly from specs, but we can verify via a ShellTest roundtrip.
	// Instead, test ParseManifest's internal ShellTest construction by parsing and checking BuildSpecs output.
	// The env is only visible at runtime, so verify ParseManifest doesn't error.
	if len(specs) != 1 {
		t.Fatalf("expected 1 spec, got %d", len(specs))
	}
}

func TestParseManifest_StepRegistryMetadata(t *testing.T) {
	manifest := `{
		"defaults": {"cluster_profile": "aws"},
		"tests": [
			{
				"name": "[sig-test] ci test", "script": "a.sh",
				"from_image": "registry.ci.openshift.org/ocp/4.17:tests",
				"credentials": [{"namespace": "test-creds", "name": "cloud", "mount_path": "/var/run/cloud"}],
				"cluster_profile": "gcp"
			}
		]
	}`

	specs, _, err := ParseManifest([]byte(manifest), ".")
	if err != nil {
		t.Fatal(err)
	}
	if len(specs) != 1 {
		t.Fatalf("expected 1 spec, got %d", len(specs))
	}
}

func TestParseManifest_BackwardCompatibility(t *testing.T) {
	manifest := `{
		"defaults": {"tags": {"product": "quay"}, "lifecycle": "blocking"},
		"tests": [
			{"name": "[sig-test] basic", "script": "a.sh", "labels": ["SMOKE"]}
		]
	}`

	specs, _, err := ParseManifest([]byte(manifest), ".")
	if err != nil {
		t.Fatal(err)
	}
	if len(specs) != 1 {
		t.Fatalf("expected 1 spec, got %d", len(specs))
	}
	if specs[0].Tags["product"] != "quay" {
		t.Errorf("expected product tag, got %v", specs[0].Tags)
	}
	if !specs[0].Labels.Has("SMOKE") {
		t.Error("expected SMOKE label")
	}
}

func TestHumanize(t *testing.T) {
	cases := []struct {
		input, expected string
	}{
		{"check-dns-resolution", "check dns resolution"},
		{"validate_tls_certs", "validate tls certs"},
		{"simple", "simple"},
		{"mixed-dash_underscore", "mixed dash underscore"},
	}

	for _, tc := range cases {
		got := humanize(tc.input)
		if got != tc.expected {
			t.Errorf("humanize(%q) = %q, want %q", tc.input, got, tc.expected)
		}
	}
}

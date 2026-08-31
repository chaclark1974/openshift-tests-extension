package shell

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	et "github.com/openshift-eng/openshift-tests-extension/pkg/extension/extensiontests"
)

// TestManifest is the top-level structure of a tests.json file.
type TestManifest struct {
	Defaults TestDefaults `json:"defaults,omitempty"`
	Tests    []TestEntry  `json:"tests"`
	Suites   []SuiteEntry `json:"suites,omitempty"`
}

// TestDefaults are applied to every test unless overridden.
type TestDefaults struct {
	Labels         []string          `json:"labels,omitempty"`
	Tags           map[string]string `json:"tags,omitempty"`
	Lifecycle      string            `json:"lifecycle,omitempty"`
	Timeout        string            `json:"timeout,omitempty"`
	Env            map[string]string `json:"env,omitempty"`
	ClusterProfile string            `json:"cluster_profile,omitempty"`
}

// TestEntry declares a single shell test.
type TestEntry struct {
	Name           string            `json:"name"`
	Script         string            `json:"script"`
	Labels         []string          `json:"labels,omitempty"`
	Tags           map[string]string `json:"tags,omitempty"`
	Lifecycle      string            `json:"lifecycle,omitempty"`
	Include        string            `json:"include,omitempty"`
	Exclude        string            `json:"exclude,omitempty"`
	Timeout        string            `json:"timeout,omitempty"`
	Env            map[string]string `json:"env,omitempty"`
	FromImage      string            `json:"from_image,omitempty"`
	Credentials    []CredentialRef   `json:"credentials,omitempty"`
	ClusterProfile string            `json:"cluster_profile,omitempty"`
}

// CredentialRef declares a credential mount that a test requires.
type CredentialRef struct {
	Namespace string `json:"namespace"`
	Name      string `json:"name"`
	MountPath string `json:"mount_path"`
}

// SuiteEntry declares a suite in the manifest.
type SuiteEntry struct {
	Name        string   `json:"name"`
	Description string   `json:"description,omitempty"`
	Qualifiers  []string `json:"qualifiers,omitempty"`
	Parents     []string `json:"parents,omitempty"`
	Parallelism int      `json:"parallelism,omitempty"`
	TestTimeout string   `json:"testTimeout,omitempty"`
}

// LoadManifest reads a tests.json file and returns ExtensionTestSpecs and SuiteEntries.
func LoadManifest(path string) (et.ExtensionTestSpecs, []SuiteEntry, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, fmt.Errorf("reading manifest %s: %w", path, err)
	}

	return ParseManifest(data, filepath.Dir(path))
}

// ParseManifest parses manifest JSON bytes and returns specs and suite entries.
// scriptBaseDir is used to resolve relative script paths.
func ParseManifest(data []byte, scriptBaseDir string) (et.ExtensionTestSpecs, []SuiteEntry, error) {
	var manifest TestManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return nil, nil, fmt.Errorf("parsing manifest: %w", err)
	}

	defaultTimeout, err := parseOptionalDuration(manifest.Defaults.Timeout)
	if err != nil {
		return nil, nil, fmt.Errorf("invalid defaults.timeout %q: %w", manifest.Defaults.Timeout, err)
	}

	var tests []ShellTest

	for i, entry := range manifest.Tests {
		if entry.Name == "" {
			return nil, nil, fmt.Errorf("test at index %d: name is required", i)
		}
		if entry.Script == "" {
			return nil, nil, fmt.Errorf("test %q: script is required", entry.Name)
		}

		t := ShellTest{
			Name:       entry.Name,
			ScriptPath: filepath.Join(scriptBaseDir, entry.Script),
		}

		t.Labels = append(t.Labels, manifest.Defaults.Labels...)
		t.Labels = append(t.Labels, entry.Labels...)

		t.Tags = make(map[string]string)
		for k, v := range manifest.Defaults.Tags {
			t.Tags[k] = v
		}
		for k, v := range entry.Tags {
			t.Tags[k] = v
		}

		lifecycle := manifest.Defaults.Lifecycle
		if entry.Lifecycle != "" {
			lifecycle = entry.Lifecycle
		}
		switch lifecycle {
		case "informing":
			t.Lifecycle = et.LifecycleInforming
		default:
			t.Lifecycle = et.LifecycleBlocking
		}

		timeoutStr := entry.Timeout
		if timeoutStr == "" {
			timeoutStr = manifest.Defaults.Timeout
		}
		if timeoutStr != "" {
			dur, err := time.ParseDuration(timeoutStr)
			if err != nil {
				return nil, nil, fmt.Errorf("test %q: invalid timeout %q: %w", entry.Name, timeoutStr, err)
			}
			t.Timeout = dur
		} else {
			t.Timeout = defaultTimeout
		}

		t.Include = entry.Include
		t.Exclude = entry.Exclude

		t.Env = make(map[string]string)
		for k, v := range manifest.Defaults.Env {
			t.Env[k] = v
		}
		for k, v := range entry.Env {
			t.Env[k] = v
		}

		t.FromImage = entry.FromImage
		t.Credentials = entry.Credentials
		clusterProfile := manifest.Defaults.ClusterProfile
		if entry.ClusterProfile != "" {
			clusterProfile = entry.ClusterProfile
		}
		t.ClusterProfile = clusterProfile

		tests = append(tests, t)
	}

	return BuildSpecs(tests), manifest.Suites, nil
}

// DiscoverScripts scans a directory for .sh files and creates one test per script.
func DiscoverScripts(dir, sigPrefix string) (et.ExtensionTestSpecs, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("reading script directory %s: %w", dir, err)
	}

	var tests []ShellTest
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if filepath.Ext(name) != ".sh" {
			continue
		}

		baseName := name[:len(name)-len(".sh")]
		testName := fmt.Sprintf("[%s] %s", sigPrefix, humanize(baseName))

		tests = append(tests, ShellTest{
			Name:       testName,
			ScriptPath: filepath.Join(dir, name),
		})
	}

	if len(tests) == 0 {
		return nil, fmt.Errorf("no .sh files found in %s", dir)
	}

	return BuildSpecs(tests), nil
}

func humanize(s string) string {
	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		if s[i] == '-' || s[i] == '_' {
			out = append(out, ' ')
		} else {
			out = append(out, s[i])
		}
	}
	return string(out)
}

func parseOptionalDuration(s string) (time.Duration, error) {
	if s == "" {
		return 0, nil
	}
	return time.ParseDuration(s)
}

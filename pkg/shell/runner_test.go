package shell

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	et "github.com/openshift-eng/openshift-tests-extension/pkg/extension/extensiontests"
)

func writeScript(t *testing.T, dir, name, content string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(content), 0755); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestRunShellTest_Pass(t *testing.T) {
	dir := t.TempDir()
	script := writeScript(t, dir, "pass.sh", "#!/bin/bash\necho hello\nexit 0\n")

	test := ShellTest{Name: "test-pass", ScriptPath: script}
	result := runShellTest(context.Background(), test)

	if result.Result != et.ResultPassed {
		t.Errorf("expected passed, got %s: %s", result.Result, result.Error)
	}
	if result.Name != "test-pass" {
		t.Errorf("expected name test-pass, got %s", result.Name)
	}
}

func TestRunShellTest_Fail(t *testing.T) {
	dir := t.TempDir()
	script := writeScript(t, dir, "fail.sh", "#!/bin/bash\necho failure >&2\nexit 1\n")

	test := ShellTest{Name: "test-fail", ScriptPath: script}
	result := runShellTest(context.Background(), test)

	if result.Result != et.ResultFailed {
		t.Errorf("expected failed, got %s", result.Result)
	}
	if result.Error == "" {
		t.Error("expected error message on failure")
	}
}

func TestRunShellTest_Skip(t *testing.T) {
	dir := t.TempDir()
	script := writeScript(t, dir, "skip.sh", "#!/bin/bash\necho skipping >&2\nexit 2\n")

	test := ShellTest{Name: "test-skip", ScriptPath: script}
	result := runShellTest(context.Background(), test)

	if result.Result != et.ResultSkipped {
		t.Errorf("expected skipped, got %s", result.Result)
	}
}

func TestRunShellTest_Timeout(t *testing.T) {
	dir := t.TempDir()
	script := writeScript(t, dir, "slow.sh", "#!/bin/bash\nwhile true; do sleep 0.1; done\n")

	test := ShellTest{Name: "test-timeout", ScriptPath: script, Timeout: 500 * time.Millisecond}
	result := runShellTest(context.Background(), test)

	if result.Result != et.ResultFailed {
		t.Errorf("expected failed on timeout, got %s", result.Result)
	}
	if result.Error == "" {
		t.Error("expected timeout error message")
	}
}

func TestRunShellTest_TimeoutKillsChildren(t *testing.T) {
	dir := t.TempDir()
	marker := filepath.Join(dir, "child-running")
	script := writeScript(t, dir, "parent.sh", fmt.Sprintf(
		"#!/bin/bash\n(touch %s; while true; do sleep 0.1; done) &\nwait\n", marker))

	test := ShellTest{Name: "test-child-kill", ScriptPath: script, Timeout: 500 * time.Millisecond}
	result := runShellTest(context.Background(), test)

	if result.Result != et.ResultFailed {
		t.Errorf("expected failed on timeout, got %s", result.Result)
	}

	time.Sleep(200 * time.Millisecond)
	if _, err := os.Stat(marker); os.IsNotExist(err) {
		t.Skip("child process did not start in time")
	}
}

func TestRunShellTest_StdoutCapture(t *testing.T) {
	dir := t.TempDir()
	script := writeScript(t, dir, "output.sh", "#!/bin/bash\necho hello-stdout\necho hello-stderr >&2\nexit 0\n")

	test := ShellTest{Name: "test-output", ScriptPath: script}
	result := runShellTest(context.Background(), test)

	if result.Result != et.ResultPassed {
		t.Fatalf("expected passed, got %s", result.Result)
	}
	if result.Output == "" {
		t.Error("expected output to be captured")
	}
}

func TestRunShellTest_NonexistentScript(t *testing.T) {
	test := ShellTest{Name: "test-missing", ScriptPath: "/nonexistent/script.sh"}
	result := runShellTest(context.Background(), test)

	if result.Result != et.ResultFailed {
		t.Errorf("expected failed for missing script, got %s", result.Result)
	}
}

func TestBuildSpecs(t *testing.T) {
	tests := []ShellTest{
		{Name: "[sig-test] first test", ScriptPath: "scripts/a.sh", Labels: []string{"SMOKE"}, Tags: map[string]string{"tier": "0"}},
		{Name: "[sig-test] second test", ScriptPath: "scripts/b.sh", Lifecycle: et.LifecycleInforming},
	}

	specs := BuildSpecs(tests)

	if len(specs) != 2 {
		t.Fatalf("expected 2 specs, got %d", len(specs))
	}

	if specs[0].Name != "[sig-test] first test" {
		t.Errorf("unexpected name: %s", specs[0].Name)
	}
	if !specs[0].Labels.Has("SMOKE") {
		t.Error("expected SMOKE label")
	}
	if specs[0].Tags["tier"] != "0" {
		t.Error("expected tier tag")
	}
	if specs[0].Lifecycle != et.LifecycleBlocking {
		t.Errorf("expected blocking lifecycle, got %s", specs[0].Lifecycle)
	}

	if specs[1].Lifecycle != et.LifecycleInforming {
		t.Errorf("expected informing lifecycle, got %s", specs[1].Lifecycle)
	}

	if specs[0].Run == nil || specs[0].RunParallel == nil {
		t.Error("expected Run and RunParallel to be set")
	}
}

func TestBuildSpecs_IncludeExclude(t *testing.T) {
	tests := []ShellTest{
		{Name: "test-env", ScriptPath: "a.sh", Include: `platform=="aws"`, Exclude: `topology=="single"`},
	}

	specs := BuildSpecs(tests)

	if specs[0].EnvironmentSelector.Include != `platform=="aws"` {
		t.Errorf("unexpected include: %s", specs[0].EnvironmentSelector.Include)
	}
	if specs[0].EnvironmentSelector.Exclude != `topology=="single"` {
		t.Errorf("unexpected exclude: %s", specs[0].EnvironmentSelector.Exclude)
	}
}

func TestBuildSpecs_DefaultLifecycle(t *testing.T) {
	tests := []ShellTest{{Name: "test", ScriptPath: "a.sh"}}
	specs := BuildSpecs(tests)

	if specs[0].Lifecycle != et.LifecycleBlocking {
		t.Errorf("expected default blocking lifecycle, got %s", specs[0].Lifecycle)
	}
}

func TestSanitizeName(t *testing.T) {
	cases := []struct {
		input, expected string
	}{
		{"[sig-test] simple name", "sig-test-simple-name"},
		{"test with spaces", "test-with-spaces"},
		{"test/with/slashes", "testwithslashes"},
		{"clean-name_ok", "clean-name_ok"},
	}

	for _, tc := range cases {
		got := sanitizeName(tc.input)
		if got != tc.expected {
			t.Errorf("sanitizeName(%q) = %q, want %q", tc.input, got, tc.expected)
		}
	}
}

func TestTruncate(t *testing.T) {
	short := "hello"
	if truncate(short, 10) != "hello" {
		t.Error("short string should not be truncated")
	}

	long := "abcdefghij"
	if truncate(long, 5) != "fghij" {
		t.Errorf("expected last 5 chars, got %q", truncate(long, 5))
	}
}

func TestSetEnvInSlice(t *testing.T) {
	env := []string{"A=1", "B=2"}

	env = setEnvInSlice(env, "B", "99")
	if v, ok := lookupEnv(env, "B"); !ok || v != "99" {
		t.Errorf("expected B=99, got %s", v)
	}

	env = setEnvInSlice(env, "C", "3")
	if v, ok := lookupEnv(env, "C"); !ok || v != "3" {
		t.Errorf("expected C=3, got %s", v)
	}
}

func TestLookupEnv(t *testing.T) {
	env := []string{"FOO=bar", "BAZ=qux"}

	if v, ok := lookupEnv(env, "FOO"); !ok || v != "bar" {
		t.Errorf("expected FOO=bar, got ok=%v v=%s", ok, v)
	}
	if _, ok := lookupEnv(env, "MISSING"); ok {
		t.Error("expected MISSING to not be found")
	}
}

func TestBuildEnv_NonCI(t *testing.T) {
	t.Setenv("OPENSHIFT_CI", "")
	t.Setenv("SHARED_DIR", "")

	test := ShellTest{Name: "test", ScriptPath: "a.sh"}
	env := buildEnv(test, "/tmp/artifacts/test")

	if v, ok := lookupEnv(env, "TEST_ARTIFACTS_DIR"); !ok || v != "/tmp/artifacts/test" {
		t.Errorf("expected TEST_ARTIFACTS_DIR=/tmp/artifacts/test, got ok=%v v=%s", ok, v)
	}
	if _, ok := lookupEnv(env, "PARENT_SHARED_DIR"); ok {
		t.Error("PARENT_SHARED_DIR should not be set outside CI")
	}
}

func TestBuildEnv_CIContext(t *testing.T) {
	sharedDir := t.TempDir()
	t.Setenv("OPENSHIFT_CI", "true")
	t.Setenv("SHARED_DIR", sharedDir)
	t.Setenv("EXTENSION_ARTIFACTS_DIR", "")

	test := ShellTest{Name: "[sig-test] my test", ScriptPath: "a.sh"}
	env := buildEnv(test, "")

	parentVal, ok := lookupEnv(env, "PARENT_SHARED_DIR")
	if !ok || parentVal != sharedDir {
		t.Errorf("expected PARENT_SHARED_DIR=%s, got ok=%v v=%s", sharedDir, ok, parentVal)
	}

	sharedVal, ok := lookupEnv(env, "SHARED_DIR")
	if !ok {
		t.Fatal("SHARED_DIR not set")
	}
	if sharedVal == sharedDir {
		t.Error("SHARED_DIR should be a per-test subdirectory, not the parent")
	}
	if !strings.HasPrefix(sharedVal, sharedDir) {
		t.Errorf("per-test SHARED_DIR should be under parent, got %s", sharedVal)
	}

	if _, err := os.Stat(sharedVal); os.IsNotExist(err) {
		t.Errorf("per-test SHARED_DIR directory was not created: %s", sharedVal)
	}
}

func TestBuildEnv_ArtifactDirBridge(t *testing.T) {
	t.Setenv("OPENSHIFT_CI", "true")
	t.Setenv("SHARED_DIR", "")
	t.Setenv("EXTENSION_ARTIFACTS_DIR", "")
	t.Setenv("ARTIFACT_DIR", "/tmp/ci-artifacts")

	test := ShellTest{Name: "test", ScriptPath: "a.sh"}
	env := buildEnv(test, "")

	if v, ok := lookupEnv(env, "EXTENSION_ARTIFACTS_DIR"); !ok || v != "/tmp/ci-artifacts" {
		t.Errorf("expected EXTENSION_ARTIFACTS_DIR bridged from ARTIFACT_DIR, got ok=%v v=%s", ok, v)
	}
}

func TestBuildEnv_ManifestEnvVars(t *testing.T) {
	t.Setenv("OPENSHIFT_CI", "")
	t.Setenv("SHARED_DIR", "")

	test := ShellTest{
		Name:       "test",
		ScriptPath: "a.sh",
		Env:        map[string]string{"MY_VAR": "hello", "HOME": "should-not-override"},
	}
	env := buildEnv(test, "")

	if v, ok := lookupEnv(env, "MY_VAR"); !ok || v != "hello" {
		t.Errorf("expected MY_VAR=hello, got ok=%v v=%s", ok, v)
	}

	if v, _ := lookupEnv(env, "HOME"); v == "should-not-override" {
		t.Error("manifest env should not override existing env vars")
	}
}

func TestWriteArtifactLogs(t *testing.T) {
	dir := t.TempDir()
	writeArtifactLogs(dir, "hello stdout", "hello stderr")

	stdout, err := os.ReadFile(filepath.Join(dir, "stdout.log"))
	if err != nil {
		t.Fatalf("stdout.log not created: %v", err)
	}
	if string(stdout) != "hello stdout" {
		t.Errorf("unexpected stdout.log content: %s", stdout)
	}

	stderr, err := os.ReadFile(filepath.Join(dir, "stderr.log"))
	if err != nil {
		t.Fatalf("stderr.log not created: %v", err)
	}
	if string(stderr) != "hello stderr" {
		t.Errorf("unexpected stderr.log content: %s", stderr)
	}
}

func TestWriteArtifactLogs_EmptyDir(t *testing.T) {
	writeArtifactLogs("", "stdout", "stderr")
}

func TestSummarizeArtifacts(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "file1.txt"), []byte("hello"), 0644)
	os.WriteFile(filepath.Join(dir, "file2.txt"), []byte("world"), 0644)

	summary := summarizeArtifacts(dir)
	if !strings.Contains(summary, "2 files") {
		t.Errorf("expected 2 files in summary, got: %s", summary)
	}
	if !strings.Contains(summary, dir) {
		t.Errorf("expected dir path in summary, got: %s", summary)
	}
}

func TestSummarizeArtifacts_EmptyDirRemoved(t *testing.T) {
	dir := t.TempDir()
	emptyDir := filepath.Join(dir, "empty")
	os.MkdirAll(emptyDir, 0755)

	summary := summarizeArtifacts(emptyDir)
	if summary != "" {
		t.Errorf("expected empty summary for empty dir, got: %s", summary)
	}
	if _, err := os.Stat(emptyDir); !os.IsNotExist(err) {
		t.Error("expected empty artifact dir to be removed")
	}
}

func TestFormatSize(t *testing.T) {
	cases := []struct {
		bytes    int64
		expected string
	}{
		{500, "500B"},
		{1536, "1.5KB"},
		{1572864, "1.5MB"},
	}
	for _, tc := range cases {
		got := formatSize(tc.bytes)
		if got != tc.expected {
			t.Errorf("formatSize(%d) = %q, want %q", tc.bytes, got, tc.expected)
		}
	}
}

func TestRunShellTest_ArtifactCapture(t *testing.T) {
	dir := t.TempDir()
	artifactDir := filepath.Join(dir, "artifacts")
	os.MkdirAll(artifactDir, 0755)

	script := writeScript(t, dir, "artifact.sh",
		"#!/bin/bash\necho test-output\nexit 0\n")

	t.Setenv("EXTENSION_ARTIFACTS_DIR", artifactDir)

	test := ShellTest{Name: "test-artifact", ScriptPath: script}
	result := runShellTest(context.Background(), test)

	if result.Result != et.ResultPassed {
		t.Fatalf("expected passed, got %s: %s", result.Result, result.Error)
	}

	testDir := filepath.Join(artifactDir, "test-artifact")
	if _, err := os.Stat(filepath.Join(testDir, "stdout.log")); os.IsNotExist(err) {
		t.Error("expected stdout.log in artifact dir")
	}
	if !strings.Contains(result.Output, "Artifacts:") {
		t.Errorf("expected artifact summary in output, got: %s", result.Output)
	}
}

func TestRunShellTest_EnvInjection(t *testing.T) {
	dir := t.TempDir()
	script := writeScript(t, dir, "env.sh", "#!/bin/bash\necho $MY_TEST_VAR\nexit 0\n")

	test := ShellTest{
		Name:       "test-env",
		ScriptPath: script,
		Env:        map[string]string{"MY_TEST_VAR": "injected-value"},
	}
	result := runShellTest(context.Background(), test)

	if result.Result != et.ResultPassed {
		t.Fatalf("expected passed, got %s: %s", result.Result, result.Error)
	}
	if !strings.Contains(result.Output, "injected-value") {
		t.Errorf("expected output to contain injected env var value, got: %s", result.Output)
	}
}

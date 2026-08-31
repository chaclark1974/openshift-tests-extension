package shell

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/openshift-eng/openshift-tests-extension/pkg/dbtime"
	et "github.com/openshift-eng/openshift-tests-extension/pkg/extension/extensiontests"
	"github.com/openshift-eng/openshift-tests-extension/pkg/util/sets"
)

// ShellTest defines a single shell-based test.
type ShellTest struct {
	Name           string
	ScriptPath     string
	Labels         []string
	Tags           map[string]string
	Lifecycle      et.Lifecycle
	Include        string
	Exclude        string
	Timeout        time.Duration
	Env            map[string]string
	FromImage      string
	Credentials    []CredentialRef
	ClusterProfile string
}

// BuildSpecs converts ShellTest definitions into ExtensionTestSpecs.
func BuildSpecs(tests []ShellTest) et.ExtensionTestSpecs {
	var specs []*et.ExtensionTestSpec

	for _, t := range tests {
		test := t
		lifecycle := test.Lifecycle
		if lifecycle == "" {
			lifecycle = et.LifecycleBlocking
		}

		spec := &et.ExtensionTestSpec{
			Name:          test.Name,
			Labels:        sets.New(test.Labels...),
			Tags:          test.Tags,
			Lifecycle:     lifecycle,
			CodeLocations: []string{test.ScriptPath},
			Timeout:       test.Timeout,
			Run: func(ctx context.Context) *et.ExtensionTestResult {
				return runShellTest(ctx, test)
			},
			RunParallel: func(ctx context.Context) *et.ExtensionTestResult {
				return runShellTest(ctx, test)
			},
		}

		if test.Include != "" {
			spec.Include(test.Include)
		}
		if test.Exclude != "" {
			spec.Exclude(test.Exclude)
		}

		specs = append(specs, spec)
	}

	return specs
}

func runShellTest(ctx context.Context, test ShellTest) *et.ExtensionTestResult {
	timeout := test.Timeout
	if timeout == 0 {
		timeout = 30 * time.Minute
	}

	testCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	start := time.Now()
	stdout := &bytes.Buffer{}
	stderr := &bytes.Buffer{}

	cmd := exec.Command("bash", test.ScriptPath)
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	artifactsDir := os.Getenv("EXTENSION_ARTIFACTS_DIR")
	if artifactsDir == "" && isOpenShiftCI() {
		artifactsDir = os.Getenv("ARTIFACT_DIR")
	}

	testArtifactDir := ""
	if artifactsDir != "" {
		slug := sanitizeName(test.Name)
		testArtifactDir = filepath.Join(artifactsDir, slug)
		_ = os.MkdirAll(testArtifactDir, 0755)
	}

	cmd.Env = buildEnv(test, testArtifactDir)

	err := cmd.Start()
	if err != nil {
		end := time.Now()
		return buildResult(test.Name, et.ResultFailed, start, end,
			fmt.Sprintf("failed to start script: %v", err),
			stdout.String(), stderr.String(), "")
	}

	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()

	select {
	case err = <-done:
	case <-testCtx.Done():
		if cmd.Process != nil {
			pid := cmd.Process.Pid
			_ = syscall.Kill(-pid, syscall.SIGINT)
			select {
			case <-done:
			case <-time.After(5 * time.Second):
				_ = syscall.Kill(-pid, syscall.SIGABRT)
				select {
				case <-done:
				case <-time.After(5 * time.Second):
					_ = syscall.Kill(-pid, syscall.SIGKILL)
					<-done
				}
			}
		}
		end := time.Now()
		stdoutStr := stdout.String()
		stderrStr := stderr.String()
		writeArtifactLogs(testArtifactDir, stdoutStr, stderrStr)
		artifactSummary := summarizeArtifacts(testArtifactDir)
		return buildResult(test.Name, et.ResultFailed, start, end,
			fmt.Sprintf("test timed out after %s", timeout),
			stdoutStr, stderrStr, artifactSummary)
	}

	end := time.Now()
	stdoutStr := stdout.String()
	stderrStr := stderr.String()

	writeArtifactLogs(testArtifactDir, stdoutStr, stderrStr)
	artifactSummary := summarizeArtifacts(testArtifactDir)

	if err == nil {
		return buildResult(test.Name, et.ResultPassed, start, end, "", stdoutStr, stderrStr, artifactSummary)
	}

	if exitErr, ok := err.(*exec.ExitError); ok {
		if exitErr.ExitCode() == 2 {
			return buildResult(test.Name, et.ResultSkipped, start, end, stderrStr, stdoutStr, stderrStr, artifactSummary)
		}
	}

	errMsg := stderrStr
	if errMsg == "" {
		errMsg = stdoutStr
	}
	return buildResult(test.Name, et.ResultFailed, start, end, errMsg, stdoutStr, stderrStr, artifactSummary)
}

func buildResult(name string, result et.Result, start, end time.Time, errMsg, stdoutStr, stderrStr, artifactSummary string) *et.ExtensionTestResult {
	duration := end.Sub(start)
	dbStart := dbtime.DBTime(start)
	dbEnd := dbtime.DBTime(end)

	output := fmt.Sprintf("STDOUT:\n%s\nSTDERR:\n%s", stdoutStr, stderrStr)
	if artifactSummary != "" {
		output += "\n" + artifactSummary
	}

	r := &et.ExtensionTestResult{
		Name:      name,
		Duration:  int64(duration),
		StartTime: &dbStart,
		EndTime:   &dbEnd,
		Result:    result,
		Output:    output,
	}
	if errMsg != "" {
		r.Error = truncate(errMsg, 5000)
	}
	return r
}

func writeArtifactLogs(artifactDir, stdoutStr, stderrStr string) {
	if artifactDir == "" {
		return
	}
	_ = os.WriteFile(filepath.Join(artifactDir, "stdout.log"), []byte(stdoutStr), 0644)
	_ = os.WriteFile(filepath.Join(artifactDir, "stderr.log"), []byte(stderrStr), 0644)
}

func summarizeArtifacts(artifactDir string) string {
	if artifactDir == "" {
		return ""
	}
	var count int
	var totalSize int64
	_ = filepath.Walk(artifactDir, func(_ string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		count++
		totalSize += info.Size()
		return nil
	})
	if count == 0 {
		_ = os.Remove(artifactDir)
		return ""
	}
	return fmt.Sprintf("Artifacts: %d files, %s in %s", count, formatSize(totalSize), artifactDir)
}

func formatSize(bytes int64) string {
	switch {
	case bytes >= 1<<20:
		return fmt.Sprintf("%.1fMB", float64(bytes)/float64(1<<20))
	case bytes >= 1<<10:
		return fmt.Sprintf("%.1fKB", float64(bytes)/float64(1<<10))
	default:
		return fmt.Sprintf("%dB", bytes)
	}
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[len(s)-maxLen:]
}

func isOpenShiftCI() bool {
	return os.Getenv("OPENSHIFT_CI") == "true" || os.Getenv("SHARED_DIR") != ""
}

func buildEnv(test ShellTest, testArtifactDir string) []string {
	env := os.Environ()

	if testArtifactDir != "" {
		env = append(env, fmt.Sprintf("TEST_ARTIFACTS_DIR=%s", testArtifactDir))
	}

	if isOpenShiftCI() {
		parentSharedDir := os.Getenv("SHARED_DIR")
		if parentSharedDir != "" {
			slug := sanitizeName(test.Name)
			perTestSharedDir := filepath.Join(parentSharedDir, slug)
			_ = os.MkdirAll(perTestSharedDir, 0755)
			env = setEnvInSlice(env, "PARENT_SHARED_DIR", parentSharedDir)
			env = setEnvInSlice(env, "SHARED_DIR", perTestSharedDir)
		}

		if os.Getenv("EXTENSION_ARTIFACTS_DIR") == "" && os.Getenv("ARTIFACT_DIR") != "" {
			env = setEnvInSlice(env, "EXTENSION_ARTIFACTS_DIR", os.Getenv("ARTIFACT_DIR"))
		}
	}

	for k, v := range test.Env {
		if _, exists := lookupEnv(env, k); !exists {
			env = append(env, fmt.Sprintf("%s=%s", k, v))
		}
	}

	return env
}

func setEnvInSlice(env []string, key, value string) []string {
	prefix := key + "="
	for i, e := range env {
		if strings.HasPrefix(e, prefix) {
			env[i] = prefix + value
			return env
		}
	}
	return append(env, prefix+value)
}

func lookupEnv(env []string, key string) (string, bool) {
	prefix := key + "="
	for _, e := range env {
		if strings.HasPrefix(e, prefix) {
			return e[len(prefix):], true
		}
	}
	return "", false
}

func sanitizeName(name string) string {
	out := make([]byte, 0, len(name))
	for i := 0; i < len(name); i++ {
		c := name[i]
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9', c == '-', c == '_':
			out = append(out, c)
		case c == ' ':
			out = append(out, '-')
		}
	}
	return string(out)
}

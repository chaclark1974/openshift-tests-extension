// Package adapter is a generic, exec-based OTE adapter: it turns a JSON list of
// ScenarioSpec entries into OTE ExtensionTestSpecs, running each scenario as a
// subprocess. There is no per-product or per-plugin branching — every scenario
// is just a command to exec, with tags/labels/lifecycle/env-gating from JSON.
//
// This is the scenario-JSON-driven model (cf. chaos-tests-extension's pkg/krkn).
package adapter

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path"
	"time"

	"github.com/openshift-eng/openshift-tests-extension/pkg/dbtime"
	et "github.com/openshift-eng/openshift-tests-extension/pkg/extension/extensiontests"
	"github.com/openshift-eng/openshift-tests-extension/pkg/util/sets"
)

// ScenarioSpec is one test, defined entirely in JSON.
type ScenarioSpec struct {
	Name     string   `json:"name"`               // OTE test name, e.g. "[sig-acm-policy] ..."
	Product  string   `json:"product"`            // routes the spec to an extension (acm|quay|acs|odf)
	Category string   `json:"category,omitempty"` // -> tags["category"] (functional area)
	Labels   []string `json:"labels,omitempty"`   // scenario/depth labels, e.g. OPP, ACM-VIRT, SMOKE

	// Tags are arbitrary extra key/value tags merged into the spec's tags
	// (e.g. {"tier":"0","owner":"interop-qe"}). "product" and "category" are
	// reserved and always win over anything set here.
	Tags map[string]string `json:"tags,omitempty"`

	Lifecycle string `json:"lifecycle,omitempty"` // "informing" | "blocking" (default blocking)
	Timeout   string `json:"timeout,omitempty"`   // Go duration, e.g. "30m"
	Include   string `json:"include,omitempty"`   // CEL env gate, e.g. platform=="aws"

	// Execution.
	Command     []string          `json:"command"`                  // argv; Command[0] is the binary
	Env         map[string]string `json:"env,omitempty"`            // extra env for the subprocess
	WorkDir     string            `json:"workDir,omitempty"`        // cwd for the subprocess
	SkipIfUnset []string          `json:"skipIfEnvUnset,omitempty"` // skip if any of these env vars is unset
}

// Manifest is the top-level JSON structure (interop_scenarios.json).
type Manifest struct {
	Scenarios []ScenarioSpec `json:"scenarios"`
}

// BuildSpecsByProductFS walks a filesystem (e.g. the embedded per-product
// scenario tree), merges every *.json manifest it finds, and returns specs
// grouped by product. Each product's directory owns its scenarios.json.
func BuildSpecsByProductFS(fsys fs.FS) (map[string]et.ExtensionTestSpecs, error) {
	var merged []ScenarioSpec
	err := fs.WalkDir(fsys, ".", func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || path.Ext(p) != ".json" {
			return nil
		}
		b, err := fs.ReadFile(fsys, p)
		if err != nil {
			return fmt.Errorf("reading %s: %w", p, err)
		}
		var m Manifest
		if err := json.Unmarshal(b, &m); err != nil {
			return fmt.Errorf("parsing %s: %w", p, err)
		}
		merged = append(merged, m.Scenarios...)
		return nil
	})
	if err != nil {
		return nil, err
	}
	return buildSpecs(merged)
}

// BuildSpecsByProduct parses a single manifest and returns specs grouped by product.
func BuildSpecsByProduct(data []byte) (map[string]et.ExtensionTestSpecs, error) {
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("parsing scenarios manifest: %w", err)
	}
	return buildSpecs(m.Scenarios)
}

func buildSpecs(scenarios []ScenarioSpec) (map[string]et.ExtensionTestSpecs, error) {
	out := map[string]et.ExtensionTestSpecs{}
	seen := map[string]bool{}
	for i := range scenarios {
		sc := scenarios[i]
		if sc.Name == "" {
			return nil, fmt.Errorf("scenario %d: name is required", i)
		}
		if sc.Product == "" {
			return nil, fmt.Errorf("scenario %q: product is required", sc.Name)
		}
		if len(sc.Command) == 0 {
			return nil, fmt.Errorf("scenario %q: command is required", sc.Name)
		}
		if seen[sc.Name] {
			return nil, fmt.Errorf("duplicate scenario name %q", sc.Name)
		}
		seen[sc.Name] = true

		spec, err := toSpec(sc)
		if err != nil {
			return nil, fmt.Errorf("scenario %q: %w", sc.Name, err)
		}
		out[sc.Product] = append(out[sc.Product], spec)
	}
	return out, nil
}

func toSpec(sc ScenarioSpec) (*et.ExtensionTestSpec, error) {
	tags := map[string]string{}
	for k, v := range sc.Tags { // arbitrary extra tags from JSON
		tags[k] = v
	}
	tags["product"] = sc.Product // reserved: always authoritative
	if sc.Category != "" {
		tags["category"] = sc.Category
	}

	var timeout time.Duration
	if sc.Timeout != "" {
		d, err := time.ParseDuration(sc.Timeout)
		if err != nil {
			return nil, fmt.Errorf("invalid timeout %q: %w", sc.Timeout, err)
		}
		timeout = d
	}

	scCopy := sc // capture by value for the closure
	run := func(ctx context.Context) *et.ExtensionTestResult {
		return runScenario(ctx, scCopy)
	}

	spec := &et.ExtensionTestSpec{
		Name:        sc.Name,
		Labels:      sets.New(sc.Labels...),
		Tags:        tags,
		Lifecycle:   lifecycle(sc.Lifecycle),
		Timeout:     timeout,
		Run:         run,
		RunParallel: run,
	}
	if sc.Include != "" {
		spec.Include(sc.Include) // environment gating (CEL)
	}
	return spec, nil
}

func lifecycle(s string) et.Lifecycle {
	if s == "informing" {
		return et.LifecycleInforming
	}
	return et.LifecycleBlocking
}

// runScenario execs the scenario's command and maps the outcome to an OTE result.
func runScenario(ctx context.Context, sc ScenarioSpec) *et.ExtensionTestResult {
	start := time.Now()

	// Skip if a required env var is missing.
	for _, k := range sc.SkipIfUnset {
		if os.Getenv(k) == "" {
			return result(sc, start, time.Now(), et.ResultSkipped,
				fmt.Sprintf("%s not set; skipping", k), "")
		}
	}

	runCtx := ctx
	if sc.Timeout != "" {
		if d, err := time.ParseDuration(sc.Timeout); err == nil {
			var cancel context.CancelFunc
			runCtx, cancel = context.WithTimeout(ctx, d)
			defer cancel()
		}
	}

	cmd := exec.CommandContext(runCtx, sc.Command[0], sc.Command[1:]...)
	cmd.Dir = sc.WorkDir
	cmd.Env = os.Environ()
	for k, v := range sc.Env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}

	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf

	res := et.ResultPassed
	errMsg := ""
	if err := cmd.Run(); err != nil {
		res = et.ResultFailed
		errMsg = err.Error()
	}
	return result(sc, start, time.Now(), res, buf.String(), errMsg)
}

func result(sc ScenarioSpec, start, end time.Time, res et.Result, output, errMsg string) *et.ExtensionTestResult {
	s := dbtime.DBTime(start)
	e := dbtime.DBTime(end)
	r := &et.ExtensionTestResult{
		Name:      sc.Name,
		Lifecycle: lifecycle(sc.Lifecycle),
		Duration:  int64(end.Sub(start)),
		StartTime: &s,
		EndTime:   &e,
		Result:    res,
		Output:    output,
	}
	if errMsg != "" {
		r.Error = errMsg
	}
	return r
}

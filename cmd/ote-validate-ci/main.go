package main

import (
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/openshift-eng/openshift-tests-extension/pkg/shell"
	"github.com/openshift-eng/openshift-tests-extension/pkg/shell/stepregistry"
	"gopkg.in/yaml.v3"
)

type componentDef struct {
	Name      string
	Dir       string
	Binary    string
	OrgRepo   string
	CIStepDir string
}

var components = []componentDef{
	{Name: "cnv", Dir: "cnv-tests", Binary: "cnv-tests", OrgRepo: "openshift/cnv-tests", CIStepDir: "cnv"},
	{Name: "virt", Dir: "virt-tests", Binary: "virt-tests", OrgRepo: "openshift/virt-tests", CIStepDir: "kubevirt"},
	{Name: "opp", Dir: "opp-tests", Binary: "opp-tests", OrgRepo: "openshift/opp-tests", CIStepDir: "acm"},
	{Name: "policy-collection", Dir: "stolostron-policy-collection", Binary: "stolostron-policy-collection", OrgRepo: "stolostron/policy-collection", CIStepDir: "acm"},
	{Name: "interop", Dir: "interop-tests", Binary: "interop-tests", OrgRepo: "RedHatQE/interop-testing", CIStepDir: "interop-tests"},
}

func main() {
	component := flag.String("component", "", "Component name: cnv, virt, opp, policy-collection, interop")
	all := flag.Bool("all", false, "Validate all known components")
	ciPath := flag.String("ci-path", "", "Local path to CI step-registry directory (e.g., from cloned openshift/release)")
	ciRepo := flag.String("ci-repo", "", "GitHub repo for upstream CI refs via gh api (e.g., openshift/release or full URL)")
	flag.Parse()

	*ciRepo = normalizeRepo(*ciRepo)

	if !*all && *component == "" {
		fmt.Fprintln(os.Stderr, "Error: specify --component <name> or --all")
		fmt.Fprintln(os.Stderr, "  Components: cnv, virt, opp, policy-collection, interop")
		os.Exit(1)
	}

	var targets []componentDef
	if *all {
		targets = components
	} else {
		comp := findComponent(*component)
		if comp == nil {
			fmt.Fprintf(os.Stderr, "Error: unknown component %q\n", *component)
			fmt.Fprintln(os.Stderr, "  Valid: cnv, virt, opp, policy-collection, interop")
			os.Exit(1)
		}
		targets = []componentDef{*comp}
	}

	totalFail := 0
	for i, comp := range targets {
		if i > 0 {
			fmt.Println()
		}
		failures := validateComponent(comp, *ciPath, *ciRepo)
		totalFail += failures
	}

	if totalFail > 0 {
		os.Exit(1)
	}
}

func findComponent(name string) *componentDef {
	for _, c := range components {
		if c.Name == name {
			return &c
		}
	}
	return nil
}

func normalizeRepo(repo string) string {
	repo = strings.TrimSpace(repo)
	for _, prefix := range []string{
		"https://github.com/",
		"http://github.com/",
		"github.com/",
	} {
		if strings.HasPrefix(repo, prefix) {
			repo = strings.TrimPrefix(repo, prefix)
			break
		}
	}
	repo = strings.TrimSuffix(repo, ".git")
	repo = strings.TrimSuffix(repo, "/")
	return repo
}

func validateComponent(comp componentDef, ciPath, ciRepo string) int {
	fmt.Printf("=== Validating component: %s ===\n", comp.Name)

	manifestPath := filepath.Join(comp.Dir, "tests.json")
	localRefDir := filepath.Join(comp.Dir, "ci", "step-registry")

	tests, suites, err := loadManifest(manifestPath)
	if err != nil {
		fmt.Printf("  [FAIL] Cannot load manifest: %v\n", err)
		return 1
	}

	fmt.Printf("  Directory:  %s/\n", comp.Dir)
	fmt.Printf("  Binary:     %s\n", comp.Binary)
	fmt.Printf("  Tests:      %d\n", len(tests))
	fmt.Printf("  Suites:     %d\n", len(suites))
	fmt.Println()

	failures := 0

	// Phase 1: OTE internal checks
	fmt.Println("  --- OTE Internal Checks ---")
	failures += checkTestScripts(comp.Dir, tests)
	failures += checkLocalRefs(comp, suites, localRefDir)
	failures += checkOrphanedRefs(comp, suites, localRefDir)
	failures += checkRefContent(comp, localRefDir)

	// Phase 2: Upstream CI checks
	if ciPath != "" || ciRepo != "" {
		fmt.Println()
		if ciPath != "" {
			fmt.Printf("  --- Upstream CI Checks (--ci-path %s) ---\n", ciPath)
			failures += checkUpstreamLocal(comp, suites, ciPath)
		} else {
			fmt.Printf("  --- Upstream CI Checks (--ci-repo %s) ---\n", ciRepo)
			failures += checkUpstreamRemote(comp, suites, ciRepo)
		}
	}

	fmt.Println()
	if failures == 0 {
		fmt.Println("  Result: all checks passed")
	} else {
		fmt.Printf("  Result: %d check(s) failed\n", failures)
	}

	return failures
}

func loadManifest(path string) ([]shell.TestEntry, []shell.SuiteEntry, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, fmt.Errorf("reading %s: %w", path, err)
	}

	var manifest shell.TestManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return nil, nil, fmt.Errorf("parsing %s: %w", path, err)
	}
	return manifest.Tests, manifest.Suites, nil
}

func checkTestScripts(dir string, tests []shell.TestEntry) int {
	missing := 0
	notExec := 0
	for _, t := range tests {
		scriptPath := filepath.Join(dir, t.Script)
		info, err := os.Stat(scriptPath)
		if os.IsNotExist(err) {
			fmt.Printf("  [FAIL] Test script missing: %s (%s)\n", t.Script, t.Name)
			missing++
			continue
		}
		if info.Mode()&0111 == 0 {
			fmt.Printf("  [FAIL] Test script not executable: %s\n", t.Script)
			notExec++
		}
	}
	if missing == 0 && notExec == 0 {
		fmt.Printf("  [PASS] All %d test scripts exist and are executable\n", len(tests))
		return 0
	}
	return missing + notExec
}

func checkLocalRefs(comp componentDef, suites []shell.SuiteEntry, refDir string) int {
	failures := 0
	for _, s := range suites {
		refName := stepregistry.MakeRefName(comp.OrgRepo, s.Name)
		refFile := filepath.Join(refDir, refName+"-ref.yaml")
		if _, err := os.Stat(refFile); os.IsNotExist(err) {
			fmt.Printf("  [FAIL] Suite %s has no local CI ref (expected: %s)\n", s.Name, refName)
			failures++
		} else {
			fmt.Printf("  [PASS] Suite %s → local ref %s\n", s.Name, refName)
		}
	}
	return failures
}

func checkOrphanedRefs(comp componentDef, suites []shell.SuiteEntry, refDir string) int {
	suiteRefNames := make(map[string]bool)
	for _, s := range suites {
		suiteRefNames[stepregistry.MakeRefName(comp.OrgRepo, s.Name)] = true
	}

	entries, err := os.ReadDir(refDir)
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Println("  [WARN] No local ci/step-registry/ directory")
			return 0
		}
		fmt.Printf("  [FAIL] Cannot read %s: %v\n", refDir, err)
		return 1
	}

	orphaned := 0
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), "-ref.yaml") {
			continue
		}
		refName := strings.TrimSuffix(e.Name(), "-ref.yaml")
		if !suiteRefNames[refName] {
			fmt.Printf("  [FAIL] Orphaned local CI ref: %s (no matching suite)\n", refName)
			orphaned++
		}
	}
	if orphaned == 0 {
		fmt.Println("  [PASS] No orphaned local CI refs")
	}
	return orphaned
}

func checkRefContent(comp componentDef, refDir string) int {
	entries, err := os.ReadDir(refDir)
	if err != nil {
		return 0
	}

	failures := 0
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), "-ref.yaml") {
			continue
		}

		refPath := filepath.Join(refDir, e.Name())
		data, err := os.ReadFile(refPath)
		if err != nil {
			fmt.Printf("  [FAIL] Cannot read ref %s: %v\n", e.Name(), err)
			failures++
			continue
		}

		var ref stepregistry.StepRef
		if err := yaml.Unmarshal(data, &ref); err != nil {
			fmt.Printf("  [FAIL] Invalid YAML in %s: %v\n", e.Name(), err)
			failures++
			continue
		}

		if ref.From != comp.Binary {
			fmt.Printf("  [FAIL] Ref %s: from=%q, expected %q\n", ref.Ref, ref.From, comp.Binary)
			failures++
		}

		cmdFile := filepath.Join(refDir, ref.Commands)
		cmdData, err := os.ReadFile(cmdFile)
		if err != nil {
			fmt.Printf("  [FAIL] Ref %s: commands file %s missing\n", ref.Ref, ref.Commands)
			failures++
			continue
		}

		cmdStr := string(cmdData)
		if !strings.Contains(cmdStr, comp.Binary+" run-suite") {
			fmt.Printf("  [FAIL] Ref %s: commands.sh does not run %s\n", ref.Ref, comp.Binary)
			failures++
		}
	}

	if failures == 0 {
		fmt.Println("  [PASS] All local ref YAML and commands.sh are valid")
	}
	return failures
}

func checkUpstreamLocal(comp componentDef, suites []shell.SuiteEntry, ciPath string) int {
	upstreamDir := filepath.Join(ciPath, comp.CIStepDir)

	var fakeEntries []os.DirEntry
	pathMap := make(map[string]string)

	err := filepath.WalkDir(upstreamDir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.IsDir() && strings.HasSuffix(d.Name(), "-ref.yaml") {
			fakeEntries = append(fakeEntries, &ghDirEntry{itemName: d.Name()})
			pathMap[d.Name()] = path
		}
		return nil
	})
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Printf("  [WARN] No upstream CI refs found at %s\n", upstreamDir)
			return 0
		}
		fmt.Printf("  [FAIL] Cannot walk upstream dir %s: %v\n", upstreamDir, err)
		return 1
	}

	return compareUpstreamRefs(comp, suites, fakeEntries, "", func(name string) ([]byte, error) {
		return os.ReadFile(pathMap[name])
	})
}

func checkUpstreamRemote(comp componentDef, suites []shell.SuiteEntry, ciRepo string) int {
	if _, err := exec.LookPath("gh"); err != nil {
		fmt.Println("  [WARN] gh CLI not found — install GitHub CLI to enable upstream checks")
		return 0
	}

	basePath := fmt.Sprintf("ci-operator/step-registry/%s", comp.CIStepDir)
	refs, err := listRefsRecursiveRemote(ciRepo, basePath)
	if err != nil {
		fmt.Printf("  [INFO] No step-registry path %q in %s, scanning full repo tree...\n", basePath, ciRepo)
		refs, err = listRefsFromTree(ciRepo)
		if err != nil {
			fmt.Printf("  [WARN] Cannot scan repo tree: %v\n", err)
			return 0
		}
	}

	if len(refs) == 0 {
		fmt.Printf("  [INFO] No CI step-registry ref files (*-ref.yaml) found in %s\n", ciRepo)
		return 0
	}

	var fakeEntries []os.DirEntry
	apiPathMap := make(map[string]string)
	for _, rf := range refs {
		fakeEntries = append(fakeEntries, &ghDirEntry{itemName: rf.name})
		apiPathMap[rf.name] = rf.apiPath
	}

	return compareUpstreamRefs(comp, suites, fakeEntries, "", func(name string) ([]byte, error) {
		fileOut, err := exec.Command("gh", "api", apiPathMap[name], "--jq", ".content").Output()
		if err != nil {
			return nil, err
		}
		decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(fileOut)))
		if err != nil {
			return nil, fmt.Errorf("base64 decode: %w", err)
		}
		return decoded, nil
	})
}

type ghFileRef struct {
	name    string
	apiPath string
}

func listRefsRecursiveRemote(ciRepo, dirPath string) ([]ghFileRef, error) {
	apiPath := fmt.Sprintf("repos/%s/contents/%s", ciRepo, dirPath)
	out, err := exec.Command("gh", "api", apiPath).Output()
	if err != nil {
		return nil, err
	}

	var listing []struct {
		Name string `json:"name"`
		Type string `json:"type"`
		Path string `json:"path"`
	}
	if err := json.Unmarshal(out, &listing); err != nil {
		return nil, fmt.Errorf("parse listing: %w", err)
	}

	var refs []ghFileRef
	for _, item := range listing {
		if item.Type == "file" && strings.HasSuffix(item.Name, "-ref.yaml") {
			refs = append(refs, ghFileRef{
				name:    item.Name,
				apiPath: fmt.Sprintf("repos/%s/contents/%s", ciRepo, item.Path),
			})
		} else if item.Type == "dir" {
			subRefs, err := listRefsRecursiveRemote(ciRepo, item.Path)
			if err != nil {
				continue
			}
			refs = append(refs, subRefs...)
		}
	}
	return refs, nil
}

func listRefsFromTree(ciRepo string) ([]ghFileRef, error) {
	apiPath := fmt.Sprintf("repos/%s/git/trees/HEAD?recursive=1", ciRepo)
	out, err := exec.Command("gh", "api", apiPath).Output()
	if err != nil {
		return nil, fmt.Errorf("git tree API: %w", err)
	}

	var tree struct {
		Tree []struct {
			Path string `json:"path"`
			Type string `json:"type"`
		} `json:"tree"`
	}
	if err := json.Unmarshal(out, &tree); err != nil {
		return nil, fmt.Errorf("parse tree: %w", err)
	}

	var refs []ghFileRef
	for _, item := range tree.Tree {
		if item.Type == "blob" && strings.HasSuffix(item.Path, "-ref.yaml") {
			name := filepath.Base(item.Path)
			refs = append(refs, ghFileRef{
				name:    name,
				apiPath: fmt.Sprintf("repos/%s/contents/%s", ciRepo, item.Path),
			})
		}
	}
	return refs, nil
}

type upstreamStepRef struct {
	Ref struct {
		As        string `yaml:"as"`
		FromImage struct {
			Name string `yaml:"name"`
		} `yaml:"from_image"`
		From     string `yaml:"from"`
		Commands string `yaml:"commands"`
	} `yaml:"ref"`
}

func parseUpstreamRef(data []byte) (refName, fromImage string, err error) {
	var oteRef stepregistry.StepRef
	if err := yaml.Unmarshal(data, &oteRef); err == nil && oteRef.Ref != "" {
		return oteRef.As, oteRef.From, nil
	}

	var upRef upstreamStepRef
	if err := yaml.Unmarshal(data, &upRef); err != nil {
		return "", "", fmt.Errorf("cannot parse as OTE or upstream format: %w", err)
	}
	name := upRef.Ref.As
	image := upRef.Ref.FromImage.Name
	if image == "" {
		image = upRef.Ref.From
	}
	return name, image, nil
}

func compareUpstreamRefs(comp componentDef, suites []shell.SuiteEntry, entries []os.DirEntry, _ string, readFile func(string) ([]byte, error)) int {
	suiteNames := make(map[string]bool)
	for _, s := range suites {
		suiteNames[s.Name] = true
	}

	suiteRefNames := make(map[string]string)
	for _, s := range suites {
		suiteRefNames[stepregistry.MakeRefName(comp.OrgRepo, s.Name)] = s.Name
	}

	failures := 0
	upstreamRefNames := make(map[string]bool)

	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), "-ref.yaml") {
			continue
		}
		refName := strings.TrimSuffix(e.Name(), "-ref.yaml")
		upstreamRefNames[refName] = true

		data, err := readFile(e.Name())
		if err != nil {
			fmt.Printf("  [WARN] Cannot read upstream ref %s: %v\n", e.Name(), err)
			continue
		}

		parsedName, fromImage, err := parseUpstreamRef(data)
		if err != nil {
			fmt.Printf("  [WARN] Cannot parse upstream ref %s: %v\n", e.Name(), err)
			continue
		}

		if suiteName, ok := suiteRefNames[refName]; ok {
			fmt.Printf("  [PASS] Upstream ref %s matches OTE suite %s (image: %s)\n", refName, suiteName, fromImage)
		} else if parsedName != "" {
			fmt.Printf("  [INFO] Upstream ref %s (image: %s) — no matching OTE suite\n", refName, fromImage)
		} else {
			fmt.Printf("  [INFO] Upstream ref %s — no matching OTE suite\n", refName)
		}
	}

	for _, s := range suites {
		refName := stepregistry.MakeRefName(comp.OrgRepo, s.Name)
		if !upstreamRefNames[refName] {
			fmt.Printf("  [WARN] OTE suite %s has no upstream CI ref\n", s.Name)
		}
	}

	return failures
}

// ghDirEntry implements os.DirEntry for GitHub API directory listings.
type ghDirEntry struct {
	itemName string
}

func (e *ghDirEntry) Name() string               { return e.itemName }
func (e *ghDirEntry) IsDir() bool                 { return false }
func (e *ghDirEntry) Type() os.FileMode           { return 0 }
func (e *ghDirEntry) Info() (os.FileInfo, error)   { return nil, nil }

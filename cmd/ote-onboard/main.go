package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func main() {
	reader := bufio.NewReader(os.Stdin)

	fmt.Println("=== OTE Shell Test Onboarding ===")
	fmt.Println("This tool will guide you through creating a new OTE shell test project.")
	fmt.Println()

	name := prompt(reader, "Project name (e.g., acme-tests)", "")
	if name == "" {
		fatal("project name is required")
	}

	product := prompt(reader, "Product identifier (e.g., acme)", "")
	if product == "" {
		fatal("product identifier is required")
	}

	org := prompt(reader, "Go module org prefix (e.g., openshift)", "openshift")
	kind := prompt(reader, "Component kind [external, layered-product, standalone]", "external")
	ciOrgRepo := prompt(reader, "GitHub org/repo for CI refs (e.g., openshift/acme-tests, leave empty to skip)", "")

	fmt.Println()
	fmt.Println("=== Configuration Summary ===")
	fmt.Printf("  Name:         %s\n", name)
	fmt.Printf("  Product:      %s\n", product)
	fmt.Printf("  Org:          %s\n", org)
	fmt.Printf("  Kind:         %s\n", kind)
	fmt.Printf("  Module:       %s/%s\n", org, name)
	if ciOrgRepo != "" {
		fmt.Printf("  CI org/repo:  %s\n", ciOrgRepo)
	}
	fmt.Println()

	confirm := prompt(reader, "Proceed with scaffolding? [Y/n]", "Y")
	if !strings.HasPrefix(strings.ToUpper(confirm), "Y") {
		fmt.Println("Aborted.")
		os.Exit(0)
	}

	scaffoldScript := findScaffoldScript()
	if scaffoldScript == "" {
		fatal("ote-scaffold.sh not found — ensure it exists in the repo root or is on PATH")
	}

	args := []string{scaffoldScript, "--name", name, "--product", product, "--org", org, "--kind", kind}
	if ciOrgRepo != "" {
		args = append(args, "--ci-org-repo", ciOrgRepo)
	}

	fmt.Println()
	fmt.Printf("Running: bash %s\n", strings.Join(args, " "))
	fmt.Println()

	cmd := exec.Command("bash", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fatal(fmt.Sprintf("scaffold failed: %v", err))
	}

	fmt.Println()
	fmt.Println("=== Post-Scaffold Setup ===")

	projectDir := name
	if err := os.Chdir(projectDir); err != nil {
		fatal(fmt.Sprintf("cannot cd to %s: %v", projectDir, err))
	}

	fmt.Println("Running go mod tidy...")
	if err := runCmd("go", "mod", "tidy"); err != nil {
		fmt.Fprintf(os.Stderr, "WARN: go mod tidy failed: %v\n", err)
	}

	fmt.Println("Running make build...")
	if err := runCmd("make", "build"); err != nil {
		fmt.Fprintf(os.Stderr, "WARN: make build failed: %v\n", err)
	}

	fmt.Println("Running make validate...")
	if err := runCmd("make", "validate"); err != nil {
		fmt.Fprintf(os.Stderr, "WARN: make validate failed: %v\n", err)
	}

	fmt.Println()
	fmt.Println("=== Onboarding Complete ===")
	fmt.Printf("Project: %s/\n", projectDir)
	fmt.Println()
	fmt.Println("Next steps:")
	fmt.Println("  1. Replace example scripts in scripts/ with real test scripts")
	fmt.Println("  2. Update tests.json with test entries, labels, tags, and suites")
	fmt.Println("  3. Run: make build && make validate")
	fmt.Println("  4. Run: make ci  (build + validate + shellcheck)")
	fmt.Println("  5. Run: make test  (run the default suite)")
	fmt.Println()
	fmt.Println("Documentation: see ONBOARDING_SHELL_TESTS.md in the repo root")
}

func prompt(reader *bufio.Reader, label, defaultVal string) string {
	if defaultVal != "" {
		fmt.Printf("%s [%s]: ", label, defaultVal)
	} else {
		fmt.Printf("%s: ", label)
	}

	input, _ := reader.ReadString('\n')
	input = strings.TrimSpace(input)
	if input == "" {
		return defaultVal
	}
	return input
}

func findScaffoldScript() string {
	candidates := []string{
		"ote-scaffold.sh",
		"../ote-scaffold.sh",
		filepath.Join(os.Getenv("HOME"), "dev", "openshift-tests-extension", "ote-scaffold.sh"),
	}

	if exe, err := os.Executable(); err == nil {
		candidates = append(candidates, filepath.Join(filepath.Dir(exe), "ote-scaffold.sh"))
	}

	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			abs, _ := filepath.Abs(c)
			return abs
		}
	}
	return ""
}

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func fatal(msg string) {
	fmt.Fprintf(os.Stderr, "Error: %s\n", msg)
	os.Exit(1)
}

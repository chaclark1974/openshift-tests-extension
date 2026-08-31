package shell

import (
	"os"
	"path/filepath"
	"testing"
)

func setupValidManifest(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")

	manifest := `{
		"defaults": {"lifecycle": "blocking", "timeout": "5m"},
		"tests": [
			{"name": "[sig-test] valid test", "script": "a.sh", "labels": ["SMOKE"]}
		],
		"suites": [
			{"name": "test/all", "qualifiers": ["labels.exists(l, l==\"SMOKE\")"]}
		]
	}`
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(manifest), 0644)
	return path
}

func TestValidateManifest_Valid(t *testing.T) {
	path := setupValidManifest(t)
	errs := ValidateManifest(path)
	if len(errs) != 0 {
		t.Errorf("expected no errors, got: %v", errs)
	}
}

func TestValidateManifest_FileNotFound(t *testing.T) {
	errs := ValidateManifest("/nonexistent/tests.json")
	if len(errs) == 0 {
		t.Fatal("expected error for missing file")
	}
}

func TestValidateManifest_InvalidJSON(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte("not json"), 0644)

	errs := ValidateManifest(path)
	if len(errs) == 0 {
		t.Fatal("expected error for invalid JSON")
	}
}

func TestValidateManifest_MissingName(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"tests": [{"script": "a.sh"}]}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "tests[0].name" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected error for missing name, got: %v", errs)
	}
}

func TestValidateManifest_MissingScript(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"tests": [{"name": "[sig-test] test"}]}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "tests[0].script" && e.Message == "required" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected error for missing script, got: %v", errs)
	}
}

func TestValidateManifest_ScriptNotFound(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"tests": [{"name": "[sig-test] test", "script": "missing.sh"}]}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "tests[0].script" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected error for missing script file, got: %v", errs)
	}
}

func TestValidateManifest_ScriptNotExecutable(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "noexec.sh"), []byte("#!/bin/bash\nexit 0\n"), 0644)
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"tests": [{"name": "[sig-test] test", "script": "noexec.sh"}]}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "tests[0].script" && e.Message != "" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected error for non-executable script, got: %v", errs)
	}
}

func TestValidateManifest_DuplicateNames(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	writeScript(t, dir, "b.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	manifest := `{"tests": [
		{"name": "[sig-test] dupe", "script": "a.sh"},
		{"name": "[sig-test] dupe", "script": "b.sh"}
	]}`
	os.WriteFile(path, []byte(manifest), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "tests[1].name" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected duplicate name error, got: %v", errs)
	}
}

func TestValidateManifest_BadNameConvention(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"tests": [{"name": "no brackets", "script": "a.sh"}]}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "tests[0].name" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected naming convention error, got: %v", errs)
	}
}

func TestValidateManifest_InvalidLifecycle(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"tests": [{"name": "[sig-test] test", "script": "a.sh", "lifecycle": "invalid"}]}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "tests[0].lifecycle" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected lifecycle error, got: %v", errs)
	}
}

func TestValidateManifest_InvalidCEL(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"tests": [{"name": "[sig-test] test", "script": "a.sh", "include": "not a valid cel !!!"}]}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "tests[0].include" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected CEL validation error, got: %v", errs)
	}
}

func TestValidateManifest_InvalidSuiteQualifier(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	manifest := `{
		"tests": [{"name": "[sig-test] test", "script": "a.sh"}],
		"suites": [{"name": "test/bad", "qualifiers": ["invalid cel !!!"]}]
	}`
	os.WriteFile(path, []byte(manifest), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "suites[0].qualifiers[0]" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected suite qualifier CEL error, got: %v", errs)
	}
}

func TestValidateManifest_InvalidTimeout(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"defaults": {"timeout": "nope"}, "tests": [{"name": "[sig-test] test", "script": "a.sh"}]}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "defaults.timeout" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected timeout error, got: %v", errs)
	}
}

func TestValidateManifest_EmptyEnvKey(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"tests": [{"name": "[sig-test] test", "script": "a.sh", "env": {"": "value"}}]}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "tests[0].env" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected empty env key error, got: %v", errs)
	}
}

func TestValidateManifest_InvalidCredentials(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	manifest := `{"tests": [{"name": "[sig-test] test", "script": "a.sh", "credentials": [{"namespace": "", "name": "", "mount_path": ""}]}]}`
	os.WriteFile(path, []byte(manifest), 0644)

	errs := ValidateManifest(path)
	nsFound, nameFound, mountFound := false, false, false
	for _, e := range errs {
		if e.Field == "tests[0].credentials[0].namespace" {
			nsFound = true
		}
		if e.Field == "tests[0].credentials[0].name" {
			nameFound = true
		}
		if e.Field == "tests[0].credentials[0].mount_path" {
			mountFound = true
		}
	}
	if !nsFound || !nameFound || !mountFound {
		t.Errorf("expected credential validation errors, got: %v", errs)
	}
}

func TestValidateManifest_InvalidFromImage(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"tests": [{"name": "[sig-test] test", "script": "a.sh", "from_image": "notanimage"}]}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "tests[0].from_image" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected from_image validation error, got: %v", errs)
	}
}

func TestValidateManifest_ValidNewFields(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	manifest := `{
		"defaults": {"env": {"CLUSTER": "test"}},
		"tests": [{
			"name": "[sig-test] ci test", "script": "a.sh",
			"env": {"MY_VAR": "val"},
			"from_image": "registry.ci/ocp:tests",
			"credentials": [{"namespace": "ns", "name": "cred", "mount_path": "/mnt"}],
			"cluster_profile": "aws"
		}]
	}`
	os.WriteFile(path, []byte(manifest), 0644)

	errs := ValidateManifest(path)
	if len(errs) != 0 {
		t.Errorf("expected no errors for valid new fields, got: %v", errs)
	}
}

func TestValidateManifest_DefaultsEmptyEnvKey(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "a.sh", "#!/bin/bash\nexit 0\n")
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"defaults": {"env": {"": "val"}}, "tests": [{"name": "[sig-test] test", "script": "a.sh"}]}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Field == "defaults.env" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected defaults empty env key error, got: %v", errs)
	}
}

func TestValidateManifest_NoTests(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tests.json")
	os.WriteFile(path, []byte(`{"tests": []}`), 0644)

	errs := ValidateManifest(path)
	found := false
	for _, e := range errs {
		if e.Message == "no tests defined" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected 'no tests defined' error, got: %v", errs)
	}
}

package shell

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/cel-go/cel"
	"github.com/google/cel-go/checker/decls"
)

// ValidationError represents a single validation issue.
type ValidationError struct {
	Field   string
	Message string
}

func (v ValidationError) String() string {
	if v.Field != "" {
		return fmt.Sprintf("%s: %s", v.Field, v.Message)
	}
	return v.Message
}

// ValidateManifest checks a tests.json file for common errors.
// Returns a list of validation errors (empty if valid).
func ValidateManifest(path string) []ValidationError {
	var errs []ValidationError

	data, err := os.ReadFile(path)
	if err != nil {
		return []ValidationError{{Message: fmt.Sprintf("cannot read manifest: %v", err)}}
	}

	var manifest TestManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return []ValidationError{{Message: fmt.Sprintf("invalid JSON: %v", err)}}
	}

	baseDir := filepath.Dir(path)

	if manifest.Defaults.Timeout != "" {
		if _, err := parseOptionalDuration(manifest.Defaults.Timeout); err != nil {
			errs = append(errs, ValidationError{
				Field:   "defaults.timeout",
				Message: fmt.Sprintf("invalid duration %q: %v", manifest.Defaults.Timeout, err),
			})
		}
	}

	if manifest.Defaults.Lifecycle != "" && manifest.Defaults.Lifecycle != "blocking" && manifest.Defaults.Lifecycle != "informing" {
		errs = append(errs, ValidationError{
			Field:   "defaults.lifecycle",
			Message: fmt.Sprintf("must be \"blocking\" or \"informing\", got %q", manifest.Defaults.Lifecycle),
		})
	}

	for k := range manifest.Defaults.Env {
		if k == "" {
			errs = append(errs, ValidationError{Field: "defaults.env", Message: "env var key must not be empty"})
		} else if strings.Contains(k, "=") {
			errs = append(errs, ValidationError{
				Field:   fmt.Sprintf("defaults.env[%s]", k),
				Message: "env var key must not contain '='",
			})
		}
	}

	if len(manifest.Tests) == 0 {
		errs = append(errs, ValidationError{Message: "no tests defined"})
	}

	seenNames := map[string]int{}
	for i, t := range manifest.Tests {
		prefix := fmt.Sprintf("tests[%d]", i)

		if t.Name == "" {
			errs = append(errs, ValidationError{Field: prefix + ".name", Message: "required"})
		} else {
			if !strings.HasPrefix(t.Name, "[") {
				errs = append(errs, ValidationError{
					Field:   prefix + ".name",
					Message: fmt.Sprintf("should follow [sig-xxx] convention, got %q", t.Name),
				})
			}
			if prev, exists := seenNames[t.Name]; exists {
				errs = append(errs, ValidationError{
					Field:   prefix + ".name",
					Message: fmt.Sprintf("duplicate of tests[%d]", prev),
				})
			}
			seenNames[t.Name] = i
		}

		if t.Script == "" {
			errs = append(errs, ValidationError{Field: prefix + ".script", Message: "required"})
		} else {
			scriptPath := filepath.Join(baseDir, t.Script)
			info, statErr := os.Stat(scriptPath)
			if statErr != nil {
				errs = append(errs, ValidationError{
					Field:   prefix + ".script",
					Message: fmt.Sprintf("file not found: %s", scriptPath),
				})
			} else if info.Mode()&0111 == 0 {
				errs = append(errs, ValidationError{
					Field:   prefix + ".script",
					Message: fmt.Sprintf("not executable: %s", scriptPath),
				})
			}
		}

		if t.Lifecycle != "" && t.Lifecycle != "blocking" && t.Lifecycle != "informing" {
			errs = append(errs, ValidationError{
				Field:   prefix + ".lifecycle",
				Message: fmt.Sprintf("must be \"blocking\" or \"informing\", got %q", t.Lifecycle),
			})
		}

		if t.Timeout != "" {
			if _, err := parseOptionalDuration(t.Timeout); err != nil {
				errs = append(errs, ValidationError{
					Field:   prefix + ".timeout",
					Message: fmt.Sprintf("invalid duration %q: %v", t.Timeout, err),
				})
			}
		}

		if t.Include != "" {
			if err := validateCELEnvironment(t.Include); err != nil {
				errs = append(errs, ValidationError{
					Field:   prefix + ".include",
					Message: fmt.Sprintf("invalid CEL: %v", err),
				})
			}
		}

		if t.Exclude != "" {
			if err := validateCELEnvironment(t.Exclude); err != nil {
				errs = append(errs, ValidationError{
					Field:   prefix + ".exclude",
					Message: fmt.Sprintf("invalid CEL: %v", err),
				})
			}
		}

		for k := range t.Env {
			if k == "" {
				errs = append(errs, ValidationError{Field: prefix + ".env", Message: "env var key must not be empty"})
			} else if strings.Contains(k, "=") {
				errs = append(errs, ValidationError{
					Field:   fmt.Sprintf("%s.env[%s]", prefix, k),
					Message: "env var key must not contain '='",
				})
			}
		}

		if t.FromImage != "" {
			if !strings.Contains(t.FromImage, "/") && !strings.Contains(t.FromImage, ":") {
				errs = append(errs, ValidationError{
					Field:   prefix + ".from_image",
					Message: fmt.Sprintf("does not look like a container image reference: %q", t.FromImage),
				})
			}
		}

		for j, cred := range t.Credentials {
			credPrefix := fmt.Sprintf("%s.credentials[%d]", prefix, j)
			if cred.Namespace == "" {
				errs = append(errs, ValidationError{Field: credPrefix + ".namespace", Message: "required"})
			}
			if cred.Name == "" {
				errs = append(errs, ValidationError{Field: credPrefix + ".name", Message: "required"})
			}
			if cred.MountPath == "" {
				errs = append(errs, ValidationError{Field: credPrefix + ".mount_path", Message: "required"})
			}
		}
	}

	for i, s := range manifest.Suites {
		prefix := fmt.Sprintf("suites[%d]", i)
		if s.Name == "" {
			errs = append(errs, ValidationError{Field: prefix + ".name", Message: "required"})
		}
		for j, q := range s.Qualifiers {
			if err := validateCELQualifier(q); err != nil {
				errs = append(errs, ValidationError{
					Field:   fmt.Sprintf("%s.qualifiers[%d]", prefix, j),
					Message: fmt.Sprintf("invalid CEL: %v", err),
				})
			}
		}
	}

	return errs
}

func validateCELEnvironment(expr string) error {
	env, err := cel.NewEnv(
		cel.Declarations(
			decls.NewVar("platform", decls.String),
			decls.NewVar("architecture", decls.String),
			decls.NewVar("network", decls.String),
			decls.NewVar("networkStack", decls.String),
			decls.NewVar("topology", decls.String),
			decls.NewVar("upgrade", decls.String),
			decls.NewVar("version", decls.String),
			decls.NewVar("installer", decls.String),
			decls.NewVar("externalConnectivity", decls.String),
			decls.NewVar("apiGroups", decls.NewListType(decls.String)),
			decls.NewVar("featureGates", decls.NewListType(decls.String)),
			decls.NewVar("optionalCapabilities", decls.NewListType(decls.String)),
			decls.NewVar("fact_keys", decls.NewListType(decls.String)),
			decls.NewVar("facts", decls.NewMapType(decls.String, decls.String)),
		),
	)
	if err != nil {
		return err
	}
	ast, iss := env.Parse(expr)
	if iss.Err() != nil {
		return iss.Err()
	}
	_, iss = env.Check(ast)
	if iss.Err() != nil {
		return iss.Err()
	}
	return nil
}

func validateCELQualifier(expr string) error {
	env, err := cel.NewEnv(
		cel.Declarations(
			decls.NewVar("source", decls.String),
			decls.NewVar("name", decls.String),
			decls.NewVar("originalName", decls.String),
			decls.NewVar("labels", decls.NewListType(decls.String)),
			decls.NewVar("codeLocations", decls.NewListType(decls.String)),
			decls.NewVar("tags", decls.NewMapType(decls.String, decls.String)),
		),
	)
	if err != nil {
		return err
	}
	ast, iss := env.Parse(expr)
	if iss.Err() != nil {
		return iss.Err()
	}
	_, iss = env.Check(ast)
	if iss.Err() != nil {
		return iss.Err()
	}
	return nil
}

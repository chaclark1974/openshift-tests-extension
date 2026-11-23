// Package interop embeds every layered product's scenario manifest so they ship
// inside the binary. Each product owns a directory (acm/, acs/, cnv/, odf/,
// quay/) containing a scenarios.json. The adapter (pkg/adapter) merges them.
package interop

import "embed"

//go:embed acm acs cnv odf quay
var ScenarioFS embed.FS

# Quay Public Test Repository Integration

## Overview
This integration demonstrates how to use the OpenShift Tests Extension (OTE) library with a Quay public test repository.

## Structure

### Files Created

#### `test/quay/quay.go`
Package declaration file for the quay test package.

#### `test/quay/repository.go`
Contains the Quay public test repository integration test using the Ginkgo/Gomega testing framework.

### Files Modified

#### `cmd/example-tests/main.go`
- Added import: `_ "github.com/openshift-eng/openshift-tests-extension/test/quay"`
- Registered suite: `quay/tests` as a child of `openshift/conformance/parallel`

## Test Details

### Test: Quay Public Test Repository Validation

**Test Name:** `[sig-registry] Quay public test repository should be accessible and return valid repository metadata`

**What it validates:**
- Connectivity to Quay.io API (`https://quay.io/api/v1/repository/quay/test`)
- HTTP 200 OK response
- JSON content-type header
- Repository metadata structure including:
  - Namespace: `quay`
  - Name: `test`
  - Kind: `image`
  - IsPublic: `true`
  - State: `NORMAL`

**Repository Used:** `quay/test` - Official Quay.io public test repository

**Suite:** `quay/tests`  
**Parent Suite:** `openshift/conformance/parallel`  
**Lifecycle:** `blocking`

## Building

```bash
go build -o example-tests ./cmd/example-tests
```

## Running Tests

### List the Quay test
```bash
./example-tests list tests | jq '.[] | select(.name | contains("Quay"))'
```

### Run the specific test
```bash
./example-tests run-test "[sig-registry] Quay public test repository should be accessible and return valid repository metadata"
```

### Run the entire quay suite
```bash
./example-tests run-suite quay/tests
```

### List available suites
```bash
./example-tests list suites | grep quay
```

## Test Results

✅ **Status:** PASSING  
⏱️ **Duration:** ~120-211ms  
🔧 **Last Run:** 2026-06-18

## Integration Pattern

This integration follows the OTE library pattern:

1. **Test Package Structure:**
   ```
   test/quay/
   ├── quay.go           # Package file
   └── repository.go     # Test specifications
   ```

2. **Test Registration:**
   - Tests are automatically discovered via Ginkgo
   - Imported in `main.go` with blank import
   - Suite registered in extension registry

3. **Test Execution:**
   - Tests run through the OTE framework
   - Results output in JSON format
   - Compatible with OpenShift test orchestration

## API Response Structure

The test validates the following JSON structure from Quay API:

```json
{
  "namespace": "quay",
  "name": "test",
  "kind": "image",
  "description": "",
  "is_public": true,
  "is_organization": true,
  "state": "NORMAL"
}
```

## Extensions

To add more Quay tests:

1. Add new test cases in `test/quay/repository.go`
2. Use Ginkgo's `Describe` and `It` blocks
3. Follow the `[sig-registry]` naming convention
4. Rebuild the binary

Example:
```go
It("should validate repository tags", func() {
    // Your test code here
})
```

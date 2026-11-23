# OTE Interop Binary (`ote--interop`)

A single [OpenShift Tests Extension (OTE)](https://github.com/openshift-eng/openshift-tests-extension)
binary that hosts the interop test catalogs for multiple Red Hat layered
products — **ACM, Quay, ACS, ODF, and CNV** — in one process.

It follows the **scenario‑JSON‑driven** model (as in
[`RedHatQE/chaos-tests-extension`](https://github.com/oharan2/chaos-tests-extension)):
every test is a JSON `ScenarioSpec` that a generic exec adapter turns into an OTE
test spec and runs as a subprocess. There is **no Ginkgo** and no per‑product Go
test code — products are *data*.

- **Module:** `github.com/stolostron/cluster-lifecycle-e2e/openshift-tests-ext`
- **Binary:** `ote--interop`
- **Project root:** `interop/test/ote/`
- **Go:** 1.23+

---

## Table of contents

1. [Architecture](#architecture)
2. [Directory layout](#directory-layout)
3. [Components (products)](#components-products)
4. [Scenario JSON schema](#scenario-json-schema)
5. [The exec adapter](#the-exec-adapter)
6. [Selection model: tags, labels, qualifiers, suites](#selection-model-tags-labels-qualifiers-suites)
7. [Suites reference](#suites-reference)
8. [Building](#building)
9. [Running & listing (CLI)](#running--listing-cli)
10. [Adding tests and products](#adding-tests-and-products)
11. [How origin/openshift-tests uses this binary](#how-originopenshift-tests-uses-this-binary)
12. [Remaining work to be production/CI ready](#remaining-work-to-be-productionci-ready)

---

## Architecture

```
test/interop/<product>/scenarios.json   (data: the test catalogs, embedded)
            │
            │  //go:embed  (test/interop/embed.go  ->  ScenarioFS)
            ▼
pkg/adapter.BuildSpecsByProductFS(ScenarioFS)
            │  merges every scenarios.json, groups by "product"
            ▼
map[product] -> []*ExtensionTestSpec     (each spec's Run execs the scenario's command)
            │
            │  cmd/ote--interop/main.go
            ▼
one e.Extension per product (+ its suites)  ->  registry  ->  OTE CLI
```

Three ideas:

1. **Data, not code.** Tests live in JSON (`scenarios.json`), one directory per
   product. Adding/removing a test is a JSON edit.
2. **One generic adapter.** `pkg/adapter` turns any `ScenarioSpec` into an OTE
   spec whose `Run` execs `command` as a subprocess, mapping exit code →
   passed/failed and honoring skips/timeouts/env‑gating. No per‑product
   branching.
3. **One binary, many components.** Each product is registered as its own OTE
   **component** (`<product>:layered-product:<product>-tests`) with its own
   suites, so origin can target each independently.

---

## Directory layout

```
interop/test/ote/                         # PROJECT ROOT (go.mod here)
├── ote--interop                          # the compiled binary (build artifact)
├── go.mod / go.sum
├── Makefile                              # build / test / list / validate targets
├── cmd/
│   └── ote--interop/
│       └── main.go                       # registers the 5 extensions + all suites
├── pkg/
│   └── adapter/
│       └── adapter.go                    # generic exec adapter (ScenarioSpec -> OTE spec)
└── test/
    └── interop/
        ├── embed.go                      # //go:embed acm acs cnv odf quay
        ├── acm/scenarios.json
        ├── quay/scenarios.json
        ├── acs/scenarios.json
        ├── odf/scenarios.json
        └── cnv/scenarios.json
```

| Path | Purpose |
|------|---------|
| `cmd/ote--interop/main.go` | Declares each product's **component identity** and **suites**; wires specs from the adapter. The only per‑product Go left. |
| `pkg/adapter/adapter.go` | Product‑agnostic: parse JSON → `ExtensionTestSpec`, exec subprocess, map results. |
| `test/interop/<product>/scenarios.json` | That product's test catalog. |
| `test/interop/embed.go` | Embeds the whole scenario tree into the binary. |

---

## Components (products)

Five OTE components are registered. The identifier (`product:type:name`) is what
you pass to `--component`. **ACM is registered first, so it is the default**
component; the others require `--component`.

| Component (`--component`) | Tests | Upstream reference |
|---------------------------|-------|--------------------|
| `acm:layered-product:acm-tests`  (default) | 12 | ACM / `stolostron`; OPP upgrade commands script |
| `quay:layered-product:quay-tests` | 7 | `quay/quay` web Playwright e2e |
| `acs:layered-product:acs-tests`   | 8 | `stackrox/stackrox` qa-tests-backend |
| `odf:layered-product:odf-tests`   | 9 | `red-hat-storage/ocs-ci` (pytest) |
| `cnv:layered-product:cnv-tests`   | 7 | Container‑native Virtualization / KubeVirt |

> The upstream repos are **references** used to model the scenarios. No upstream
> code is pulled or built; the scenario `command`s are placeholders (see
> [Remaining work](#remaining-work-to-be-productionci-ready)).

---

## Scenario JSON schema

Each `test/interop/<product>/scenarios.json` is:

```json
{ "scenarios": [ { /* ScenarioSpec */ }, ... ] }
```

A `ScenarioSpec`:

| Field | Type | Required | Meaning |
|-------|------|----------|---------|
| `name` | string | ✅ | OTE test name. Convention: `[sig-<product>-<area>] description`. |
| `product` | string | ✅ | Routes the spec to a component (`acm`,`quay`,`acs`,`odf`,`cnv`). → tag `product`. |
| `category` | string | | Functional area. → tag `category`. |
| `labels` | []string | | Membership flags: scenario (`OPP`,`ACM-VIRT`), depth (`SMOKE`), product (`QUAY-E2E`, …). |
| `lifecycle` | string | | `informing` (default here) or `blocking`. |
| `timeout` | string | | Go duration, e.g. `"30m"`. |
| `include` | string | | CEL env gate, e.g. `platform=="aws"`. Spec runs only when true. |
| `command` | []string | ✅ | argv executed as a subprocess. `command[0]` is the binary. |
| `env` | map[string]string | | Extra env for the subprocess (merged over the inherited env). |
| `workDir` | string | | Working directory for the subprocess. |
| `skipIfEnvUnset` | []string | | Skip the test if **any** listed env var is unset. |

Example (`acm/scenarios.json`):

```json
{
  "name": "[sig-acm-upgrade] ACM subscription targets an upgrade channel",
  "product": "acm",
  "category": "acm-upgrade",
  "labels": ["OPP"],
  "lifecycle": "informing",
  "timeout": "30m",
  "include": "platform==\"aws\"",
  "skipIfEnvUnset": ["KUBECONFIG"],
  "command": ["bash", "-c", "oc get subscription -n ${ACM_SUBSCRIPTION_NAMESPACE:-open-cluster-management} advanced-cluster-management -o jsonpath='{.spec.channel}'"]
}
```

---

## The exec adapter

`pkg/adapter/adapter.go` exposes:

- `BuildSpecsByProductFS(fsys fs.FS) (map[string]ExtensionTestSpecs, error)` —
  walks a filesystem, merges every `*.json` manifest, returns specs grouped by
  `product`. Used with the embedded `ScenarioFS`.
- `BuildSpecsByProduct(data []byte) (...)` — same, for a single manifest.

For each scenario it builds an `ExtensionTestSpec` whose `Run`/`RunParallel`:

1. **Skips** if any `skipIfEnvUnset` var is missing → `skipped`.
2. Applies `timeout` via `context.WithTimeout`.
3. Execs `command` with `os.Environ()` + `env`, in `workDir`, capturing
   combined stdout/stderr into the result `Output`.
4. Maps exit code: `0` → `passed`, non‑zero → `failed` (error recorded).

It also sets `Lifecycle`, `Timeout`, tags (`product`,`category`), `Labels`, and
`Include` (env gating) from the JSON. Validation: `name`, `product`, and
`command` are required; duplicate names are rejected.

---

## Selection model: tags, labels, qualifiers, suites

Tests are classified on **three independent axes**, then suites select across them.

| Axis | Mechanism | Examples | How to query (CEL) |
|------|-----------|----------|--------------------|
| **Product / area** | **tag** | `product=acm`, `category=acm-policy` | `tags["category"] == "acm-policy"` |
| **Scenario / bundle** | **label** | `OPP`, `ACM-VIRT` | `labels.exists(l, l=="OPP")` |
| **Depth** | **label** | `SMOKE` | `labels.exists(l, l=="SMOKE")` |

- **Tags** are key/value (`map[string]string`) — good for dimensions with values.
- **Labels** are flat membership flags that stack — a test can be both `OPP` and
  `SMOKE`. Use labels when a test can belong to several groups at once.

A **suite** is a named set of CEL **qualifiers** (OR'd). `AddSuite` automatically
AND‑s in a `source == "<component-id>"` guard, so a suite only ever selects its
own component's tests. (`AddGlobalSuite` omits the guard.)

Combine axes with `&&` in one qualifier, e.g. policy‑area smoke:

```
tags["category"] == "acm-policy" && labels.exists(l, l=="SMOKE")
```

CEL variables available to qualifiers: `source`, `name`, `originalName`,
`labels` (list), `tags` (map), `codeLocations` (list).

---

## Suites reference

Qualifiers below omit the auto‑added `source == "<id>"` guard.

### ACM — `acm:layered-product:acm-tests`
| Suite | Qualifier |
|-------|-----------|
| `acm/opp` | `labels.exists(l, l=="OPP")` |
| `acm/virt` | `labels.exists(l, l=="ACM-VIRT")` |
| `acm/upgrade` | `tags["category"] == "acm-upgrade"` |
| `acm/policy` | `tags["category"] == "acm-policy"` |
| `acm/e2e` | `tags["category"] == "acm-e2e"` |
| `acm/gre` | `tags["category"] == "acm-gre"` |
| `acm/smoke` | `labels.exists(l, l=="SMOKE")` |
| `acm/policy-smoke` | `tags["category"]=="acm-policy" && labels.exists(l,l=="SMOKE")` |

### Quay — `quay:layered-product:quay-tests`
| Suite | Qualifier |
|-------|-----------|
| `quay/web-e2e` | `labels.exists(l, l=="QUAY-E2E")` |
| `quay/opp` | `labels.exists(l, l=="OPP")` |
| `quay/repository` | `tags["category"] == "quay-repository"` |
| `quay/organization` | `tags["category"] == "quay-organization"` |
| `quay/robot` | `tags["category"] == "quay-robot"` |

### ACS — `acs:layered-product:acs-tests`
| Suite | Qualifier |
|-------|-----------|
| `acs/qa-e2e` | `labels.exists(l, l=="ACS-E2E")` |
| `acs/vulnerability` | `tags["category"] == "acs-vulnerability"` |
| `acs/compliance` | `tags["category"] == "acs-compliance"` |
| `acs/network` | `tags["category"] == "acs-network"` |
| `acs/admission` | `tags["category"] == "acs-admission"` |
| `acs/smoke` | `labels.exists(l, l=="SMOKE")` |

### ODF — `odf:layered-product:odf-tests`
| Suite | Qualifier |
|-------|-----------|
| `odf/ocs-ci` | `labels.exists(l, l=="ODF-E2E")` |
| `odf/block` | `tags["category"] == "odf-block"` |
| `odf/file` | `tags["category"] == "odf-file"` |
| `odf/object` | `tags["category"] == "odf-object"` |
| `odf/cephhealth` | `tags["category"] == "odf-cephhealth"` |
| `odf/smoke` | `labels.exists(l, l=="SMOKE")` |

### CNV — `cnv:layered-product:cnv-tests`
| Suite | Qualifier |
|-------|-----------|
| `cnv/e2e` | `labels.exists(l, l=="CNV-E2E")` |
| `cnv/vm` | `tags["category"] == "cnv-vm"` |
| `cnv/storage` | `tags["category"] == "cnv-storage"` |
| `cnv/network` | `tags["category"] == "cnv-network"` |
| `cnv/migration` | `tags["category"] == "cnv-migration"` |
| `cnv/smoke` | `labels.exists(l, l=="SMOKE")` |

---

## Building

```bash
cd interop/test/ote
make build        # -> ./ote--interop
```

The Makefile runs:

```bash
GO_COMPLIANCE_POLICY="exempt_all" go build -ldflags "$(LDFLAGS)" -o ote--interop ./cmd/ote--interop/...
```

`GO_COMPLIANCE_POLICY="exempt_all"` disables FIPS policies for this test
binary — **do not set it globally**.

Other targets: `make clean`, `make test` (runs the default suite),
`make list`, `make validate` (info + list tests + list suites).

> **Note:** `go.mod` currently has
> `replace github.com/openshift-eng/openshift-tests-extension => ../../../`
> so it builds against your local OTE checkout. For CI this must be dropped in
> favor of a published pin (see [Remaining work](#remaining-work-to-be-productionci-ready)).

---

## Running & listing (CLI)

The binary speaks the standard OTE verbs: `info`, `list`, `run-suite`,
`run-test`, `update`, `images`.

```bash
# list all registered components
./ote--interop list components

# per component (ACM is the default, so --component is optional for ACM)
./ote--interop info        --component acm:layered-product:acm-tests
./ote--interop list suites --component quay:layered-product:quay-tests
./ote--interop list tests  --component odf:layered-product:odf-tests --output names

# list tests selected by a suite's qualifier (e.g. smoke)
./ote--interop list tests  --component acm:layered-product:acm-tests --suite acm/smoke --output names

# run a suite
./ote--interop run-suite acm/gre                                        # default component (acm)
./ote--interop run-suite quay/opp --component quay:layered-product:quay-tests
./ote--interop run-suite cnv/smoke --component cnv:layered-product:cnv-tests

# run a single test by exact name
./ote--interop run-test "[sig-acm-gre] ACM GRE harness is wired"
```

**Everything but `list components` operates on one component**, defaulting to the
first registered (ACM). To reach quay/acs/odf/cnv you must pass `--component`.

List all tests across every component:

```bash
for c in $(./ote--interop list components | jq -r '.[]|"\(.product):\(.type):\(.name)"'); do
  ./ote--interop list tests --component "$c" --output names
done
```

### Environment that makes tests actually run

Most non‑"wired" scenarios `skipIfEnvUnset` and skip offline. Provide the env to
run them:

| Product | Needs |
|---------|-------|
| acm, odf, cnv | `KUBECONFIG` (a cluster) |
| quay | `QUAY_URL` (and `QUAY_WEB_DIR` for the Playwright scenario) |
| acs | `ROX_ENDPOINT` (an ACS Central) |

---

## Adding tests and products

### Add a test to an existing product

1. Add a `ScenarioSpec` object to `test/interop/<product>/scenarios.json`.
2. `make build`.

That's it — no Go changes if it reuses existing categories/labels/suites.

### Add a new label (e.g. tag Quay into the OPP bundle)

1. Add the label string to the relevant scenarios' `labels` in their
   `scenarios.json`.
2. (Optional) add a suite in `main.go` to expose it by name
   (`labels.exists(l, l=="OPP")`).
3. `make build`.

### Add a new functional area (category) + suite

1. Give the new tests a new `category` value in the JSON.
2. Add a suite in `main.go`: `Qualifiers: []string{`tags["category"] == "<new>"`}`.
3. `make build`.

### Add a whole new product

1. Create `test/interop/<new>/scenarios.json` (scenarios with `"product":"<new>"`).
2. Add `<new>` to the `//go:embed` line in `test/interop/embed.go`.
3. In `main.go`, register the extension and its suites:
   ```go
   newExt := e.NewExtension("<new>", "layered-product", "<new>-tests")
   newExt.AddSuite(e.Suite{Name: "<new>/e2e", Qualifiers: []string{`labels.exists(l, l=="<NEW>-E2E")`}})
   // ...more suites...
   newExt.AddSpecs(byProduct["<new>"])
   registry.Register(newExt)
   ```
4. `make build`.

---

## How origin/openshift-tests uses this binary

OTE binaries are orchestrated by origin (`openshift-tests`). It does **not**
receive a pre‑baked catalog file; it asks the live binary:

1. Extracts/sets up the binary (in CI, typically from an image‑stream tag).
2. `<bin> info` — component metadata and suites.
3. `<bin> list` — the test catalog (names, labels, tags, lifecycle).
4. For each selected test: `<bin> run-test "<name>"` → the adapter execs the
   scenario's `command` in the test‑step pod.

The adapter inherits the test‑step pod's filesystem and environment
(`os.Environ()`), so kubeconfig/credentials/tooling (oc, pnpm, roxctl, …) must
already be present on that image/pod — origin does not supply them.

---

## Remaining work to be production/CI ready

This project implements the OTE protocol and the scenario‑JSON model, but a few
items from the `chaos-tests-extension` reference are not done yet:

- [ ] **Drop the local `replace`** in `go.mod`; pin a published
      `openshift-eng/openshift-tests-extension` version so the tree is
      CI‑cloneable.
- [ ] **`update` snapshots** — run `./ote--interop update` and commit the
      generated `.openshift-tests-extension/*.json` integrity guards.
- [ ] **Real runners** — scenario `command`s are placeholders
      (`echo`/sample `oc`/`pnpm`/`roxctl`). Replace with the real upstream
      invocations (Playwright, ocs-ci pytest, roxctl/qa-tests-backend, the ACM
      upgrade script).
- [ ] **CI packaging** — `images/Dockerfile.ci`, an `ote_wrapper.sh`, gzip the
      binary, and the `openshift/release` ci-operator + Prow config.
- [ ] **`OWNERS` / `LICENSE`** per the external‑repo conventions.

---

## Quick reference

```bash
make build                                   # build ./ote--interop
./ote--interop list components               # 5 components
./ote--interop run-suite acm/smoke           # default component = acm
./ote--interop run-suite cnv/vm   --component cnv:layered-product:cnv-tests
./ote--interop list tests --suite acm/opp --component acm:layered-product:acm-tests --output names
```

| Thing | Where |
|-------|-------|
| A product's tests | `test/interop/<product>/scenarios.json` |
| A product's component + suites | `cmd/ote--interop/main.go` |
| The exec adapter | `pkg/adapter/adapter.go` |
| Scenario embedding | `test/interop/embed.go` |

# `ote--interop` — Implementation Details

Complete reference for the OpenShift Tests Extension (OTE) interop binary: a
single Go binary that exposes the interop test catalogs for five Red Hat layered
products — **ACM, Quay, ACS, ODF, CNV** — using a **scenario‑JSON‑driven**
architecture with a generic exec adapter (no Ginkgo).

- **Module:** `github.com/stolostron/cluster-lifecycle-e2e/openshift-tests-ext`
- **Binary / project root:** `ote--interop` / `interop/test/ote/`
- **Go:** 1.23+ · **OTE framework:** `github.com/openshift-eng/openshift-tests-extension`
- **Totals:** 5 components · **47 tests** · **33 suites**

> Companion doc: `README.md` (quick‑start oriented). This file is the deep
> implementation reference and the current source‑of‑truth catalog snapshot.

---

## 1. Design summary

| Principle | Implementation |
|-----------|----------------|
| Tests are **data, not code** | Each product has `test/interop/<product>/scenarios.json`; a test = one JSON `ScenarioSpec`. |
| **One generic adapter** | `pkg/adapter` turns any `ScenarioSpec` into an OTE spec whose `Run` execs `command` as a subprocess. No per‑product branching. |
| **One binary, many components** | `main.go` registers one OTE extension per product (`<product>:layered-product:<product>-tests`), each with its own suites. |
| **No Ginkgo** | Specs are built from JSON; results come from subprocess exit codes. |
| **Embedded catalogs** | `//go:embed` ships all `scenarios.json` inside the binary. |

Data flow:

```
test/interop/<product>/scenarios.json
        │  //go:embed  (embed.go -> ScenarioFS)
        ▼
pkg/adapter.BuildSpecsByProductFS(ScenarioFS)     # walk + merge all JSON, group by "product"
        ▼
map[product] -> []*ExtensionTestSpec              # Run = exec(command)
        ▼
cmd/ote--interop/main.go                          # NewExtension + AddSuite + AddSpecs per product
        ▼
registry -> DefaultExtensionCommands              # info / list / run-suite / run-test / update / images
```

---

## 2. Repository layout

```
interop/test/ote/                          # PROJECT ROOT (go.mod)
├── ote--interop                           # compiled binary (build artifact)
├── go.mod / go.sum
├── Makefile
├── README.md                              # quick-start
├── IMPLEMENTATION.md                      # this file
├── cmd/
│   └── ote--interop/
│       └── main.go                        # extensions + suites + wiring
├── pkg/
│   └── adapter/
│       └── adapter.go                     # generic exec adapter
└── test/
    └── interop/
        ├── embed.go                       # //go:embed acm acs cnv odf quay
        ├── acm/scenarios.json             # 16 scenarios
        ├── quay/scenarios.json            # 7
        ├── acs/scenarios.json             # 8
        ├── odf/scenarios.json             # 9
        └── cnv/scenarios.json             # 7
```

---

## 3. Components

Registered in `main.go` in this order; **ACM is first → it is the `default`
component** (used when `--component` is omitted). All others require
`--component`.

| Component identifier (`--component`) | Dir | Tests | Suites | Upstream reference (modeled, not pulled) |
|--------------------------------------|-----|-------|--------|------------------------------------------|
| `acm:layered-product:acm-tests` (default) | `test/interop/acm/` | 16 | 10 | ACM / `stolostron`; OPP upgrade commands script |
| `quay:layered-product:quay-tests` | `test/interop/quay/` | 7 | 5 | `quay/quay` web Playwright e2e |
| `acs:layered-product:acs-tests` | `test/interop/acs/` | 8 | 6 | `stackrox/stackrox` qa-tests-backend |
| `odf:layered-product:odf-tests` | `test/interop/odf/` | 9 | 6 | `red-hat-storage/ocs-ci` (pytest) |
| `cnv:layered-product:cnv-tests` | `test/interop/cnv/` | 7 | 6 | KubeVirt / OpenShift Virtualization |

`list components` prints these five.

---

## 4. Scenario JSON schema

File shape: `{ "scenarios": [ ScenarioSpec, ... ] }`.

| Field | Type | Req | Meaning / effect |
|-------|------|-----|------------------|
| `name` | string | ✅ | OTE test name; convention `[sig-<product>-<area>] description`. Must be unique across the whole binary. |
| `product` | string | ✅ | Routes to a component. → tag `product`. |
| `category` | string | | Functional area. → tag `category`. |
| `labels` | []string | | Membership flags (scenario/depth/product): `OPP`, `ACM-VIRT`, `SMOKE`, `QUAY-E2E`, … |
| `lifecycle` | string | | `informing` (used throughout) or `blocking`. |
| `timeout` | string | | Go duration (`"30m"`); wraps the exec in a context timeout. |
| `include` | string | | CEL env gate (`platform=="aws"`); test runs only where true. |
| `command` | []string | ✅ | argv executed as a subprocess. |
| `env` | map[string]string | | Extra env for the subprocess. |
| `workDir` | string | | Subprocess working directory. |
| `skipIfEnvUnset` | []string | | Skip if any listed env var is unset. |

Example:

```json
{
  "name": "[sig-acm-upgrade] ACM subscription targets an upgrade channel",
  "product": "acm", "category": "acm-upgrade",
  "labels": ["OPP"], "lifecycle": "informing", "timeout": "30m",
  "include": "platform==\"aws\"", "skipIfEnvUnset": ["KUBECONFIG"],
  "command": ["bash","-c","oc get subscription -n ${ACM_SUBSCRIPTION_NAMESPACE:-open-cluster-management} advanced-cluster-management -o jsonpath='{.spec.channel}'"]
}
```

---

## 5. The exec adapter (`pkg/adapter/adapter.go`)

**Public API**

| Func | Purpose |
|------|---------|
| `BuildSpecsByProductFS(fsys fs.FS) (map[string]et.ExtensionTestSpecs, error)` | Walk a filesystem, merge every `*.json` manifest, group specs by `product`. Used with `ScenarioFS`. |
| `BuildSpecsByProduct(data []byte) (map[string]et.ExtensionTestSpecs, error)` | Same for a single manifest buffer. |

**Validation:** `name`, `product`, `command` required; duplicate `name` rejected;
invalid `timeout` rejected.

**Per‑scenario `Run`/`RunParallel` behavior**

1. If any `skipIfEnvUnset` var is empty → `skipped` (reason recorded).
2. Apply `timeout` via `context.WithTimeout`.
3. `exec.CommandContext(command[0], command[1:]...)` with `cmd.Dir = workDir`,
   `cmd.Env = os.Environ()` + `env`; combined stdout/stderr captured into
   `Output`.
4. Exit `0` → `passed`; non‑zero → `failed` (error recorded).

It also sets `Lifecycle`, `Timeout`, tags (`product`, `category`), `Labels`, and
`Include` (env gating) on the spec. The adapter is deliberately generic — adding
a product or test requires **no adapter changes**.

> Current limitation: the adapter maps only `product` and `category` into
> `tags`. Arbitrary JSON‑defined tags (e.g. a `subarea` key) would require a
> small extension here.

---

## 6. Selection model

Three independent axes; suites select across them.

| Axis | Mechanism | Values seen in this binary | CEL form |
|------|-----------|----------------------------|----------|
| Functional area | **tag** `category` | `acm-policy`, `odf-block`, `cnv-vm`, … | `tags["category"] == "..."` |
| Scenario / bundle | **label** | `OPP`, `ACM-VIRT`, plus product markers `QUAY-E2E`/`ACS-E2E`/`ODF-E2E`/`CNV-E2E` | `labels.exists(l, l=="OPP")` |
| Depth | **label** | `SMOKE` | `labels.exists(l, l=="SMOKE")` |

- **Tags** = key/value (dimensions with values).
- **Labels** = flat, stackable membership flags (a test can be `OPP` **and**
  `SMOKE`).
- A **suite** = named CEL qualifiers (OR'd). `AddSuite` auto‑ANDs a
  `source == "<component-id>"` guard so a suite only selects its own component's
  tests.
- Combine axes with `&&` in one qualifier (e.g. `acm/policy-smoke`).

CEL variables: `source`, `name`, `originalName`, `labels` (list), `tags` (map),
`codeLocations` (list).

---

## 7. Suites reference (qualifiers shown without the auto `source==` guard)

### ACM — `acm:layered-product:acm-tests` (10)
| Suite | Qualifier |
|-------|-----------|
| `acm/opp` | `labels.exists(l, l=="OPP")` |
| `acm/virt` | `labels.exists(l, l=="ACM-VIRT")` |
| `acm/upgrade` | `tags["category"] == "acm-upgrade"` |
| `acm/policy` | `tags["category"] == "acm-policy"` |
| `acm/policy-set` | `tags["category"] == "acm-policy-set"` |
| `acm/lifecycle` | `tags["category"] == "acm-lifecycle"` |
| `acm/e2e` | `tags["category"] == "acm-e2e"` |
| `acm/gre` | `tags["category"] == "acm-gre"` |
| `acm/smoke` | `labels.exists(l, l=="SMOKE")` |
| `acm/policy-smoke` | `tags["category"]=="acm-policy" && labels.exists(l,l=="SMOKE")` |

### Quay — `quay:layered-product:quay-tests` (5)
| Suite | Qualifier |
|-------|-----------|
| `quay/web-e2e` | `labels.exists(l, l=="QUAY-E2E")` |
| `quay/opp` | `labels.exists(l, l=="OPP")` |
| `quay/repository` | `tags["category"] == "quay-repository"` |
| `quay/organization` | `tags["category"] == "quay-organization"` |
| `quay/robot` | `tags["category"] == "quay-robot"` |

### ACS — `acs:layered-product:acs-tests` (6)
| Suite | Qualifier |
|-------|-----------|
| `acs/qa-e2e` | `labels.exists(l, l=="ACS-E2E")` |
| `acs/vulnerability` | `tags["category"] == "acs-vulnerability"` |
| `acs/compliance` | `tags["category"] == "acs-compliance"` |
| `acs/network` | `tags["category"] == "acs-network"` |
| `acs/admission` | `tags["category"] == "acs-admission"` |
| `acs/smoke` | `labels.exists(l, l=="SMOKE")` |

### ODF — `odf:layered-product:odf-tests` (6)
| Suite | Qualifier |
|-------|-----------|
| `odf/ocs-ci` | `labels.exists(l, l=="ODF-E2E")` |
| `odf/block` | `tags["category"] == "odf-block"` |
| `odf/file` | `tags["category"] == "odf-file"` |
| `odf/object` | `tags["category"] == "odf-object"` |
| `odf/cephhealth` | `tags["category"] == "odf-cephhealth"` |
| `odf/smoke` | `labels.exists(l, l=="SMOKE")` |

### CNV — `cnv:layered-product:cnv-tests` (6)
| Suite | Qualifier |
|-------|-----------|
| `cnv/e2e` | `labels.exists(l, l=="CNV-E2E")` |
| `cnv/vm` | `tags["category"] == "cnv-vm"` |
| `cnv/storage` | `tags["category"] == "cnv-storage"` |
| `cnv/network` | `tags["category"] == "cnv-network"` |
| `cnv/migration` | `tags["category"] == "cnv-migration"` |
| `cnv/smoke` | `labels.exists(l, l=="SMOKE")` |

---

## 8. Full test catalog (current snapshot — 47 tests)

Format: `category | labels | name`.

### ACM (16)
```
acm-upgrade     OPP,SMOKE        [sig-acm-upgrade] ACM upgrade harness is wired
acm-upgrade     OPP              [sig-acm-upgrade] ACM subscription targets an upgrade channel
acm-upgrade     OPP              [sig-acm-upgrade] MultiClusterHub reports healthy after upgrade
acm-policy      OPP,SMOKE        [sig-acm-policy] ACM policy harness is wired
acm-policy      OPP              [sig-acm-policy] ACM governance policy framework is installed
acm-e2e         OPP,SMOKE        [sig-acm-e2e] ACM e2e harness is wired
acm-e2e         OPP              [sig-acm-e2e] ACM managed cluster import workflow succeeds
acm-gre         OPP,SMOKE        [sig-acm-gre] ACM GRE harness is wired
acm-gre         OPP              [sig-acm-gre] ACM GRE reporting is enabled
acm-e2e         ACM-VIRT,SMOKE   [sig-acm-e2e] ACM+Virt harness is wired
acm-e2e         ACM-VIRT         [sig-acm-e2e] ACM imports a cluster running OpenShift Virtualization
acm-policy      ACM-VIRT         [sig-acm-policy] ACM policy governs VirtualMachine resources
acm-lifecycle   OPP,SMOKE        [sig-acm-lifecycle] lifecycle harness is wired
acm-lifecycle   OPP              [sig-acm-lifecycle] managed cluster create and destroy
acm-policy-set  OPP,SMOKE        [sig-acm-policy-set] policy-set harness is wired
acm-policy-set  OPP              [sig-acm-policy-set] PolicySet applies grouped policies
```

### Quay (7) — all `OPP`,`QUAY-E2E`
```
quay-repository    [sig-quay-repository] Quay web e2e harness is wired   (+SMOKE)
quay-repository    [sig-quay-repository] create and browse a repository
quay-repository    [sig-quay-repository] push and list image tags
quay-organization  [sig-quay-organization] create an organization
quay-organization  [sig-quay-organization] manage team membership
quay-robot         [sig-quay-robot] create a robot account
quay-robot         [sig-quay-robot] grant robot repository permissions
```

### ACS (8) — all `ACS-E2E`
```
acs-vulnerability  [sig-acs-vulnerability] ACS e2e harness is wired   (+SMOKE)
acs-vulnerability  [sig-acs-vulnerability] Scanner reports image vulnerabilities
acs-compliance     [sig-acs-compliance] compliance harness is wired   (+SMOKE)
acs-compliance     [sig-acs-compliance] compliance scan produces results
acs-network        [sig-acs-network] network graph renders flows
acs-network        [sig-acs-network] network policy simulation applies
acs-admission      [sig-acs-admission] admission harness is wired      (+SMOKE)
acs-admission      [sig-acs-admission] admission controller blocks a violating deployment
```

### ODF (9) — all `ODF-E2E`
```
odf-cephhealth  [sig-odf-cephhealth] ODF e2e harness is wired          (+SMOKE)
odf-cephhealth  [sig-odf-cephhealth] Ceph cluster reports HEALTH_OK
odf-block       [sig-odf-block] block harness is wired                 (+SMOKE)
odf-block       [sig-odf-block] RBD PVC provisions and binds
odf-file        [sig-odf-file] CephFS PVC provisions and binds
odf-file        [sig-odf-file] CephFS supports ReadWriteMany
odf-object      [sig-odf-object] object harness is wired               (+SMOKE)
odf-object      [sig-odf-object] NooBaa object bucket claim provisions
odf-object      [sig-odf-object] RGW S3 endpoint is reachable
```

### CNV (7) — all `CNV-E2E`
```
cnv-vm         [sig-cnv-vm] CNV e2e harness is wired                   (+SMOKE)
cnv-vm         [sig-cnv-vm] a VirtualMachine starts and reaches Running
cnv-storage    [sig-cnv-storage] storage harness is wired             (+SMOKE)
cnv-storage    [sig-cnv-storage] a DataVolume imports and binds
cnv-network    [sig-cnv-network] network harness is wired             (+SMOKE)
cnv-network    [sig-cnv-network] a VM attaches to a secondary network
cnv-migration  [sig-cnv-migration] live migration completes
```

---

## 9. Build

```bash
cd interop/test/ote
make build         # -> ./ote--interop
```

Underlying command (Makefile):

```bash
GO_COMPLIANCE_POLICY="exempt_all" go build -ldflags "$(LDFLAGS)" -o ote--interop ./cmd/ote--interop/...
```

- `GO_COMPLIANCE_POLICY="exempt_all"` disables FIPS policies for this **test**
  binary; never set it globally.
- `LDFLAGS` stamp version metadata into the OTE framework's `pkg/version`.
- Other targets: `make clean`, `make test`, `make list`, `make validate`.

**go.mod note:** currently uses
`replace github.com/openshift-eng/openshift-tests-extension => ../../../`
(local checkout). Must be replaced with a published pin for CI.

---

## 10. CLI usage

Verbs: `info`, `list`, `run-suite`, `run-test`, `update`, `images`.
All except `list components` operate on one component (default = ACM).

```bash
./ote--interop list components

# metadata / catalog for a component
./ote--interop info        --component acs:layered-product:acs-tests
./ote--interop list suites --component cnv:layered-product:cnv-tests
./ote--interop list tests  --component odf:layered-product:odf-tests --output names

# list by qualifier (use the suite whose qualifier you want)
./ote--interop list tests  --component acm:layered-product:acm-tests --suite acm/smoke --output names
./ote--interop list tests  --component acm:layered-product:acm-tests --suite acm/policy-set --output names

# run
./ote--interop run-suite acm/lifecycle                                   # ACM = default component
./ote--interop run-suite quay/opp  --component quay:layered-product:quay-tests
./ote--interop run-test  "[sig-cnv-vm] CNV e2e harness is wired" --component cnv:layered-product:cnv-tests
```

List every test across all components:

```bash
for c in $(./ote--interop list components | jq -r '.[]|"\(.product):\(.type):\(.name)"'); do
  ./ote--interop list tests --component "$c" --output names
done
```

**Env to actually run (otherwise `skipIfEnvUnset` skips):**

| Product | Env |
|---------|-----|
| acm, odf, cnv | `KUBECONFIG` |
| quay | `QUAY_URL` (`QUAY_WEB_DIR` for Playwright) |
| acs | `ROX_ENDPOINT` |

---

## 11. Maintenance recipes

| Task | Steps |
|------|-------|
| Add a test | Add a `ScenarioSpec` to `test/interop/<product>/scenarios.json`; `make build`. |
| Add a label (e.g. `OPP`) | Add the string to the scenarios' `labels`; optionally add a `*/opp` suite in `main.go`; `make build`. |
| Add a functional area | New `category` value in JSON + a suite in `main.go` with `tags["category"]=="<new>"`; `make build`. |
| Add a product | New `test/interop/<new>/scenarios.json`; add `<new>` to `//go:embed` in `embed.go`; add the extension + suites in `main.go`; `make build`. |
| Wire a real runner | Replace the scenario `command` with the real invocation (Playwright/pytest/roxctl/oc/script); ensure its tooling is on the test‑step image. |

---

## 12. How origin consumes it

Origin (`openshift-tests`) does not get a pre‑baked catalog; it queries the live
binary: `info` → suites/metadata, `list` → catalog, then `run-test "<name>"` per
selected test. The adapter execs the scenario `command` inheriting the
test‑step pod's filesystem/env (`os.Environ()`), so kubeconfig, credentials, and
tooling (oc, pnpm, roxctl, …) must already be present on that image/pod — origin
does not provide them.

---

## 13. Gaps to production/CI parity

Relative to the `chaos-tests-extension` reference:

- [ ] Drop the local `replace` in `go.mod`; pin a published OTE version
      (CI‑cloneable).
- [ ] Generate and commit `update` snapshots
      (`.openshift-tests-extension/*.json` integrity guards) via
      `./ote--interop update`.
- [ ] Replace placeholder `command`s with real upstream runners.
- [ ] CI packaging: `images/Dockerfile.ci`, `ote_wrapper.sh`, gzip the binary,
      and `openshift/release` ci-operator + Prow config.
- [ ] Add `OWNERS` / `LICENSE`.
- [ ] (Optional) extend the adapter to pass arbitrary JSON tags (e.g. a
      `subarea` dimension) beyond `product`/`category`.

---

*Snapshot generated from the live binary: 5 components, 47 tests, 33 suites.*

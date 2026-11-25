---
title: Governing agent-written code
nav_order: 7
---

# Governing agent-written code
{: .no_toc }

An ADR compliance harness for workloads written by AI coding agents, built on this stack.
{: .fs-6 .fw-300 }

1. TOC
{:toc}

## In short

A coding agent wrote and deployed an application in 13 iterations on 5 and 6 November 2026. Its code was not reviewed line by line. After each deployment the harness checked the running system against the platform team's architecture decision records (ADRs) and sent the findings back to the agent. In the first iteration 9 of 16 ADRs were violated; in the last, 3 of 25. None of those three belongs to the application: one is a gap in the platform's own tier profile, one a provenance decision the platform accepted as a risk, and one is known vulnerabilities in base and third-party images. Several problems showed up only in runtime and network evidence while the static checks passed: plaintext traffic between tiers, capability use inside a database container that had dropped all capabilities, and personal data leaving the namespace.


This page describes the harness behind the talk "Set the Terms for Your Agents and Let Your Humans Be Creative: How to Govern Code Nobody Reviewed" by Dr. Constanze Roedig and Thomas Schuetz (Platform Engineering Day, KubeCon + CloudNativeCon North America 2026). The harness lives in the public repository [k8sstormcenter/commons-grid-dynamics-manifest](https://github.com/k8sstormcenter/commons-grid-dynamics-manifest). It runs on the Kubernetes StormCenter (soc) stack.

All paths on this page are relative to that repository unless stated otherwise.

![Title slide: Set the Terms for Your Agents and Let Your Humans be Creative. How to Govern Code Nobody Reviewed. Dr. Constanze Roedig and Thomas Schuetz, Platform Engineering Day North America](img/adr-title-slide.png)

## The problem

AI coding agents can produce a whole application, with its Kubernetes manifests, in minutes. Often nobody reviews that code line by line. The application author may not be an engineer at all. The repository calls this person a "citizen coder".

The harness does not try to review the code. Instead:

- The platform team writes architecture decision records (ADRs). Each ADR states one decision, for example "no plaintext on the wire".
- Each ADR is tied to checks that the platform can run against the deployed workload: at admission, on the pod spec, at runtime (eBPF), and on the network.
- The coding agent deploys. The harness collects evidence from the running system and decides, per ADR, whether the decision holds.
- The findings go back to the coding agent as concrete fixes. The agent changes its code and manifest and deploys again.

The rule the evaluator follows is stated in `adr/README.md`: "No observation, no finding — and no observation, no pass." A finding carries the event that produced it. A pass carries what was examined. If evidence is missing, the result is `NOT_OBSERVED`, not a pass.

### The test fixture

The workload under test is Commons Grid Dynamics. It is a browser-side simulator of a mutual-credit ledger (agent-based model and ODE solver) that an AI agent wrote. Its source is in the private repository `k8sstormcenter/commons-grid-dynamics` (description: "vibecoded edge4 test fixture"). Its manifests, one per iteration, are in the public manifest repository (`deploy-iter0.yaml` … `deploy-iter12.yaml`).

Two agents take part:

- The coding agent writes the application and its manifests.
- A platform-side LLM agent on the target cluster ("edge4") applies the manifests, runs the harness, and relays the evaluator's findings to the coding agent. The README describes it as acting "as a deployment controller AND to relay the MCP's findings to the citizen-coder". The coding agent can also ask it about the cluster, for example which storage class exists or where the identity provider is.

A human also changed the requirements during the run: in iteration 3 (remove the database) and in iteration 6 (store runs in PostgreSQL, store only a keyed hash of the owner, state the lawful basis).

## How it works

### The loop

```
coding agent ── pushes deploy-iterN.yaml ──►  manifest repo
     ▲                                             │
     │ feedback: finding, decision broken, fix     ▼
platform agent ◄── adr_findings / MCP ── harness/loop.sh N
                                           1. record time (since)
                                           2. apply manifest
                                           3. static scan
                                           4. wait until every pod is ≥ 210 s old
                                           5. put load on the app
                                           6. evaluate all ADRs
                                           7. write kpi json + ClickHouse rows
                                           8. ask the MCP what the agent is told
```

One iteration is one run of `harness/loop.sh <N> [namespace] [manifest]` (defaults: namespace `commons-grid`, manifest `deploy-iter<N>.yaml`). The script:

1. Waits until the sensor DaemonSet `honey/node-agent` is rolled out.
2. Records the start time in `artefacts/iter<N>-since` and applies the manifest.
3. Starts a static scan in the background: `compliance/scan.sh` runs `kubescape scan framework AllControls` on the namespace.
4. Waits until the youngest running pod is older than the warm-up (`WARMUP`, default 210 s). Network rules are only judged after this point.
5. Puts traffic on the application with `harness/load.sh` (`LOAD_SECONDS`, default 45), then waits `SETTLE` (default 20 s) for alerts and Pixie rows to land.
6. Evaluates every ADR: `compliance/adr_kpi.py <ns> --since <epoch> --scan /tmp/AllControls-<ns>.json --out artefacts/kpi-<ns>-iter<N>.json`.
7. Writes the result into ClickHouse table `forensic_db.adr_findings` (`compliance/kpi_to_ch.py`).
8. Calls the MCP server (`compliance/adr_mcp.py`) with `adr_architecture`, `adr_recheck` and `adr_violations`, and saves the answers in `artefacts/iter<N>-mcp.jsonl`. This is what the coding agent is told.

Evidence is filtered to pods that exist now and to detections that happened after the pod started. A previous revision's findings do not carry over into the next iteration.

The iteration-0 feedback tells the coding agent to expect the next feedback about five minutes after each push (`feedback/iter0-feedback.md`). Iterations 0 to 5 were evaluated on 2026-11-05 between 05:50 and 06:52 UTC.

The feedback also carries platform facts the agent cannot read from its manifest: how services are exposed, where the identity provider is and how to reach it in-cluster, that no Prometheus operator exists, and which namespaces NetworkPolicies must admit (`feedback/iter0-feedback.md`, section "THIS PLATFORM").

### Traffic

Runtime and wire checks need traffic. An edge that carried no traffic cannot be `COMPLIANT`. `harness/load.sh` picks the first available source:

| source | who writes it | when |
|---|---|---|
| `deploy-loadgen.yaml` | the coding agent: a k6 Deployment in namespace `<app>-load` that runs the test suite continuously | iteration 1 and later |
| `load/k6.js` | the coding agent: a k6 script derived from its functional tests, run as a Job | iteration 0 |
| `compliance/drive.py` | the harness: a browser stand-in (GET `/`, the page's scripts, the `/api` paths) | fallback |

Every request carries `User-Agent: adr-driver/<tool>` and `X-Test-Case: <use case>`. The proof for each edge names the use cases that exercised it. The coding agent was asked for this suite in the iteration-0 feedback (`harness/load/README.md`).

### Enforcement points

From `adr/README.md`:

| point | when | mechanism | what it sees |
|---|---|---|---|
| admission | before the pod exists | Kyverno mutate | the manifest: tier label, profile binding |
| static | any time | the pod spec; static scan controls | what was declared |
| runtime | while the container runs | node-agent (eBPF) + the tier ContainerProfile (SBOB) | processes, files, DNS, capabilities, network edges the profile does not declare |
| wire | while traffic flows | Pixie protocol tracers; the TLS tap for decrypted bodies | source, destination, port, path, encrypted or not; request and response bodies |

### Tier profiles (SBOBs) and admission

The platform cannot know the application in advance. It works with tiers: frontend, backend, middleware, database, and unclassified.

- `kyverno/02-label-tiers.yaml` (ClusterPolicy `assign-workload-tier`) sets `app.kubernetes.io/tier` and `kubescape.io/user-defined-profile: tier-<tier>` on every new pod. It picks the tier from the image name, then from the container port, else `unclassified`. A label the manifest already declares is not overwritten. The policy only mutates. It never blocks a deployment.
- `kyverno/01-clone-profiles.yaml` (ClusterPolicy `clone-tier-sbobs`) copies every ContainerProfile from namespace `sbob-library` into each new namespace. The file explains why: node-agent looks up the profile in the pod's own namespace, and a missing profile leaves the pod unwatched without an error.
- `kyverno/00-kyverno-rbac.yaml` lets Kyverno read and write ContainerProfiles.
- `sbobs/cp-tier-*.yaml` are the five tier profiles, built by `sbobs/compose.sh` from `sbobs/fragments/`. Each profile allows any process and any file. It still alerts on network edges the tier may not use, on capabilities outside a short list, on runtime tooling and package installs (`subtract-runtime-tooling.yaml`), on sensitive files (`subtract-sensitive-files.yaml`), and, outside the backend tier, on the ServiceAccount token (`subtract-cluster-credentials.yaml`).

The Kyverno folder contains mutate and generate policies only. Where an ADR names `kyverno.validate` as its enforcement point, the harness checks that ADR from the pod spec and the static scan.

The architecture prescribes these edges (`compliance/adrs.yaml`, `topology:`). Traffic on them is never a tier violation:

```
frontend -> backend        backend -> backend
backend -> database        database -> database
backend -> middleware      backend -> identity provider (ns:zitadel)
middleware -> database     every tier -> DNS
```

If a tier profile alerts on one of these edges, the profile has a gap. That is reported under ADR-0005 with `owner=platform`.

### The ADRs

There are 25 ADRs. Numbers 0008, 0009 and 0015 do not exist in `adr/`. ADR-0001 to ADR-0007 have status "accepted"; the others have status "proposed". ADR-0020 to ADR-0027 were added on 2026-11-06 (commit `f988992`), ADR-0028 later that day (commit `af816ac`).

| ADR | decision (from `adr/README.md`) | status | evidence the evaluator reads (`compliance/adrs.yaml`) |
|---|---|---|---|
| 0001 | Tiers are strictly layered; the presentation tier never reaches the data tier | accepted | runtime, wire |
| 0002 | The data tier never initiates outbound connections | accepted | runtime |
| 0003 | Only the backend tier holds cluster credentials | accepted | pod spec, runtime |
| 0004 | Images are immutable at runtime; nothing is installed after build | accepted | pod spec, runtime |
| 0005 | Every workload is classified and bound to its tier profile; an unrecognised one is quarantined | accepted | pod labels, runtime |
| 0006 | Workloads run as non-root | accepted | pod spec, static scan, runtime |
| 0007 | A profile wildcard never covers a protected path that the profile does not also subtract | accepted | tier profiles |
| 0010 | Every backend request is authenticated by the platform identity provider | proposed | evaluator probes, served page |
| 0011 | No plaintext on the wire | proposed | Service, Ingress, wire |
| 0012 | Metrics are served on a dedicated port, scraped only by the platform | proposed | pod spec, evaluator probes, wire |
| 0013 | Every workload declares resources, probes and security context | proposed | pod spec |
| 0014 | Images are pinned by digest, signed; no latest | proposed | pod spec, static scan |
| 0016 | Credentials are per workload, short-lived, never in environment variables or manifests | proposed | pod spec, Secrets, static scan |
| 0017 | A ServiceAccount holds only the permissions its code uses; nothing is bound to default | proposed | RBAC, runtime, static scan |
| 0018 | Unprivileged; no host path, no kernel module, no access to the cloud metadata API | proposed | pod spec, NetworkPolicy, runtime, wire, static scan |
| 0019 | Reachable only through the platform's tailnet exposure of the frontend Service | proposed | Service, Ingress, NetworkPolicy, pod spec |
| 0020 | Every image carries signed SLSA provenance from the platform build workflow | proposed | registry lookup per digest (provenance, signature) |
| 0021 | Every image publishes an SBOM and carries no critical or exploitable known vulnerability | proposed | registry lookup (SBOM), vulnerability scan |
| 0022 | Nothing is downloaded, installed or compiled after the container starts | proposed | runtime |
| 0023 | The namespace declares a record of processing (ConfigMap `gdpr-processing`) | proposed | ConfigMap |
| 0024 | The API and the wire carry no personal data beyond what is declared | proposed | `/openapi.json`, decrypted bodies |
| 0025 | Personal data never reaches logs, metrics labels or URLs | proposed | container logs |
| 0026 | A subject created through the API can be erased through the API | proposed | evaluator canary |
| 0027 | Personal data leaves the namespace only to the IdP, the data tier and declared processors | proposed | decrypted bodies, wire |
| 0028 | Personal identifiers reach the data tier only as keyed hashes or tokens | proposed | decrypted bodies on the database hop, evaluator canary |

What the evidence names mean:

| evidence | where it comes from |
|---|---|
| pod spec, pod labels, Service, Ingress, NetworkPolicy, Secrets, RBAC, tier profiles | `kubectl` reads of live objects |
| static scan | `compliance/scan.sh` → `/tmp/AllControls-<ns>.json` |
| runtime | node-agent detections in ClickHouse `forensic_db.kubescape_logs` (for example R0004 capabilities, R0011 unexpected egress, R0012 unexpected ingress) |
| wire | Pixie `http_events`, `pgsql_events`, `conn_stats` in ClickHouse |
| decrypted bodies | the TLS tap (`platform/dx-ktls-openssl.yaml`) → `forensic_db.dx_kubelet_stream` with `source='openssl'`, plus Pixie `http_events` / `pgsql_events` |
| evaluator probes | HTTP requests the evaluator sends: no token, a garbage token, a valid platform token; `/metrics` on the application port. In-cluster probe pods come from `platform/adr-probe.sh` |
| served page | the HTML/JS the frontend serves (API calls, auth markers) |
| registry lookup | referrers next to each image digest (provenance, signature, SBOM); verification needs `cosign` |
| evaluator canary | the evaluator creates a synthetic subject through the API, deletes it, and reads it back |

### Statuses, owners and discounts

| status | meaning |
|---|---|
| `VIOLATED` | at least one counted finding: the observed event, the decision it broke, the fix |
| `COMPLIANT` | every required evidence item was examined and is clean; the proof says what was examined |
| `NOT_OBSERVED` | evidence missing: pods younger than the warm-up, no traffic, no scan, a peer that cannot be attributed |

The `violations` number is the count of counted findings. Identical detections are collapsed into one finding with a count. For example, one ADR-0005 finding in iteration 5 stands for 4,700 R0012 events.

Each finding has an owner: `application` (the coding agent fixes it) or `platform` (the platform team fixes it). Only the platform can grant exceptions, in ConfigMap `sbob-library/adr-exceptions`. Excepted findings stay in the report with `counted=false`.

Some events are discounted and never make an ADR `VIOLATED` (`adr/README.md`): kubelet probes, the evaluator's own requests, departed peers during a rollout (these give `NOT_OBSERVED`), capabilities used by `runc` while creating the container, processes started by `kubectl exec` or exec probes, and processes whose parent is the Pixie tracer.

### Where findings land

| output | content |
|---|---|
| `artefacts/kpi-<ns>-iter<N>.json` | the full verdict (schema `adr-kpi/v2`): `source` (window, row counts, use cases), `summary`, `kpis`, `adrs[]` with proof and findings, `workloads`, `content` |
| `artefacts/iter<N>-mcp.jsonl` | the MCP answers the coding agent would get |
| `forensic_db.adr_findings` | one row per finding and one row per ADR without findings (DDL: `sql/adr_findings.sql`) |
| `forensic_db.adr_findings_grouped` | a view that groups rows by iteration, tool, ADR and broken decision (DDL: `sql/adr_findings_grouped.sql`) |
| `feedback/iter<N>-feedback.md` | the text sent to the coding agent, with operator notes |

Columns of `adr_findings`: `event_time`, `hostname`, `kpi_time`, `cluster`, `namespace`, `iteration`, `tool`, `adr`, `adr_summary`, `title`, `status`, `violations`, `counted`, `note`, `owner`, `proof`, `source`, `rule`, `workload`, `decision_broken`, `observed`, `fix`. The `tool` column says who wrote the row (for example `harness`, `rescore`, `slsa-gdpr-trial`, or the MCP tool name).

The MCP server (`compliance/adr_mcp.py`, stdio JSON-RPC) offers the same evaluator to the coding agent:

| tool | arguments | returns |
|---|---|---|
| `adr_compliance` | namespace, since_minutes | per-ADR status and proof |
| `adr_violations` | namespace, adr?, since_minutes | findings: observed, decision broken, fix, counted or discounted |
| `adr_explain` | adr | the decision text and its checks |
| `adr_architecture` | namespace | per workload: tier, how it was assigned, what it serves, its findings |
| `adr_recheck` | namespace, since_epoch | compliance for evidence after a redeploy |

Every evaluating call also writes its rows to `forensic_db.adr_findings`.

### Viewing findings in Pixie

The soc Pixie build can read ClickHouse tables with `px.DataFrame(..., clickhouse_dsn=...)`. This PxL script shows the findings of the last 30 minutes:

```python
import px

dsn = 'forensic_analyst:<password>@clickhouse-forensic-soc-db.clickhouse.svc.cluster.local:9000/forensic_db'

df = px.DataFrame('adr_findings', clickhouse_dsn=dsn, start_time='-30m')
px.display(df[['event_time', 'iteration', 'tool', 'adr', 'status', 'violations', 'decision_broken', 'observed', 'fix']], 'adr_findings')
```

Replace `<password>` with the password of the `forensic_analyst` user (see [Install](install.html#change-the-default-passwords)). Run the script in the Pixie UI script editor, or save it as a file and run `px run -f <file>`.

The repository has two more scripts:

- `pxl/adr_findings.pxl` shows more columns (`adr_summary`, `counted`, `note`, `proof`). Widen `START` (for example to `'-6h'`) to see several iterations.
- `pxl/adr_findings_grouped.pxl` reads the grouped view. It shows one status table per iteration and ADR, and one table of counted findings with the affected workloads. Set `ITERATION` to one number, or `-1` for all.

The evaluator writes the value of `ADR_PX_HOST` into the `hostname` column (default `edge4-server`, a node of the original cluster). A code comment in `compliance/adr_mcp.py` says Pixie's ClickHouse source filters on hostname = PEM node. Set `ADR_PX_HOST` to the name of a node that runs a Pixie PEM.

### Repository layout

| path | content |
|---|---|
| `adr/` | the ADR documents, generated by `compliance/adr_docs.py` |
| `compliance/` | the evaluator: `adrs.yaml` (checks), `adr_text.yaml` (prose), `engine.py`, `evidence.py`, `adr_kpi.py`, `adr_mcp.py`, `kpi_to_ch.py`, `scan.sh`, `drive.py` |
| `harness/` | `loop.sh` (one iteration), `load.sh` (traffic), `load/` (k6 template) |
| `kyverno/`, `sbobs/` | admission policies and tier profiles |
| `platform/` | platform CA, IdP client provisioning, probe pods, the TLS tap |
| `sql/`, `pxl/` | ClickHouse DDL and Pixie scripts |
| `deploy-iter*.yaml`, `deploy-loadgen.yaml`, `load/k6.js` | what the coding agent produced |
| `artefacts/` | KPI files, MCP transcripts, `since` files |
| `feedback/`, `reports/` | feedback per iteration; the SLSA/GDPR trial report |

## Findings

### Two rounds

- Round 1 ran in October 2026 (commits from 2026-10-23 to 2026-10-28, branch `demo`) with 15 ADRs and four iterations. The `demo` branch README reports 5, 6, 7, 12 and 14 of 15 ADRs compliant (iteration 1 was evaluated twice). The evaluator and the ADR set differ from round 2.
- Round 2 ran from 2026-11-05 to 2026-11-07 (branch `kcna26colo`, merged into `main`). It is what `main` holds and what the rest of this section describes.

The evaluator changed during round 2 (commits marked `r12` to `r26`). Some iterations were scored again with a newer evaluator; their files end in `-rescore` or carry an `r24`/`r25` suffix. Counts from different evaluator versions are not strictly comparable.

### Iterations of round 2

V/C/N = VIOLATED / COMPLIANT / NOT_OBSERVED. Times are UTC, from `generated_at` in each file.

| iteration | evaluated | manifest commit | change (from the commit message) | ADRs | V/C/N | file in `artefacts/` |
|---|---|---|---|---|---|---|
| 0 | 2026-11-05 05:50 | `2a8f24d` | one nginx pod, NodePort Service | 16 | 9/3/4 | `kpi-commons-grid-iter0.json` |
| 1 | 2026-11-05 06:17 | `558fad5` | split into frontend, backend, database (PostgreSQL); digest pins; k6 script | 16 | 8/6/2 | `kpi-commons-grid-iter1.json` |
| 2 | 2026-11-05 06:31 | `18c3936` | security envelope on all three; bearer-token auth; continuous load generator | 16 | 7/7/2 | `kpi-commons-grid-iter2.json` |
| 3 | 2026-11-05 06:37 | `34c9391` | database removed (human request) | 16 | 6/9/1 | `kpi-commons-grid-iter3.json` |
| 4 | 2026-11-05 06:42 | `0df7f4a` | frontend TLS, tailnet exposure, NetworkPolicies, IdP client as files | 16 | 4/11/1 | `kpi-commons-grid-iter4.json` |
| 5 | 2026-11-05 06:52 | `401bd87` | backend TLS on 8443; namespace audience accepted | 16 | 3/12/1 | `kpi-commons-grid-iter5.json` |
| 5t | 2026-11-06 06:40 | `401bd87` (unchanged) | 8 new ADRs (0020–0027) tried on the running iteration 5 | 24 | 7/16/1 | `kpi-commons-grid-iter5-slsa-gdpr.json` |
| 6r | 2026-11-06 08:40 | `276635c`, `8125156` | PostgreSQL with TLS and a volume (human request); owner stored as keyed hashes; `gdpr-processing` ConfigMap | 25 | 7/17/1 | `kpi-commons-grid-iter6-rescore.json` |
| 7r | 2026-11-06 08:57 | `c69cc3d` | schema migration at start; `/openapi.json`; exporter probes | 25 | 5/20/0 | `kpi-commons-grid-iter7-rescore.json` |
| 8 | 2026-11-06 09:09 | `3cb9129` | exporter over the Unix socket; `/metrics` off the application port; newer images | 25 | 5/20/0 | `kpi-commons-grid-iter8.json` |
| 9 | 2026-11-06 09:24 | `0be8567` | PostgreSQL started directly as uid 70 | 25 | 3/20/2 | `kpi-commons-grid-iter9.json` |
| 10r | 2026-11-06 15:45 | `9b8dea5` | database strategy `Recreate`; pinned backend dependencies | 25 | 3/22/0 | `kpi-commons-grid-iter10-rescore.json` |
| 11 | – | `2f0ac58` | both images rebuilt on current base images | – | no file | – |
| 12 | 2026-11-06 17:32 | `8d89669` | web image with upgraded curl, libcurl, brotli-libs | 25 | 3/22/0 | `kpi-commons-grid-iter12.json` |
| 12f | 2026-11-07 05:45 | `8d89669` (unchanged) | final re-score with evaluator update r25 | 25 | 3/22/0 | `kpi-commons-grid-iter12-piiclass-r25.json` |

The iteration-5 feedback states that every ADR owned by the application author was compliant at that point (`feedback/iter5-feedback.md`). It lists the three remaining violations as one platform item (ADR-0005) and two evaluator defects (ADR-0006, ADR-0016; see below).

### Status per ADR and iteration

`C` = COMPLIANT, `N` = NOT_OBSERVED, `Vn` = VIOLATED with n counted findings, `–` = ADR not defined yet. Column labels as in the table above. Source: the `kpis` array of each KPI file listed above.

| ADR | 0 | 1 | 2 | 3 | 4 | 5 | 5t | 6r | 7r | 8 | 9 | 10r | 12 | 12f |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0001 | N | N | N | C | C | C | C | C | C | C | C | C | C | C |
| 0002 | N | C | C | N | N | N | N | C | C | C | C | C | C | C |
| 0003 | **V1** | **V2** | C | C | C | C | C | C | C | C | C | C | C | C |
| 0004 | **V1** | **V3** | **V1** | **V1** | C | C | C | C | C | C | C | C | C | C |
| 0005 | **V1** | C | C | **V1** | **V1** | **V1** | **V1** | **V1** | **V1** | **V2** | **V1** | **V2** | **V1** | **V1** |
| 0006 | **V2** | **V6** | **V1** | C | C | **V5** | C | C | C | **V8** | C | C | C | C |
| 0007 | C | C | C | C | C | C | C | C | C | C | C | C | C | C |
| 0010 | N | **V4** | **V3** | C | **V3** | C | C | C | C | C | C | C | C | C |
| 0011 | **V1** | N | N | **V13** | **V6** | C | C | C | C | C | C | C | C | C |
| 0012 | N | **V1** | **V1** | C | C | C | **V1** | **V1** | **V1** | C | C | C | C | C |
| 0013 | **V6** | **V18** | C | C | C | C | C | **V2** | **V2** | C | C | C | C | C |
| 0014 | **V1** | C | C | C | C | C | C | C | C | C | C | C | C | C |
| 0016 | C | C | **V1** | **V1** | **V1** | **V1** | C | C | C | C | C | C | C | C |
| 0017 | C | C | C | C | C | C | C | C | C | C | C | C | C | C |
| 0018 | **V1** | **V1** | **V1** | **V1** | C | C | C | C | C | C | C | C | C | C |
| 0019 | **V3** | **V2** | **V2** | **V2** | C | C | C | C | C | C | C | C | C | C |
| 0020 | – | – | – | – | – | – | **V2** | **V4** | **V4** | **V4** | **V4** | **V4** | **V4** | **V4** |
| 0021 | – | – | – | – | – | – | **V6** | **V9** | **V9** | **V5** | **V8** | **V9** | **V8** | **V10** |
| 0022 | – | – | – | – | – | – | C | C | C | C | C | C | C | C |
| 0023 | – | – | – | – | – | – | **V1** | C | C | C | C | C | C | C |
| 0024 | – | – | – | – | – | – | **V1** | N | C | C | C | C | C | C |
| 0025 | – | – | – | – | – | – | C | C | C | C | C | C | C | C |
| 0026 | – | – | – | – | – | – | **V1** | **V1** | C | C | N | C | C | C |
| 0027 | – | – | – | – | – | – | C | **V5** | C | **V2** | C | C | C | C |
| 0028 | – | – | – | – | – | – | – | C | C | C | N | C | C | C |
| V/C/N | 9/3/4 | 8/6/2 | 7/7/2 | 6/9/1 | 4/11/1 | 3/12/1 | 7/16/1 | 7/17/1 | 5/20/0 | 5/20/0 | 3/20/2 | 3/22/0 | 3/22/0 | 3/22/0 |

In iterations 0 to 2 most counted findings came from the pod spec, Services and NetworkPolicies. For example, iteration 1 had 18 ADR-0013 findings (missing requests, limits, probes, seccomp, dropped capabilities on three containers). From iteration 5t on, ADR-0020 and ADR-0021 (registry and vulnerability evidence) account for most counted findings. Iteration 8 is the exception: 9 of its 21 counted findings belong to ADR-0020 and ADR-0021, 8 to ADR-0006.

### What runtime and wire evidence found that static checks did not

Each item below was found from the running system: sensor events, Pixie or TLS-tap traffic, or the evaluator's own requests. None of these findings came from the pod spec, the Kubernetes objects or the static scan.

- **Plaintext between tiers (ADR-0011), iterations 3 and 4.** The Services were `ClusterIP`, so the Service check found nothing. Pixie recorded plaintext HTTP (`encrypted=0`) from the frontend to the backend on port 8000 and from the load namespace to the frontend on port 8080: 13 counted findings out of 55 wire rows in iteration 3, 6 findings out of 50 wire rows in iteration 4. The backend moved to TLS on 8443 in iteration 5. In iterations 1 and 2 this ADR was `NOT_OBSERVED`, because no wire rows were exported for the namespace (a platform-side issue named in `feedback/iter1-feedback.md`). Files: `artefacts/kpi-commons-grid-iter3.json`, `artefacts/kpi-commons-grid-iter4.json`, `feedback/iter3-feedback.md`, `feedback/iter4-feedback.md`.
- **Capability events in the database container (ADR-0006), iterations 2 and 8.** In both manifests the `postgres` container declared `runAsNonRoot: true`, `runAsUser: 70`, `allowPrivilegeEscalation: false` and `capabilities.drop: [ALL]`, and the pod spec checks passed. The sensor rule R0004 ("Unexpected capability used") still fired in that container: 1 finding in iteration 2 (`CAP_SETUID` by `bash`), 8 findings in iteration 8 (`CAP_SETUID`, `CAP_SETGID`, `CAP_FOWNER` by the image entrypoint and `bash`). The evaluator's text for these findings is "it starts as root and drops"; the feedback names the postgres entrypoint (`docker-entrypoint.sh`/`gosu`). Iteration 9 no longer runs the image entrypoint: an `initdb` init container prepares the data directory and the main container starts PostgreSQL directly. ADR-0006 was compliant from then on. Files: `artefacts/kpi-commons-grid-iter2.json`, `artefacts/kpi-commons-grid-iter8.json`, `feedback/iter8-feedback.md`, `deploy-iter8.yaml`, `deploy-iter9.yaml`.
- **Authentication that does not work (ADR-0010), iterations 1, 2 and 4.** These came from the evaluator's HTTP probes, not from eBPF. Iteration 1: the backend answered 200 without a token on `/api/runs`, `/api/runs/` and `/api/simulations`, and the served page called the backend without authentication. Iteration 2: a valid platform token got 503, because the backend could not fetch the IdP's keys. Iteration 3 passed. Iteration 4: a valid token got 401, because the accepted audience list no longer contained the namespace's own project. Iteration 5 passed. Files: `artefacts/kpi-commons-grid-iter1.json`, `-iter2.json`, `-iter4.json`, `feedback/iter2-feedback.md`, `feedback/iter4-feedback.md`.
- **Personal data in decrypted traffic (ADR-0024, 0027, 0028).** None of this is visible in a manifest.
  - Iteration 5t: an e-mail address in a request body while no record of processing existed (ADR-0024, 1 finding). File: `artefacts/kpi-commons-grid-iter5-slsa-gdpr.json`.
  - Iteration 6r: e-mail addresses and the evaluator's canary in traffic from the frontend to peers outside the namespace: the load namespace, the evaluator, and two peers the evaluator could not attribute (ADR-0027, 5 findings). File: `artefacts/kpi-commons-grid-iter6-rescore.json`.
  - Iteration 7r: the feedback reports 75,115 bodies inspected on three legs with no undeclared class (ADR-0024); the KPI proof lists 55,370 and 19,745 rows from the TLS tap and 1 from Pixie. On the backend→database hop 19,745 statements and rows were inspected, and the canary owner appeared only as a hash (ADR-0028). Files: `artefacts/kpi-commons-grid-iter7-rescore.json`, `feedback/iter7-feedback.md`.
- **Erasure (ADR-0026), evaluator canary.** Iteration 5t: `POST /api/runs` returned 201, `DELETE` returned 501 Not Implemented. Identifiers were sequential (informational note). Iteration 7r: POST 201, DELETE 204, GET 404. Files: `artefacts/kpi-commons-grid-iter5-slsa-gdpr.json`, `feedback/iter5-slsa-gdpr-feedback.md`, `feedback/iter7-feedback.md`.
- **A gap in the platform's own tier profile (ADR-0005, owner platform).** Labels and profile bindings passed in every iteration from 1 on. The sensor still raised R0012 ("unexpected ingress") on the backend for frontend→backend traffic on port 8443, a prescribed edge. One finding stood for 4,700 events in iteration 5, 10,875 events in iteration 12 (600 s window), and 47,241 events in the final re-score (2,729 s window). The iteration-5 feedback names the cause: the backend tier profile declared the edge on port 8000, and the hop moved to 8443. R0011 ("unexpected egress") from the backend to the IdP (`ns:zitadel`, port 8080) appears in iterations 3, 4, 8 and 10r. Files: `artefacts/kpi-commons-grid-iter5.json`, `-iter12.json`, `-iter12-piiclass-r25.json`, `feedback/iter5-feedback.md`.
- **A data-loss incident that no ADR covered, iteration 9.** The new database pod crash-looped with PostgreSQL PANIC "could not locate a valid checkpoint record". The feedback attributes it to a `RollingUpdate` that ran two instances on one `ReadWriteOnce` volume. ADR-0026 and ADR-0028 were `NOT_OBSERVED` because no canary could be written. Iteration 10 switched the database to `strategy: Recreate`. The feedback proposes a new platform ADR: "a data-tier Deployment never rolls two instances onto one RWO volume". File: `feedback/iter9-feedback.md`.

### Findings the operator marked as evaluator defects

The rows stay in `adr_findings` as evidence. The evaluator was changed afterwards.

| ADR | iteration | what happened | fix | source |
|---|---|---|---|---|
| 0016 | 4, 5 | the environment variable name `IDP_SECRET_DIR` was flagged; its value is a path | judge the value, not the name | `feedback/iter4-feedback.md`, `reports/slsa-gdpr-trial-2026-11-06.md` |
| 0006 | 5 | 5 findings were capability use by `runc` while creating the container | new discount `container_start` | `feedback/iter5-feedback.md`, `reports/slsa-gdpr-trial-2026-11-06.md` |
| 0027 | 8 | a listening socket (`::` and `0.0.0.0`, port 65535) was read as an external peer | fixed in `compliance/evidence.py` | `feedback/iter8-feedback.md` |
| 0025 | interim score of 12 | a UUID in an `/api/runs/<id>` URL passed the card-number test | the classifier now rejects digit runs bounded by hex letters | `feedback/iter12-feedback.md` |

### Final state (iteration 12)

Result: 3 VIOLATED / 22 COMPLIANT / 0 NOT_OBSERVED (`artefacts/kpi-commons-grid-iter12.json`, `feedback/iter12-feedback.md`). All GDPR ADRs (0023 to 0028) are compliant. The three open items:

- **ADR-0005** (platform): the tier-profile gap described above.
- **ADR-0020** (4 findings): the two application images carry provenance, but it cannot be verified against the platform builder identity (the evaluator host had no `cosign`). The PostgreSQL and exporter images carry no provenance. The app commit `d621b84` says the attestation step fails on the private repository with the current plan. The iteration-12 feedback records this as a platform decision and an accepted risk: provenance will not be implemented and repository visibility will not change.
- **ADR-0021** (8 findings): backend 0 critical, 60 HIGH (15 relevant); per the feedback, all in Debian base-OS packages, 59 marked "won't fix". Web image 0 critical, 5 HIGH (1 relevant), down from 15 critical and 39 HIGH before the curl, libcurl and brotli-libs upgrade. `postgres:16-alpine` 11 critical, 108 HIGH (56 relevant). `postgres-exporter` 14 critical, 70 HIGH (69 relevant). Neither third-party image has an SBOM next to its digest.

## How to reproduce

### Prerequisites

The soc stack, installed by the TL;DR section of the [soc README](https://github.com/k8sstormcenter/soc):

- Tools: `kubectl`, `helm`, `skaffold` v2, `openssl`, `git`, and kernel headers for the running kernel (Pixie).
- Nodes with at least 7 GiB memory (Pixie reserves 2 GiB on every node, ClickHouse 2 GiB on one) and about 60 GB disk in a small setup.
- Pixie deployed against the soc cloud (`PX_CLOUD_ADDR=soc.k8sstormcenter.com`, `--vizier_version 0.14.19-pemdq1`), then `skaffold deploy -m soc-alpha` for ClickHouse, the runtime sensor, the adaptive exporter and dx.
- Check: pods in namespaces `pl`, `honey` and `clickhouse` are running, and `SELECT count() FROM forensic_db.kubescape_logs` returns rows.

ADR-0021 also reads results from the sensor's vulnerability scan. The trial report enabled the scan for its second run (`reports/slsa-gdpr-trial-2026-11-06.md`). On soc `main`, `tree/kubescape/values.yaml` sets `capabilities.vulnerabilityScan: disable` and `capabilities.relevancy: disable` (checked 2026-11-25), so it has to be switched on.

Platform components the harness expects (from `platform/`, the manifests and the `demo` branch README):

- Kyverno and cert-manager. The `demo` branch README installs Kyverno chart 3.9.2 and cert-manager v1.19.3.
- The platform CA: `kubectl apply -f platform/platform-ca.yaml` (ClusterIssuer `platform-ca`, ADR-0011).
- ZITADEL in namespace `zitadel`, Service `zitadel` on port 8080, with Secret `iam-admin-pat` (read by `platform/idp-client.sh`, ADR-0010).
- The Tailscale operator with proxies in namespace `tailscale-system` (ADR-0019).
- A namespace `monitoring` (the platform scrapes the metrics ports from there).
- Node-agent rule R0002 enabled in the stack's default rules (ADR-0004; `demo` branch README).

On the machine that runs the harness: `kubectl` access to the cluster, `python3` with PyYAML, the scanner CLI that `compliance/scan.sh` installs if missing, and optionally `cosign` (without it, provenance is reported as "not verifiable").

### Commands

```sh
git clone https://github.com/k8sstormcenter/commons-grid-dynamics-manifest
cd commons-grid-dynamics-manifest

# tier profiles (SBOBs) and admission policies
kubectl create namespace sbob-library --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f sbobs/cp-tier-backend.yaml -f sbobs/cp-tier-database.yaml \
  -f sbobs/cp-tier-frontend.yaml -f sbobs/cp-tier-middleware.yaml -f sbobs/cp-tier-unclassified.yaml
kubectl apply -f kyverno/                      # RBAC first, then clone + label policies
kubectl apply -f platform/platform-ca.yaml

# findings table and grouped view in ClickHouse
CH=$(kubectl -n clickhouse get pod -l clickhouse.altinity.com/chi=forensic-soc-db -o name | head -1)
kubectl -n clickhouse exec -i "$CH" -- clickhouse-client --multiquery < sql/adr_findings.sql
kubectl -n clickhouse exec -i "$CH" -- clickhouse-client --multiquery < sql/adr_findings_grouped.sql

# application namespaces, IdP clients, probe pods
kubectl create namespace commons-grid
kubectl create namespace commons-grid-load
./platform/idp-client.sh commons-grid
./platform/idp-client.sh commons-grid-load
./platform/adr-probe.sh commons-grid           # probe pods in commons-grid-load and monitoring

# optional: the TLS tap, needed for ADR-0024, 0027 and 0028 (read the warning below first)
kubectl apply -f platform/dx-ktls-openssl.yaml

# evaluator settings
export ADR_CH="http://ingest_writer:<password>@$(kubectl -n clickhouse get pod \
  -l clickhouse.altinity.com/chi=forensic-soc-db -o jsonpath='{.items[0].status.podIP}'):8123"
export ADR_PX_HOST=<name of a node that runs a Pixie PEM>

# one iteration: namespace commons-grid, manifest deploy-iter12.yaml
./harness/loop.sh 12
```

The `ADR_CH` line needs a route from your machine to the pod IP. Otherwise use `kubectl port-forward` to port 8123 and `127.0.0.1`. Use the password of the `ingest_writer` user.

To evaluate without applying anything, or to give a coding agent the evaluator:

```sh
python3 compliance/adr_kpi.py commons-grid --since <epoch> \
  --scan /tmp/AllControls-commons-grid.json --out kpi.json
claude mcp add adr -e ADR_CH="$ADR_CH" -- python3 compliance/adr_mcp.py   # from the demo branch README
```

The same loop works for another application: `./harness/loop.sh <N> <namespace> <manifest>`. Run `platform/idp-client.sh` for that namespace first.

### Values specific to the original cluster

The committed manifests will not run unchanged on another cluster:

- The two application images (`ghcr.io/k8sstormcenter/commons-grid-dynamics` and `…-backend`) and the TLS tap image (`docker.io/tanzeee/dx-ktls`) could not be pulled without credentials on 2026-11-25 (checked with `crane manifest`; `grafana/k6` pulled as a control). The app source repository is private.
- The backend accepts the audience `398230519810097786`, the load-generator project on the original IdP. Replace it with the project id that `idp-client.sh commons-grid-load` prints.
- The frontend Service carries `tailscale.com/tags: tag:edge4`.
- The backend mounts Secret `pii-hmac` (key `key`, the HMAC key for owner hashes). The repository does not create it.
- The TLS tap needs Secrets `honey/dx-pull` (image pull) and `honey/dx-metastasis-ch` (ClickHouse URL) and the ServiceAccount `honey/dx-daemon`.

### Warning: switch off the TLS tap when you are done

`platform/dx-ktls-openssl.yaml` is a proof of concept. It is not part of the soc stack.

- It runs as a privileged DaemonSet with `hostPID: true`. It attaches uprobes to `SSL_read` and `SSL_write` in the libssl of every pod in the namespaces listed in `DX_KTLS_NAMESPACES` (here `commons-grid`).
- It writes decrypted request and response bodies (up to 16,384 bytes each) to `forensic_db.dx_kubelet_stream` with `source='openssl'`. Rows are kept 24 hours.
- Personal data is replaced by `<pii:class>` markers at ingest by a classifier (classes email, phone, ccn, iban, ssn, ipv4, ipv6, dob, name, address). `DX_KTLS_REDACT=0` turns this off and stores bodies in clear. A classifier can miss values; only list namespaces whose traffic you are allowed to inspect.
- The README gives about 20 million rows a day under load.
- The image comes from the `feat/ktls-piiclass` branch of the dx repository.

Remove it after the evaluation, together with the probe pods. The load generator runs with `DURATION 24h`; delete its namespace too.

```sh
kubectl -n honey delete ds dx-ktls-openssl
./platform/adr-probe.sh --stop
kubectl delete namespace commons-grid-load
```

The soc README gives a similar warning for its kTLS probes on Kubernetes API traffic: turn them off unless an external storage sink is configured.

## Links

- Video: [Kubecon NA26: Set the Terms for Your Agents Let Your Humans Be Creative: Govern Code Nobody Reviewed](https://youtu.be/3N9fNF6sQIQ) (7:18, channel "Dr Constanze Roedig", uploaded 2026-11-06)
- Session: [Set the Terms for Your Agents and Let Your Humans Be Creative: How to Govern Code Nobody Reviewed](https://cncf-hosted-co-located-events-north-america-2026.sessionize.com/session/1255381). Platform Engineering Day (CNCF-hosted co-located event), KubeCon + CloudNativeCon North America 2026, Salt Lake City. Monday 2026-11-09, 13:30–13:55 (event time zone, Mountain Standard Time). Room: Salt Palace, Level 1, Grand Ballroom BDF. Speakers: Thomas Schuetz (Cloud Native Trainer & Architect, TSC Labs) and Dr. Constanze Roedig.
- Event page: [Platform Engineering Day, KubeCon + CloudNativeCon North America](https://events.linuxfoundation.org/kubecon-cloudnativecon-north-america/co-located-events/platform-engineering-day/)
- Harness and manifests: [k8sstormcenter/commons-grid-dynamics-manifest](https://github.com/k8sstormcenter/commons-grid-dynamics-manifest) (`main` = round 2, `demo` = round 1)
- soc stack: [k8sstormcenter/soc](https://github.com/k8sstormcenter/soc)
- SBOB (bill of behavior): [billofbehavior.com](https://billofbehavior.com)

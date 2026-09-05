# Installing the Sovereign SOC stack (soc + pixie) on a fresh Kubernetes cluster

For an agent bringing up the full stack on a **fresh cluster with no Tailscale** — the
cluster reaches the Pixie cloud directly over the public internet. It installs the
ClickHouse forensic store, Kubescape runtime SBoB enforcement, Vector, and Pixie
(Vizier + Adaptive Export + DX) **with Pixie's own SBoBs bound by default**.

## Prerequisites

- `kubectl`, `helm` (v4+), `skaffold` (v2.24+), `docker` (buildx).
- Outbound `:443` from the cluster to your Pixie cloud and to the image registries.
- Deploy the stack **only via `skaffold deploy` / `kubectl apply`** — never hand-edit
  the running objects. If something is wrong, fix the skaffold, not the cluster.

## Repos (clone read-only, deploy from these branches)

| repo | branch | provides |
|---|---|---|
| `k8sstormcenter/soc` | `main` (or the current deploy branch) | soc stack skaffold (ClickHouse + Kubescape + Vector + dx-wiring), `ks-sync`, `ch-cleanup` |
| `k8sstormcenter/pixie` | `feat/pixie-native-sbob` | AE + DX skaffolds, Pixie's own SBoBs (default-on), the `dx/*` views |
| `k8sstormcenter/bob` | per demo | the demo apps + SBoBs + the signed trust policy |

## 1. soc stack — ClickHouse → Kubescape → Vector → dx-wiring

```
cd soc
skaffold deploy -m soc-stack
```

This brings up, in order (the module chains the dependencies):

- **ClickHouse** `forensic-soc-db` with the `forensic_db` schema.
- **Kubescape operator**, chart
  `kubescape-operator-1.41.0-duckling2` (from the k8sstormcenter helm-charts release),
  node-agent `docker.io/entlein/duckling:v0.1.0-rogue2`, storage `rc-rogue5`,
  `maxLearningPeriod: 24h`, `learningPeriod: 10m`.
- **Vector** (kubescape → ClickHouse pipeline) + the **dx-wiring**.
- The **`ks-ch-sync`** CronJob (kubescape ContainerProfiles / rogue artifacts / trust
  policy → ClickHouse, every 2 min).

## 2. Pixie Adaptive Export + DX (pinned images)

AE and DX are **not** part of vanilla Pixie — deploy them from the pixie skaffold:

```
cd ../pixie
skaffold deploy -f skaffold/skaffold_adaptive_export.yaml    # AE 0.14.19-aeprod90
skaffold deploy -f skaffold/skaffold_dx.yaml                 # DX 0.5.0-keepset-rc23
```

- AE image: `ghcr.io/k8sstormcenter/vizier-adaptive_export_image:0.14.19-aeprod90`
- DX image: `docker.io/entlein/dx-daemon:0.5.0-keepset-rc23`
- The AE skaffold before-hook forces `PL_CLOUD_ADDR` to carry `:443` and self-heals
  `forensic_db` schema drift (drops AE-owned tables when `conn_stats.unique_id` is
  missing so `apply.go` recreates them).
- DX creates the `dx_orders` / `dx_ord__*` / `dx_src__kubescape_mitre` schema the
  `dx/*` views read.
- **PEM, AE, and DX all query node-local via pem-direct — that is real-time
  detection.** Each PEM answers queries from its OWN node on `:50305`; no cloud or
  broker round-trip. This needs **our** PEM line, not stock Pixie: stock `0.14.17`
  does not ship the `:50305` direct-query listener, so pem-direct is refused and dx
  goes **blind** (every dx-owned table — `conn_stats`, `dc_snoop`, `stack_trace`,
  `redis_events`, `mysql_events`, … — renders empty). Our PEM ships it (pem-direct
  is default-on in `main` since #87) and is built alongside AE at the same tag.
  - **PEM image: `ghcr.io/k8sstormcenter/vizier-pem_image:0.14.19-aeprod90`** —
    pinned in the pixie `k8s/vizier/pem` overlay, so it deploys with the vizier
    skaffold in §3 (no extra step).
  - AE queries its own node: `ADAPTIVE_VIZIER_DIRECT_ADDR=$(HOST_IP):50305`
    (already set in `adaptive_export_deployment.yaml`).
  - DX queries its own node: `DX_BENCH=pemdirect`. Confirm with the dx-daemon log
    line `bench=pemdirect (… :50305)`. If you see `bench=broker`,
    `bench=px`, or `bench UNAVAILABLE`, pem-direct didn't select — the usual cause
    is a stock `0.14.17` PEM instead of our line; verify with
    `kubectl -n pl get ds vizier-pem -o jsonpath='{..image}'`.
- **dx is order-driven — its tables stay empty until an alert fires.** Right after
  deploy, `conn_stats` / `dc_snoop` / `stack_trace` / the protocol tables read **0**
  because no anomaly has produced a referral yet. This is expected — do **not** read it
  as a broken deploy. Run a demo (e.g. the IngressNightmare or redis attack); a single
  run produces the referrals and the tables + `dx_order_edges` populate within ~45s.
  Verify the *bench* with the log line above, not with an empty table on a quiet cluster.

## 3. Pixie Vizier + Operator — SBoBs bound by DEFAULT

Deploy the Vizier and operator from the pixie skaffold. The SBoB overlay is the
**default** kustomize path, so Pixie's own ContainerProfiles are applied and each
workload's pod template is labelled with no extra flag:

```
skaffold deploy -f skaffold/skaffold_vizier.yaml
skaffold deploy -f skaffold/skaffold_operator.yaml
```

- Every vizier / operator / OLM workload comes up bound to its ContainerProfile —
  the node-agent adopts them at container start.
- The operator helm value `sbob: true` deploys the OLM/catalog profiles.
- To bring the stack up **without** the SBoBs, add `-p no-sbob` to both commands.

## 4. Trust policy for signed SBoBs

The node-agent reads its trust policy from cm `node-agent-bundle-policy` (key
`trust-policy.json`, mounted at `/etc/bundle`). Point it at the demo's signed trust
policy and apply the signed baseline rules, then roll the node-agent so it re-reads:

```
kubectl -n honey create cm node-agent-bundle-policy \
  --from-file=trust-policy.json=bob/example/redis/distros/signed-bundles/trust-policy.signed.json \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n honey apply -f bob/example/redis/distros/signed-bundles/rules/baseline-rules-signed.yaml
kubectl -n honey rollout restart ds/node-agent
```

## 5. Keep `forensic_db` lean

```
kubectl apply -f soc/tree/ch-cleanup/ch-cleanup.yaml
```

A CronJob (namespace `clickhouse`, every 2 min) that removes the infra-namespace
false-positive noise (Pixie's own `pl`/`px-operator`/`olm`/… plane, which is monitored
but is not an investigation subject) from `dx_orders` / `dx_order_records` /
`kubescape_logs`, plus their edges **scoped by a join to those orders** — it never
touches real correlation edges. Demo namespaces are left alone.

## 6. Register the cluster to your Pixie cloud (no Tailscale)

The Vizier connects out to your Pixie cloud over the public internet. `pl-cloud-config`
`PL_CLOUD_ADDR` **must** carry `:443`. Once the cluster shows healthy in the cloud UI,
the `dx/*` views are served by the cloud proxy — each view reads the in-cluster
ClickHouse via its `clickhouse_dsn` variable, so only the rendered query results leave
the cluster.

## 7. Verify

```
kubectl -n pl get pods        # vizier Healthy, adaptive-export Running, dx-daemon Running
kubectl -n honey get pods     # node-agent, storage, vector, ks-ch-sync
kubectl -n clickhouse exec <ch-pod> -- clickhouse-client \
  -q "SHOW TABLES FROM forensic_db"     # dx_orders, dx_ord__*, kubescape_*
```

SBoB binding is confirmed by the node-agent log line
`adopted user-authored ContainerProfile as authoritative base` for the pl / px-operator
/ olm workloads.

## Golden rules

- Deploy the stack **only via skaffold**; if it breaks, fix the skaffold.
- AE + DX are deployed from the pixie skaffold; vanilla Pixie has neither.
- The SBoBs are on by default — a plain `skaffold deploy` binds Pixie's own pods.

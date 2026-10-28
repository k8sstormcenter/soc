# dx-ktls

`dx-ktls.yaml` is the kTLS tap DaemonSet as it runs on edge4. It is a raw manifest and is not yet part of `skaffold.yaml`.

| Item | Value |
|---|---|
| Image | `docker.io/tanzeee/dx-ktls:49a3d1e@sha256:4bf6f97df7440e83d171d08c92c7cc7aaf73a77c3021861190be85c6ccc5f69e` (private; pull secret `dx-pull`; pin owned by AEDX) |
| Namespace / SA | `honey` / `dx-daemon` |
| Privileges | `privileged`, `hostPID`, hostPath `/sys/fs/bpf`, tolerates all taints |
| Kernel | needs BTF |
| ClickHouse | `DX_ORDERS_CH` from secret `dx-metastasis-ch` key `http-url`, the same ClickHouse as dx-daemon |
| Payload | `DX_KTLS_PAYLOAD_MAX=16384`, `DX_KTLS_BODIES=two-tier`, `DX_KTLS_EXCLUDE_UA` as in the manifest |
| Memory | limit must stay `1Gi`: the startup PROGBITS scan peaks at about 516 MiB; at `512Mi` it is OOM-killed about 2 s after start, before its first log line |
| Table | creates `dx_kubelet_stream` itself; do not pre-create it from DDL |

## Before integrating

`dx_kubelet_stream` is partitioned by `toYYYYMM`. On k3s-1 it reached 73.5 GiB (one month partition 68.4 GiB) and its merges filled the worker disk. Give it a retention or TTL decision before it runs on a cluster with a small data volume.

## Retention

`dx_kubelet_stream`: TTL 24 h (decided 2026-10-28). The TTL belongs in the table DDL the tap creates itself; it is not pre-created from this tree.

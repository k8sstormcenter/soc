---
title: Install
nav_order: 2
---

# Install
{: .no_toc }

1. TOC
{:toc}

{: .warning }
Alpha software. Install it on a test cluster. The stack needs a lot of memory and disk and is not optimised yet: with many events, pods can run out of memory.

## What you need

- A Kubernetes cluster. The stack is tested on k3s.
- x86-64 (amd64) nodes. The dx image is built for amd64 only, so ARM64 nodes do not work yet.
- At least 7 GiB of memory per node. Pixie reserves 2 GiB on every node, and ClickHouse 2 GiB on one node.
- About 60 GB of disk in a small setup. To use less, lower the volume sizes in the values files under `tree/`.
- The kernel headers for the running kernel on every node (Pixie needs them).
- On your workstation: `kubectl`, `helm`, `skaffold` v2, `openssl` and `git`.
- Outbound HTTPS (port 443) from the cluster to the Pixie cloud and to the container registries.

## 1. Install Pixie

The cockpit runs in a Pixie cloud. The commands below use the public SOC cloud at `soc.k8sstormcenter.com`, where you create your own account on first login. To use your own Pixie cloud, set `PX_CLOUD_ADDR` to its address instead.

Install the Pixie CLI and log in:

```sh
bash -c "$(curl -fsSL https://withpixie.ai/install.sh)"
export PX_CLOUD_ADDR=soc.k8sstormcenter.com
px auth login --manual
```

Deploy Pixie. The command depends on the kernel version of your nodes (`uname -r`).

**Kernel older than 6.10:**

```sh
px deploy --vizier_version 0.14.19-pemdq1 --pem_memory_request 2Gi --pem_memory_limit 4Gi
```

**Kernel 6.10 or newer.** The patch lowers a Pixie eBPF loop limit so that newer kernels load its programs:

```sh
px deploy --vizier_version 0.14.19-pemdq1 --pem_memory_request 2Gi --pem_memory_limit 4Gi \
  --patches 'vizier-pem:{"spec":{"template":{"spec":{"containers":[{"name":"pem","args":["--stirling_bpf_loop_limit=41"]}]}}}}'
```

Create an API key. The next step needs it:

```sh
export PIXIE_API_KEY=$(px api-key create -s -d soc)
```

## 2. Install the stack

```sh
git clone https://github.com/k8sstormcenter/soc && cd soc
skaffold deploy -m soc-alpha
```

This installs, in this order:

| Step | Component | Namespace |
|---|---|---|
| 1 | ClickHouse operator and the forensic database `forensic-soc-db` with the `forensic_db` schema | `clickhouse` |
| 2 | Runtime sensor operator (k8sstormcenter build of the chart) with the SOC rule set and rule binding | `honey` |
| 3 | Adaptive export, one per node, next to Pixie | `pl` |
| 4 | dx-daemon, one per node | `honey` |

The deploy stops with an error if Pixie is not installed in `pl`, or if `PIXIE_API_KEY` is not set on the first run. Later runs keep the stored key.

Running `skaffold deploy -m soc-alpha` again changes nothing.

## 3. Check

```sh
kubectl get pods -n pl; kubectl get pods -n honey; kubectl get pods -n clickhouse
kubectl -n honey logs ds/dx-daemon --tail=20
CH=$(kubectl -n clickhouse get pod -l clickhouse.altinity.com/chi=forensic-soc-db -o name | head -1)
kubectl -n clickhouse exec "$CH" -- clickhouse-client -q "SELECT count() FROM forensic_db.kubescape_logs"
```

All pods should be `Running`. The count grows once the sensor raises alerts.

The dx tables stay empty until the first alert fires. That is expected: dx only collects evidence for alerts. See [How it works](how-it-works.html).

Then open the Pixie cloud in your browser, select your cluster and pick a view whose name starts with `dx/`. See [Cockpit views](cockpit.html).

## Sensor only

To run detection without ClickHouse and Pixie:

```sh
skaffold deploy -m soc-kubescape -p standalone
```

The node-agent then sends alerts to an Alertmanager at `alertmanager.honey.svc.cluster.local:9093` (set in `tree/kubescape/values-standalone.yaml`). The stack does not install Alertmanager; run your own there or change the address.

## Remove

```sh
skaffold delete -m soc-alpha
px delete
```

Check afterwards for PersistentVolumeClaims left in the `clickhouse` namespace; they hold the stored evidence.

---
title: Troubleshooting
nav_order: 6
---

# Troubleshooting
{: .no_toc }

1. TOC
{:toc}

## `ERROR: Pixie is not installed in namespace pl`

The stack needs Pixie first. Do [step 1 of the install](install.html#1-install-pixie), then run `skaffold deploy -m soc-alpha` again.

## `ERROR: export PIXIE_API_KEY (px api-key create) for the first deploy`

The first deploy stores your Pixie API key in the cluster. Create one and run the deploy again:

```sh
export PIXIE_API_KEY=$(px api-key create -s -d soc)
skaffold deploy -m soc-alpha
```

## `ERROR: adaptive-export-control has no endpoints`

The adaptive export pods (one per node) did not become ready within a minute. Look at them:

```sh
kubectl -n pl get pods | grep adaptive-export
kubectl -n pl logs ds/adaptive-export --tail=50
```

## The dx tables are empty

On a quiet cluster this is expected. dx only collects evidence when an alert fires, and Kubescape only raises alerts after it has learned a workload's profile (at least 10 minutes after the workload starts). Wait for the learning period, then do something the workload never did during learning, for example start a shell in its container. The tables fill within about a minute of the alert.

If alerts arrive in `kubescape_logs` but the dx tables stay empty, read the dx log:

```sh
kubectl -n honey logs ds/dx-daemon --tail=50
```

## Pixie runs but shows no data on a new kernel

On kernels 6.10 and newer, deploy Pixie with the loop-limit patch from [step 1](install.html#1-install-pixie).

## Pods are `Pending` or restart with `OOMKilled`

The nodes have too little memory. Pixie reserves 2 GiB on every node and ClickHouse 2 GiB on one node; plan at least 7 GiB per node. With many events the stack needs more.

## The disk fills up

A small setup needs about 60 GB. Lower the volume sizes in the values files under `tree/`, or add disk.

## `PL_CLOUD_ADDR` without a port

The adaptive export needs the Pixie cloud address with an explicit port. The deploy adds `:443` to `PL_CLOUD_ADDR` in the `pl-cloud-config` ConfigMap if it is missing; you do not need to do anything.

## Still stuck

Open an issue at [github.com/k8sstormcenter/soc/issues](https://github.com/k8sstormcenter/soc/issues) with the output of the [check commands](install.html#3-check).

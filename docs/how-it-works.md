---
title: How it works
nav_order: 3
---

# How it works
{: .no_toc }

1. TOC
{:toc}

## From alert to evidence

1. **Watch.** The runtime sensor (node-agent) runs on every node. With eBPF it sees what each container does: processes it starts, files it opens, network connections, system calls and capabilities.
2. **Learn.** While a workload runs normally, the sensor learns its behavior profile. In this stack it learns for at least 10 minutes and at most 24 hours (`learningPeriod` and `maxLearningPeriod` in `tree/kubescape/values.yaml`). You can also bind a profile you wrote yourself; see the [node-agent documentation on user-defined profiles](https://kubescape.io/docs/operator/bill-of-behavior/).
3. **Alert.** When a container does something its profile does not allow, a rule fires and the sensor raises an alert. The rules and their binding to workloads are in `tree/kubescape/default-rules.yaml` and `tree/kubescape/rule-alert-binding.yaml`.
4. **Order.** The node-agent streams each alert directly to dx-daemon on the same node. dx turns it into an *order*: a request to collect evidence for the pods involved, in a narrow time window around the alert.
5. **Collect.** Pixie keeps recent data on each node: connections, DNS, HTTP and database protocols, process events and stack traces. For each order, dx and the adaptive export read the matching rows from Pixie and write them to ClickHouse.
6. **Link.** dx links alerts and evidence into graphs: which pod reached which other pod, and how (for example delivery, execution, pivot), with a severity and a confidence for each link.
7. **Look.** You read the result in the [cockpit views](cockpit.html), starting from an alert or a host.

Alert cooldown is off on purpose. A false positive is fixed by a better profile, not hidden by suppressing repeats.

## What runs where

| Namespace | What runs there |
|---|---|
| `pl` | Pixie (Vizier, and a PEM on every node) and the adaptive export on every node |
| `honey` | Sensor operator (node-agent on every node, storage) and dx-daemon on every node |
| `clickhouse` | ClickHouse operator and the forensic database `forensic-soc-db` |

## What stays in your cluster

- All collected data is stored in ClickHouse in your cluster.
- The cockpit views run as queries in your cluster. The Pixie cloud passes the query results to your browser. If you do not want that either, run your own Pixie cloud and point `PX_CLOUD_ADDR` at it.

## Noise

Not every alert is an attack. dx sorts what it finds and labels links that turned out to be harmless as `triage_benign`, `ruled_out` or `triage_abstain`.

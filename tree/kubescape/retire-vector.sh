#!/bin/sh
# Retire a vector left from before the direct stream. Only after node-agent has
# rolled onto the direct stream, so alerts are briefly written twice rather than
# lost. Covers both install paths: a helm release (Makefile) and the objects the
# old soc-vector skaffold module applied with kubectl. A no-op once vector is gone.
set -eu
L=app.kubernetes.io/name=vector
if ! helm status vector -n honey >/dev/null 2>&1 && \
   [ -z "$(kubectl -n honey get ds,deploy,sts -l $L -o name 2>/dev/null)" ]; then
  exit 0
fi
kubectl -n honey rollout status ds/node-agent --timeout=10m
if helm status vector -n honey >/dev/null 2>&1; then
  helm uninstall vector -n honey
fi
kubectl -n honey delete ds,deploy,sts,svc,sa,cm,secret -l $L --ignore-not-found
kubectl delete clusterrole,clusterrolebinding -l $L --ignore-not-found

#!/bin/sh
# Rules hand-over from the chart to soc. A release installed with
# alertCRD.installDefault=true owns default-rules and all-rules-all-pods; soc
# sets it false and applies the same objects itself. Without this, helm deletes
# them on upgrade and node-agent runs with no rules until soc's apply lands (or
# for good, if the upgrade fails first). helm skips deleting an object whose live
# annotations carry resource-policy=keep. A no-op when soc already owns them.
set -eu
keep() {
  rel=$(kubectl get "$@" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null) || return 0
  pol=$(kubectl get "$@" -o jsonpath='{.metadata.annotations.helm\.sh/resource-policy}' 2>/dev/null || true)
  [ "$rel" = kubescape ] && [ "$pol" != keep ] && kubectl annotate "$@" helm.sh/resource-policy=keep >/dev/null
  return 0
}
keep -n honey rules.kubescape.io default-rules
keep runtimerulealertbindings.kubescape.io all-rules-all-pods

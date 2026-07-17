#!/usr/bin/env bash
NODE=gke-k8s-caas-0009-dev-user-pool-0fc5bebd-kq52
MINIME_POD_IP=10.1.2.8 #$(kubectl get pod  -n pacman -o jsonpath='{.items[0].status.podIP}')
#PWRU_ARGS="--output-tuple 'host ${MINIME_POD_IP}'"
PWRU_ARGS="dst host 169.254.169.254 and tcp"

trap " kubectl delete --wait=false pod pwru " EXIT

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pwru
spec:
  nodeSelector:
    kubernetes.io/hostname: ${NODE}
  containers:
  - image: docker.io/cilium/pwru:latest
    name: pwru
    volumeMounts:
    - mountPath: /sys/kernel/debug
      name: sys-kernel-debug
    securityContext:
      privileged: true
    command: ["/bin/sh"]
    args: ["-c", "pwru ${PWRU_ARGS}"]
  volumes:
  - name: sys-kernel-debug
    hostPath:
      path: /sys/kernel/debug
      type: DirectoryOrCreate
  hostNetwork: true
  hostPID: true
EOF

kubectl wait pod pwru --for condition=Ready --timeout=90s
kubectl logs -f pwru
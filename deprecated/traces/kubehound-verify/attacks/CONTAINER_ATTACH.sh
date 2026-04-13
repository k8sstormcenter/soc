#!/bin/bash

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

# Get all namespaces
namespaces=$(kubectl get namespaces -o json | jq -r '.items[].metadata.name')

# Iterate over all namespaces
for ns in $namespaces; do
    echo "Processing namespace: $ns"

    # Get all pods in the namespace
    pods=$(kubectl get pods -n $ns -o json | jq -r '.items[].metadata.name')

    # Iterate over all pods
    for pod in $pods; do
        echo "Processing pod: $pod"

        # Get the service account associated with the pod
        sa=$(kubectl get pod $pod -n $ns -o json | jq -r '.spec.serviceAccountName')

        if [ -z "$sa" ]; then
            echo "No service account found for pod: $pod"
            continue
        fi

        echo "Service account for pod $pod: $sa"

        # Get the target container name
        containers=$(kubectl get pod $pod -n $ns -o json | jq -r '.spec.containers[].name')

        # Iterate over all containers in the pod
        for container in $containers; do
            echo "Attempting to debug container: $container in pod: $pod"

            # Attempt kubectl debug
            kubectl debug -it $pod -n $ns --image=busybox:1.28 --target=$container --serviceaccount=$sa
        done
    done
done
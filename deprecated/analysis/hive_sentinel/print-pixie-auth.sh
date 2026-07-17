#!/bin/bash

# Prints Pixie API token and healthy cluster ID to terminal

set -e

if ! command -v px &> /dev/null; then
  echo "Error: px CLI is not installed. Install it from https://docs.pixielabs.ai/installing-pixie/installing-pixie-cli"
  exit 1
fi

echo "--- Pixie Environment Info ---"
px api-key create

CLUSTER_JSON=$(px get clusters --output json | grep -Eo '{.*}' | jq -c 'select(.Status == 1)' | head -n 1)
CLUSTER_ID=$(echo "$CLUSTER_JSON" | jq -r '.ID')
CLUSTER_NAME=$(echo "$CLUSTER_JSON" | jq -r '.ClusterName')

if [ -z "$CLUSTER_JSON" ]; then
  echo "Error: No healthy cluster found. Please ensure you have a healthy cluster."
  exit 1
fi

echo "PIXIE_CLUSTER_ID=$CLUSTER_ID"
echo "Cluster Name: $CLUSTER_NAME"

#!/bin/bash

echo "🔄 Processing STIX lines..."

TEMP_FILE="stix.json"

while IFS= read -r line; do
  payload=$(echo "$line" | jq -c .)  # ensure it's compact JSON
  echo "{\"stix_bundle\": $payload}" >> "$TEMP_FILE"
done < stix.log

echo "📦 Transformed lines written to $TEMP_FILE"

echo "🚀 Copying to Minikube..."
minikube cp "$TEMP_FILE" /home/docker/stix.json
echo "✅ File copied to Minikube successfully!"
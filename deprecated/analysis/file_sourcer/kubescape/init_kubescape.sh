#!/bin/bash

echo "Moving init file to Minikube..."
minikube cp kubescape_schema_init.json /home/docker/kubescape.json
echo "✅ Moved the file succesfully!"

px run -f ingest_kubescape.pxl

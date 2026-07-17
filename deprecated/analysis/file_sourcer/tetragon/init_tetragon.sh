#!/bin/bash

echo "Moving init file to Minikube..."
minikube cp tetragon_schema_init.json /tmp/tetragon.json
echo "✅ Moved the file succesfully!"

px run -f ingest_tetragon.pxl
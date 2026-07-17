#!/bin/bash

# for demo: make sure you run this once before so the stuff is installed in the ssh-proxy
apt update
apt install -y python3-pip
pip3 install kubernetes
export KUBERNETES_SERVICE_HOST=kubernetes.default
export KUBERNETES_SERVICE_PORT=443
python3 ./create.py
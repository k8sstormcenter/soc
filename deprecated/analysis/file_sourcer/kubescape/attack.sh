#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HONEYCLUSTER_DIR="$SCRIPT_DIR/../../.."

# Step 1: Set up bait environment and start port-forward
echo "🧲 Step 1: Setting up bait environment..."
(cd "$HONEYCLUSTER_DIR" && \
  make --makefile=Makefile_attack bait && \
  sleep 1 && \
  echo | make --makefile=Makefile_attack port-forward)

# Step 2: Wait until port-forward is ready
echo ""
echo "⏳ Waiting for port-forward to be ready on 127.0.0.1:5555..."
for i in {1..15}; do
  if nc -z localhost 5555; then
    echo "✅ Port-forward is ready!"
    break
  fi
  sleep 1
done

if ! nc -z localhost 5555; then
  echo "❌ Timed out waiting for port-forward on 127.0.0.1:5555"
  exit 1
fi

# Step 3: SSH into bait pod and generate logs
echo ""
echo "🔐 Step 2: Connecting over SSH and generating Pixie logs..."
echo "(Password is: root)"
ssh -p 5555 root@127.0.0.1 <<'ENDSSH'
apt update -y
wget -q http://security.ubuntu.com
exit
ENDSSH

# Step 4: Preprocess Kubescape logs
echo ""
echo "🛠️ Step 3: Preprocessing kubescape logs using current time..."
bash "$SCRIPT_DIR/preprocess_kubescape.sh" "$SCRIPT_DIR/kubescape.log" "$SCRIPT_DIR/kubescape.json" --time=now

# Done
echo ""
echo "✅ Attack scenario complete. Logs aligned and deployed."
echo "🧹 To clean up, run:"
echo "   (cd $HONEYCLUSTER_DIR && make --makefile=Makefile_attack bait-delete)"
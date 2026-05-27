#!/bin/bash
set -euo pipefail

# Install K3s on Node-1.
# Run on the master node, not from the Mac workstation.
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.33.11+k3s1 sh -s - \
  --write-kubeconfig-mode 600

echo "K3s installed. Save the worker join token in homelab-private:"
echo "  sudo cat /var/lib/rancher/k3s/server/node-token"

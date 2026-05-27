#!/bin/bash
# Safe Node-2 shutdown: drain first, then power off over SSH.
NODE="optiplex-worker"
NODE_SSH_HOST="<node-2-host-or-ip>"
NODE_SSH_PORT="<SSH_PORT>"
NODE_SSH_USER="<ssh-user>"

echo "Draining $NODE..."
kubectl drain "$NODE" \
  --delete-emptydir-data \
  --ignore-daemonsets \
  --force \
  --timeout=120s

if [ $? -eq 0 ]; then
  echo "Drain complete. Shutting down..."
  ssh -p "$NODE_SSH_PORT" "$NODE_SSH_USER@$NODE_SSH_HOST" "sudo shutdown now"
else
  echo "Drain failed. NOT shutting down."
  exit 1
fi

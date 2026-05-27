#!/bin/bash
set -euo pipefail

# Apply after Node-2 has joined the cluster.
kubectl label node optiplex-worker workload=llm-inference --overwrite
kubectl label node optiplex-worker workload=heavy-ml --overwrite

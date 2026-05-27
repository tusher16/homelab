# K3s Bootstrap

Bootstrap files for the K3s-era homelab.

Current confirmed state:

- Node-1 runs K3s as the control-plane node.
- The Kubernetes hostname used in manifests is `elitedesk-node1`.
- Node-2 is still part of the migration plan and should be joined later as the ML/Ollama worker.

Secrets, kubeconfig, join tokens, real IPs, and SSH details belong in `homelab-private`.

# GitHub Repo Setup

This repo is the public infrastructure repo: `tusher16/homelab`.

The private companion repo is `tusher16/homelab-private` and must hold secrets, real IPs, kubeconfig, join tokens, and app `.env` files.

## Create the Public Repo

```bash
cd /Users/tusher16/Projects/homelab
git init
git add .
git commit -m "feat: merge Docker legacy docs with K3s homelab structure"
gh repo create tusher16/homelab --public --source=. --remote=origin --push
```

## Recommended Topics

```text
k3s
kubernetes
homelab
traefik
cert-manager
ollama
fastapi
berlin
cloudnativepg
self-hosted
```

## Do Not Commit

- `.env` files
- `secrets/`
- kubeconfig
- K3s join token
- Cloudflare API tokens
- real LAN IPs
- real SSH port

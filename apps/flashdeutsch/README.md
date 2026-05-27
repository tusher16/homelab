# FlashDeutsch

German vocabulary flashcard app at `flashdeutsch.tusher16.com`.

Firebase auth (Google OAuth), Firestore sync, served as a Docker image from `ghcr.io/tusher16/flashdeutsch-vocab`.

**Manifests:**
- `deployment.yaml` — nginx container, nodeSelector: `elitedesk-node1`, imagePullSecrets: `ghcr-secret`
- `service.yaml` — ClusterIP port 80
- `ingress.yaml` — Traefik + cert-manager, host: `flashdeutsch.tusher16.com`

**App repo:** [tusher16/flashdeutsch-vocab](https://github.com/tusher16/flashdeutsch-vocab)

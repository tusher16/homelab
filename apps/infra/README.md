# Infra Manifests

Cluster-level infrastructure manifests.

- `cluster-issuer.yaml`: cert-manager `ClusterIssuer` using Cloudflare DNS-01.
- `traefik-helmchartconfig.yaml`: K3s Traefik customization through `HelmChartConfig`.

Do not commit Cloudflare API tokens. The Kubernetes secrets that contain tokens belong in `homelab-private`.

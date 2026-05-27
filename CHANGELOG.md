# Changelog

## [2.0.0] — 2026 (K3s era — current)
### Added
- K3s cluster on Node-1 (HP EliteDesk 705 G4)
- Traefik ingress controller (built into K3s)
- cert-manager with DNS-01 Cloudflare solver
- Static landing pages for tusher16.com and safinakhan.com
- FlashDeutsch deployed on K3s
- Namespace plan for infra, databases, apps, and ml

### Planned
- Migrate RAG Studio, finance-agent, and n8n from Docker Compose to K3s
- Reinstall Node-2 and join it as a K3s worker
- Run Ollama as a K3s pod on Node-2
- Add CloudNativePG for PostgreSQL
- Add Node-3 (Arduino Uno Q) as standalone monitoring node
- Add Headlamp cluster UI
- Add Homepage dashboard (gethomepage.dev)

### Removed
- jwilder/nginx-proxy (replaced by Traefik)
- letsencrypt-nginx-proxy-companion (replaced by cert-manager)
- Portainer (replaced by k9s + Headlamp)
- resume-tailor (decommissioned — unreliable)

### Changed
- All services migrated from Docker Compose to K3s manifests
- SSL from HTTP-01 to DNS-01 (required for Cloudflare proxied mode)
- CI/CD direction updated toward ghcr.io image push + K3s rollout restart

---

## [1.0.0] — 2023 (Docker Compose era)
### Added
- Dell OptiPlex 9020 as single home server
- nginxproxy/nginx-proxy for reverse proxy (ports 80/443)
- nginxproxy/acme-companion for automatic SSL
- ddclient for dynamic DNS updates to Cloudflare
- tusher16.com — Django/Gunicorn portfolio
- safinakhan.pro — Flask/Gunicorn portfolio
- finance.tusher16.com — FastAPI finance agent
- rag.tusher16.com — FastAPI RAG pipeline
- n8n.tusher16.com — workflow automation
- portainer.tusher16.com — container management UI
- ollama — internal LLM (qwen2.5:3b, CPU-only, no public domain)
- GitHub Actions CI/CD via SSH deploy

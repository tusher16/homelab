# Homelab Migration & Rebuild — Master Plan
> Mohammad Tusher · Berlin, Germany · May 2026  
> Goal: Production-grade, job-portfolio-ready home server. Think AWS/GCP discipline — on a budget.  
> **This document doubles as the source for a Medium blog series.**

---

## The Big Picture — What & Why

| Current State | Target State |
|---|---|
| Node-2 (Dell) runs everything via Docker Compose | Node-1 (HP EliteDesk) is the K3s master — runs all services |
| Node-1 (HP EliteDesk) is fresh, unused | Node-2 (Dell) wiped → Ubuntu Server → K3s worker (Ollama/ML only) |
| `jwilder/nginx-proxy` + Docker for routing | **Traefik** (built into K3s) + **cert-manager** — no Docker proxy needed |
| Django portfolio — 5–7 year old template | Static "coming soon" landing pages first, full rebuild later |
| Portainer for management | **k9s** (terminal) + **Headlamp** (web UI) |
| No cluster-level database | **CloudNativePG** — production PostgreSQL operator on K3s |
| Docker runtime everywhere | K3s built-in **containerd** on both nodes — Docker **not needed** |

### Why This Matches Production Engineering

> A homelab that mirrors AWS/GCP discipline is the portfolio that gets you hired.
> Every decision here — Traefik over nginx-proxy, CloudNativePG over vanilla Postgres,
> cert-manager over manual SSL — is what production Kubernetes platform teams use daily.

---

## ✅ Fact-Check — Every Major Claim Verified (May 2026)

All architecture decisions were verified against official documentation and community sources.

| Claim in This Plan | Verified? | Evidence |
|---|---|---|
| Traefik is built into K3s — no separate install | ✅ YES | K3s official docs: *"Traefik is deployed by default when starting the server. Ports 80 and 443 are exposed by the bundled Traefik ingress controller"* |
| K3s uses containerd — no Docker on worker nodes | ✅ YES | K3s docs: *"K3s includes and defaults to containerd, an industry-standard container runtime"* |
| cert-manager automates Let's Encrypt renewal | ✅ YES | cert-manager.io: checks daily, renews 30 days before expiry, zero downtime |
| **http01 solver FAILS with Cloudflare orange-cloud proxy** | ✅ CONFIRMED CRITICAL | Official cert-manager GitHub #6471: *"HTTP-01 challenges fail if you use Cloudflare proxy — origin IP hidden, results in HTTP 526 error"* — **must use dns01 solver** |
| CloudNativePG `Database` CRD for declarative DB management | ✅ CONFIRMED | CNPG v1.25 docs: *"CloudNativePG introduces declarative database management using the Database CRD — scalable, automated, consistent"* |
| `kubectl drain` required before Node-2 shutdown | ✅ CONFIRMED | K8s best practice — abrupt shutdown causes 5–15 min control plane NotReady alerts |
| CloudNativePG is production-grade PostgreSQL on K3s | ✅ YES | CNCF project, KubeCon EU 2026 Amsterdam presentation, widely used in production |
| NGINX Ingress Controller is retired | ✅ YES | Kubernetes blog Nov 2025: *"SIG Network and Security Response Committee announced retirement of Ingress NGINX"* |
| Do NOT edit traefik.yaml directly in K3s | ✅ YES — ⚠️ Correction | K3s docs: *"this file should not be edited manually, as K3s will replace the file with defaults at startup"* — use `HelmChartConfig` instead |
| ConfigMap + nginx:alpine = static site, no custom image | ✅ YES | Standard K8s pattern — ConfigMap mounted as volume at /usr/share/nginx/html |
| Homepage auto-discovers K3s services via Ingress annotations | ✅ YES | gethomepage.dev: Kubernetes-native service discovery via `gethomepage.dev/enabled: "true"` annotation |
| K3s containerd 2.0 since Feb 2025 | ✅ YES | K3s docs: *"K3s includes containerd 2.0 as of the February 2025 releases v1.31.6+k3s1"* |
| K3s v1.32+ ships Traefik v3 (not v2) | ✅ CONFIRMED | K3s release notes: *"K3s versions v1.32 and later install Traefik v3"*. Current stable: v1.33 with Traefik v3.6.13 |
| Gateway API supported in K3s via HelmChartConfig | ✅ CONFIRMED | K3s docs: *"K3s comes with Traefik v3, which includes optional support for the Gateway API"* — enable via `providers.kubernetesGateway.enabled: true` |

> ⚠️ **Corrections from previous versions of this plan (all verified May 2026):**
>
> 1. **Traefik customisation** must use `HelmChartConfig` CRD — never edit `traefik.yaml` directly (K3s overwrites it on restart)
> 2. **cert-manager must use `dns01` solver** — NOT `http01`. Cloudflare orange-cloud proxy blocks HTTP-01 ACME challenges, causing cert renewal failures every 60 days. Confirmed: cert-manager GitHub issue #6471.
> 3. **CloudNativePG databases** should be created with the `Database` CRD, not `kubectl exec psql`. Confirmed: CNPG v1.25 official docs.
> 4. **Node-2 shutdown** requires `kubectl drain` first — never pull power abruptly on a K3s worker node.


---

## Architecture — The Complete Stack (Target State)

```
Internet
    ↓
Cloudflare (DNS + orange-cloud proxy, hides home IP)
    ↓
ddclient → auto-updates ssh.tusher16.com A record on IP change (see DDNS section)
    ↓
Node-1: HP EliteDesk 705 G4  (192.168.x.x)
    ↓
Traefik Ingress Controller    ← built into K3s, replaces jwilder/nginx-proxy
    ├── cert-manager           ← replaces letsencrypt-nginx-proxy-companion
    ├── tusher16.com           → static landing page (nginx:alpine + ConfigMap)
    ├── safinakhan.com         → static landing page (nginx:alpine + ConfigMap)
    ├── flashcard.tusher16.com → Flashcard App (K3s pod)
    ├── rag.tusher16.com       → RAG Studio (FastAPI + ChromaDB, K3s pod)
    ├── finance.tusher16.com   → Family Finance Agent (FastAPI, K3s pod)
    ├── n8n.tusher16.com       → n8n (K3s pod)
    ├── headlamp.tusher16.com  → Headlamp cluster UI (K3s pod)
    └── CloudNativePG          → PostgreSQL cluster (K3s pod, pinned Node-1)
    
Node-2: Dell OptiPlex 9020  (192.168.x.x)  ← K3s Worker
    └── ollama                 → Ollama (K3s pod, nodeSelector: optiplex-worker)
                                 accessible inside cluster as http://ollama:11434

Node-3: Arduino Uno Q  (monitoring, standalone — not in K3s)
    ├── Uptime Kuma            → monitors all public endpoints
    ├── Grafana                → dashboards
    └── Prometheus             → scrapes Node-1 + Node-2

Mac Mini (your workstation)
    ├── k9s                    → daily cluster management terminal UI
    └── kubectl                → direct cluster commands
```

### The Key Architectural Shift: Traefik Replaces Docker nginx-proxy

```
BEFORE (Docker Compose era):
  jwilder/nginx-proxy          — watches Docker socket, routes by VIRTUAL_HOST env var
  letsencrypt-nginx-proxy-companion — generates SSL per container

AFTER (K3s era):
  Traefik Ingress Controller   — already running inside K3s from install day 1
  cert-manager                 — install once, manages ALL SSL automatically
  Ingress YAML per service     — 10 lines replacing VIRTUAL_HOST + LETSENCRYPT_HOST
```

With Traefik, SSL is just part of your infrastructure as code. Everything is stored as text and version-controlled in your Git repo — spin up on another host and all containers and SSL certs come with it. No clicking around in a UI.

---

---

## 🌐 Dynamic DNS (DDNS) — Auto IP Update When Home IP Changes

> **With Cloudflare Tunnel (Phase 0), DDNS is only needed for ONE record:**
> `ssh.tusher16.com` — used by GitHub Actions CI/CD to SSH into Node-1.
> All public web services go through the tunnel, which doesn't need DNS records.

### What ddclient Does

Your home internet IP changes occasionally (your ISP reassigns it).
ddclient runs on Node-1 and watches your current public IP.
When it detects a change, it automatically updates the Cloudflare DNS A record
for `ssh.tusher16.com` — keeping your GitHub Actions CI/CD working without any manual intervention.

```
Your ISP changes home IP
        ↓
ddclient detects change (polls every 300 seconds)
        ↓
ddclient calls Cloudflare API → updates A record for ssh.tusher16.com
        ↓
GitHub Actions CI/CD still works — no manual DNS update needed
```

### Install ddclient on Node-1

```bash
sudo apt install -y ddclient
sudo nano /etc/ddclient.conf
```

Minimal config for SSH subdomain only:
```conf
# /etc/ddclient.conf — minimal version for Cloudflare Tunnel setup
# Only needed for ssh.tusher16.com (CI/CD access)

daemon=300                    # check every 5 minutes
syslog=yes
pid=/var/run/ddclient.pid

use=web, web=https://api.ipify.org    # detect current public IP

protocol=cloudflare
zone=tusher16.com
login=tusher16@gmail.com
password=<cloudflare-api-token>       # Zone:DNS:Edit permission
ssh.tusher16.com                      # ONLY this record — not all subdomains
```

```bash
sudo systemctl enable ddclient
sudo systemctl start ddclient

# Test it works
sudo ddclient -force -verbose
# Should show: Setting tusher16.com/ssh.tusher16.com to <your-ip>
```

### Cloudflare DNS Record for SSH

In Cloudflare dashboard:
- Type: `A`
- Name: `ssh`
- Content: your current public IP
- **Proxy status: ☁️ DNS only (grey cloud)** — MUST be grey, never orange
  - Orange cloud would hide your IP from GitHub Actions → SSH connection refused

### Why SSH Must Stay Grey Cloud (Not Tunnelled)

GitHub Actions needs a direct TCP connection to port <SSH_PORT> for SSH.
Cloudflare Tunnel only handles HTTP/HTTPS traffic (ports 80/443).
SSH over a Cloudflare Tunnel is not supported on the free tier.
Therefore `ssh.tusher16.com` needs a direct DNS record pointing to your real IP.

### All Other Subdomains

With Cloudflare Tunnel active, you do NOT add other subdomains to ddclient.conf.
The tunnel handles routing for all HTTP/HTTPS services — Cloudflare manages DNS internally.

```
OLD way (port forwarding):
  ddclient.conf: tusher16.com, rag.tusher16.com, finance.tusher16.com, n8n.tusher16.com, ...
  Every subdomain needed updating when IP changed

NEW way (Cloudflare Tunnel):
  ddclient.conf: ssh.tusher16.com   ← just this one
  All web services are tunnelled — IP changes are invisible to them
```

## Container Runtime — Read This First

| Node | Docker needed? | Runtime | Why |
|---|---|---|---|
| Node-1 (K3s Master) | **No** | K3s containerd | Traefik handles routing natively inside K3s |
| Node-2 (K3s Worker) | **No** | K3s containerd | K3s agent brings its own runtime |
| Both nodes previously | Yes (Docker Compose) | Docker daemon | Legacy — fully replaced by K3s |

K3s ships with containerd built in. Every pod — Traefik, your apps, Ollama, CloudNativePG — runs through K3s containerd. Docker is not installed on either node.

---

## Phase 0 — Pre-Flight: Static IP + kubeconfig on Mac

Before any K3s install, lock in the network.

```bash
# 1. Find Node-1's current LAN IP
ssh tusher16@<node1-current-ip>
ip addr show eno1 | grep "inet "

# 2. Assign static IP in Fritz!Box
#    Home Network → Network → DHCP Reservations
#    Node-1 → 192.168.x.x
#    Node-2 → 192.168.x.x (keep existing)

# 3. Update router port forwarding
#    Internet → Port Sharing
#    Port 80  → 192.168.x.x  (was Node-2)
#    Port 443 → 192.168.x.x  (was Node-2)
#    ⚠️ Do this at night — ~30 seconds downtime
```

---

## Phase 1 — K3s on Node-1 (Master)

**Medium blog angle:** *"Installing a production-grade Kubernetes cluster on a €80 refurbished PC"*

### 1.1 — Install K3s (keep built-in Traefik, customise via HelmChartConfig)

```bash
ssh tusher16@192.168.x.x

# Install K3s — keep Traefik but expose kubeconfig
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.33.11+k3s1 sh -s - \
  --write-kubeconfig-mode 600
  # v1.33.11 = current stable LTS. Pin this — never use bare 'get.k3s.io | sh'
  # 600 not 644 — cluster-admin kubeconfig must not be world-readable on Node-1

# Verify
sudo kubectl get nodes
# NAME           STATUS   ROLES                  AGE   VERSION
# elitedesk-node1   Ready    control-plane,master   60s   v1.x.x+k3s1

# Check Traefik is already running (built in)
sudo kubectl get pods -n kube-system | grep traefik
# traefik-xxxx   1/1   Running   0   90s
```

### 1.2 — Copy kubeconfig to Mac Mini

```bash
# On Mac mini
mkdir -p ~/.kube
scp tusher16@192.168.x.x:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Fix server address (k3s defaults to 127.0.0.1)
sed -i '' 's/127.0.0.1/192.168.x.x/g' ~/.kube/config

# Verify from Mac
kubectl get nodes
```

### 1.3 — Install k9s on Mac Mini

```bash
brew install k9s
k9s   # should show the cluster immediately
```

### 1.4 — Get the Worker Join Token (save it)

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
# K10xxx... — copy this, needed for Node-2
```

---

## Phase 2 — cert-manager + Traefik SSL (The nginx-proxy Replacement)

**Medium blog angle:** *"Replacing jwilder/nginx-proxy with K3s-native Traefik + cert-manager"*

This is the single most important infrastructure decision. After this phase, every new service
you deploy gets HTTPS automatically with a 10-line Ingress YAML — no Docker, no env vars.

### 2.1 — Install cert-manager

```bash
# Install via kubectl (official manifest)
# Pin version — never use 'latest' in production. Check https://github.com/cert-manager/cert-manager/releases
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.0/cert-manager.yaml

# Wait for all 3 cert-manager pods to be Running
kubectl get pods -n cert-manager -w
```

### 2.2 — Create the Cloudflare API Token Secret

> ⚠️ **Critical:** Do NOT use the `http01` solver. Cloudflare's orange-cloud proxy
> intercepts port 80/443, blocking Let's Encrypt HTTP-01 validation. Every renewal
> will fail silently after 60 days. Confirmed in cert-manager GitHub issue #6471.
>
> **The fix:** Use the `dns01` solver with a Cloudflare API token. cert-manager
> creates a temporary TXT record in your Cloudflare DNS out-of-band. Your home IP
> stays hidden, orange clouds stay on, certs renew automatically forever.

**Step 1:** Create a Cloudflare API token with `Zone:DNS:Edit` permission for
your zone (tusher16.com and safinakhan.com). Save it to homelab-private.

```bash
# Create the secret in cert-manager namespace
kubectl create secret generic cloudflare-api-token-secret   --from-literal=api-token=<YOUR_CLOUDFLARE_API_TOKEN>   --namespace cert-manager
```

### 2.3 — Create the Let's Encrypt ClusterIssuer (dns01)

Save as `cluster-issuer.yaml` in `homelab/apps/infra/`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: tusher16@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - dns01:
          cloudflare:
            email: tusher16@gmail.com
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
```

```bash
kubectl apply -f cluster-issuer.yaml

# Verify issuer is Ready (takes ~30 seconds)
kubectl describe clusterissuer letsencrypt-prod
# Status: True, Type: Ready
```

### 2.4 — Traefik HelmChartConfig (HTTP→HTTPS redirect + Cloudflare real IPs)

Save as `traefik-helmchartconfig.yaml` in `homelab/apps/infra/`:

> This must be a `HelmChartConfig` — never edit `traefik.yaml` directly.
> The `trustedIPs` list ensures your app logs show real visitor IPs,
> not Cloudflare's edge network IPs (which would make geo-filtering and
> rate-limiting useless).

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |
    globalArguments:
      - "--global.checknewversion=false"
      - "--global.sendanonymoususage=false"
    additionalArguments:
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.websecure.forwardedHeaders.trustedIPs=103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,172.64.0.0/13,173.245.48.0/20,188.114.96.0/20,190.93.240.0/20,197.234.240.0/22,198.41.128.0/17,2400:cb00::/32,2606:4700::/32,2803:f800::/32,2405:b500::/32,2405:8100::/32,2a06:98c0::/29,2c0f:f248::/32"
    # ↑ IPv4 + IPv6 Cloudflare ranges. Fetch latest: https://www.cloudflare.com/ips/
```

```bash
# Apply it — K3s Helm controller picks it up immediately, no restart needed
kubectl apply -f traefik-helmchartconfig.yaml

# Verify Traefik reloaded with new config
kubectl rollout status deployment/traefik -n kube-system
```

> The Cloudflare IP ranges in `trustedIPs` are Cloudflare's published CIDR blocks.
> These tell Traefik to trust the `X-Forwarded-For` header from Cloudflare,
> so your FastAPI/Django apps see the real visitor IP, not `103.x.x.x`.

### 2.5 — How Every Service Gets HTTPS (the pattern)

This replaces `VIRTUAL_HOST` + `LETSENCRYPT_HOST` env vars entirely:

```yaml
# ingress-template.yaml — reuse this for every new service
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <service-name>
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"   # auto SSL
    traefik.ingress.kubernetes.io/router.entrypoints: "websecure"
spec:
  ingressClassName: traefik
  rules:
    - host: <subdomain>.tusher16.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <service-name>
                port:
                  number: <port>
  tls:
    - hosts:
        - <subdomain>.tusher16.com
      secretName: <service-name>-tls   # cert stored here automatically
```

cert-manager automatically handles certificate rotation — it checks expiration daily and if a certificate is nearing expiration (30 days before), it initiates renewal without any downtime.

---

## Phase 3 — Static Landing Pages (tusher16.com + safinakhan.com)

**Medium blog angle:** *"Ship fast: deploying a static landing page to Kubernetes in 5 minutes"*

**Strategy:** Don't block on rebuilding the full portfolio. Ship a clean "coming soon"
link-in-bio page now. Takes 20 minutes. Gives you immediate web presence.
Full portfolio rebuild happens in Phase 6.

### 3.1 — tusher16.com Landing Page

The entire page lives in a Kubernetes ConfigMap — no Docker image to build.
The ConfigMap holds the HTML contents. The Deployment uses the stock nginx image and mounts the ConfigMap as a volume — no custom image needed.

Save as `tusher-landing.yaml`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: tusher-landing-html
  namespace: default
data:
  index.html: |
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Mohammad Tusher — Data & ML Engineer</title>
      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          background: #0f1117;
          color: #e2e8f0;
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .container { text-align: center; max-width: 480px; padding: 2rem; }
        .name { font-size: 2rem; font-weight: 700; color: #fff; margin-bottom: .5rem; }
        .title { font-size: 1rem; color: #64748b; margin-bottom: .5rem; }
        .location { font-size: .875rem; color: #475569; margin-bottom: 2rem; }
        .status {
          display: inline-block;
          background: rgba(251,191,36,.1);
          border: 1px solid rgba(251,191,36,.3);
          color: #fbbf24;
          padding: .375rem 1rem;
          border-radius: 999px;
          font-size: .8rem;
          margin-bottom: 2.5rem;
          letter-spacing: .05em;
        }
        .links { display: flex; flex-direction: column; gap: .75rem; }
        .link {
          display: block;
          padding: .875rem 1.5rem;
          border: 1px solid #1e293b;
          border-radius: 10px;
          color: #cbd5e1;
          text-decoration: none;
          background: #1e293b;
          transition: border-color .2s, color .2s;
          font-size: .95rem;
        }
        .link:hover { border-color: #3b82f6; color: #fff; }
        .footer { margin-top: 2.5rem; font-size: .75rem; color: #334155; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="name">Mohammad Tusher</div>
        <div class="title">Data & ML Engineer · Homelab Builder</div>
        <div class="location">📍 Berlin, Germany</div>
        <div class="status">🔧 Portfolio undergoing maintenance</div>
        <div class="links">
          <a class="link" href="https://www.linkedin.com/in/tusher16" target="_blank">
            💼 LinkedIn — Professional Profile
          </a>
          <a class="link" href="https://github.com/tusher16" target="_blank">
            🐙 GitHub — Code & Projects
          </a>
          <a class="link" href="https://medium.com/@tusher16" target="_blank">
            ✍️ Medium — Technical Writing
          </a>
          <a class="link" href="https://rag.tusher16.com" target="_blank">
            🤖 RAG Studio — Live ML Project
          </a>
        </div>
        <div class="footer">Running on a self-hosted K3s cluster — Berlin 🇩🇪</div>
      </div>
    </body>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tusher-landing
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tusher-landing
  template:
    metadata:
      labels:
        app: tusher-landing
    spec:
      nodeSelector:
        kubernetes.io/hostname: elitedesk-node1
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
      volumes:
        - name: html
          configMap:
            name: tusher-landing-html
---
apiVersion: v1
kind: Service
metadata:
  name: tusher-landing
  namespace: default
spec:
  selector:
    app: tusher-landing
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tusher-landing
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: traefik
  rules:
    - host: tusher16.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: tusher-landing
                port:
                  number: 80
  tls:
    - hosts:
        - tusher16.com
      secretName: tusher-landing-tls
```

```bash
kubectl apply -f tusher-landing.yaml

# Watch cert get issued (takes ~60 seconds)
kubectl get certificate -w
# tusher-landing-tls   True   tusher-landing-tls   60s
```

### 3.2 — safinakhan.com Landing Page

Same pattern — just change name, links, and host. Save as `safina-landing.yaml`
and swap in Safina's LinkedIn/GitHub/Medium links and `host: safinakhan.com`.

```bash
kubectl apply -f safina-landing.yaml
```

### 3.3 — Cloudflare DNS — Switch to Orange Cloud

Once both sites load at HTTPS → toggle both A records to proxied (orange cloud) in Cloudflare.

---

## Phase 4 — Migrate All Services from Node-2 to Node-1

**⚠️ Gate: Complete Phases 1–3 first. Node-2 must NOT be wiped until every service
below is confirmed running on Node-1 with valid HTTPS. This phase is the safety net
that makes it safe to reinstall Node-2 later.**

**Medium blog angle:** *"Migrating a Docker Compose homelab to K3s — zero downtime, one service at a time"*

### What to Remove

| Service | Reason |
|---|---|
| ~~resume-tailor~~ | Not working reliably — a broken service is a liability, not an asset |
| ~~Portainer~~ | Replaced by k9s + Headlamp |
| ~~Old Django portfolio~~ | Replaced by landing page now, full rebuild later |

### Deploy Order — What Goes Live

| Priority | Service | Domain | Status | Notes |
|---|---|---|---|---|
| ✅ Done | tusher16.com | tusher16.com | Phase 3 | Static landing page |
| ✅ Done | safinakhan.com | safinakhan.com | Phase 3 | Static landing page |
| 1 | **Flashcard App** | flashcard.tusher16.com | **Deploy first** | Already ready |
| 2 | **RAG Studio** | rag.tusher16.com | **Migrate from Node-2** | Core ML — Ollama stays on Node-2 until Phase 7 |
| 3 | **Family Finance Agent** | finance.tusher16.com | Migrate from Node-2 | FastAPI + SQLite |
| 4 | n8n | n8n.tusher16.com | Migrate from Node-2 | Automation |
| 5 | gigabyte-status | gigabyte-original-sta... | Migrate from Node-2 | Low priority |
| Later | **Full portfolio rebuild** | tusher16.com | Phase 8 | Django + CloudNativePG |

### 6.1 — Deploy Flashcard App (First New Service)

```bash
# Assuming the image is already built and pushed to ghcr.io
# Apply deployment + service + ingress

kubectl apply -f flashcard-deployment.yaml
kubectl apply -f flashcard-service.yaml
kubectl apply -f flashcard-ingress.yaml   # host: flashcard.tusher16.com

# Add DNS: Cloudflare A record flashcard → <home-public-ip> → orange cloud
# Add flashcard.tusher16.com to ddclient.conf
```

### 6.2 — Migrate RAG Studio to K3s

```bash
# Create K3s Deployment for rag-studio
# Key: OLLAMA_BASE_URL=http://ollama:11434 (K3s cluster DNS)
# Persistent volumes: data/ and vectorstore/ via hostPath on Node-1

kubectl apply -f rag-studio-deployment.yaml
# Ingress: host: rag.tusher16.com
```

### 6.3 — Migrate Family Finance Agent

```bash
# Data files are never in git — copy them to Node-1 first
scp -P <SSH_PORT> tusher16@192.168.x.x:~/family-finance-agent/data/family_budget.json \
    /tmp/family_budget.json
ssh tusher16@192.168.x.x "mkdir -p ~/finance-agent-data"
scp /tmp/family_budget.json tusher16@192.168.x.x:~/finance-agent-data/

# Then deploy as K3s pod with hostPath volume pointing to ~/finance-agent-data/
kubectl apply -f finance-agent-deployment.yaml
```

---

## Phase 5 — Verify All Services Running on Node-1 (Gate Before Node-2 Wipe)

**This phase is a deliberate pause. Run every service through its full user flow.
Only when this checklist is 100% green do you proceed to Phase 6 (Node-2 wipe).**

```bash
# Quick health check across all services
kubectl get pods -n apps        # all Running
kubectl get pods -n infra       # traefik, cert-manager Running
kubectl get certificates -A     # all Ready: True

# Test each service end-to-end
curl -I https://tusher16.com             # 200
curl -I https://safinakhan.com           # 200
curl -I https://rag.tusher16.com         # 200
curl -I https://finance.tusher16.com     # 200
curl -I https://n8n.tusher16.com         # 200
curl -I https://flashcard.tusher16.com   # 200

# Check logs for errors
kubectl logs -n apps deploy/rag-studio   --tail=20
kubectl logs -n apps deploy/n8n          --tail=20
```

> Run this for 24 hours. If everything is green after one full day → proceed to Phase 6.
> If anything is broken → fix it NOW, before you lose access to the Node-2 copy.

---

## Phase 5b — Cluster Management: k9s + Headlamp (Portainer Replacement)

### Tool 1 — k9s (already installed in Phase 1.3)

Key shortcuts for daily use:
```
:pods          → all pods across all namespaces
:deployments   → deployment list
:ingress       → see all ingress routes + domains
l              → live logs for selected pod
e              → exec shell into pod
d              → describe resource (events, config)
ctrl+d         → delete pod (K3s recreates it)
/              → filter by name
```

### Tool 2 — Headlamp (web UI)

```bash
helm repo add headlamp https://headlamp-k8s.github.io/headlamp/
helm repo update

helm install headlamp headlamp/headlamp \
  --namespace kube-system \
  --set ingress.enabled=true \
  --set "ingress.hosts[0].host=headlamp.tusher16.com" \
  --set "ingress.hosts[0].paths[0].path=/" \
  --set "ingress.hosts[0].paths[0].pathType=Prefix"
```

Add DNS: Cloudflare A record `headlamp` → `<home-public-ip>` → orange cloud.  
Add `headlamp.tusher16.com` to `/etc/ddclient.conf` on Node-1.

### Portainer Decommission

```bash
# On Node-2 before wipe — already stopped
# Remove from Cloudflare DNS: delete portainer A record
# Remove from ddclient.conf: delete portainer.tusher16.com line
# No migration needed — decommissioned entirely
```

---

## Phase 6 — Reinstall Node-2 + Join as K3s Worker

**⚠️ Hard gate: Do NOT start this phase until Phase 4 (migration) and Phase 5
(verification) are fully complete. Every service must be confirmed running on Node-1
with valid HTTPS. Wiping Node-2 before migration = guaranteed data loss.**

### Pre-Wipe Final Verification Checklist
```
[ ] tusher16.com loads at HTTPS on Node-1
[ ] safinakhan.com loads at HTTPS on Node-1
[ ] rag.tusher16.com loads and chat works
[ ] finance.tusher16.com loads and data shows
[ ] n8n.tusher16.com loads and workflows exist
[ ] flashcard.tusher16.com loads
[ ] All confirmed for 24 hours with no errors in kubectl logs
```
Only proceed when ALL boxes are checked.

### 4.1 — Backup Node-2 Before Wipe

```bash
# What models does Ollama currently have?
ssh tusher16@192.168.x.x -p <SSH_PORT>
docker exec -it ollama ollama list > ~/ollama_models_backup.txt
scp -P <SSH_PORT> tusher16@192.168.x.x:~/ollama_models_backup.txt ~/Desktop/

# Confirm all services are already running on Node-1
kubectl get pods   # should show all services healthy
```

### 4.2 — Flash Ubuntu Server 24.04 LTS on Node-2

1. Download Ubuntu Server 24.04 LTS ISO
2. Flash USB with Balena Etcher
3. Boot Node-2, install Ubuntu Server (minimal — no desktop GUI)
4. Hostname: `optiplex-worker`
5. Static IP: `192.168.x.x` (same — CI/CD and cluster refs unchanged)
6. Enable OpenSSH, create user `tusher16`

### 4.3 — Post-Install (No Docker — K3s only)

```bash
ssh tusher16@192.168.x.x   # port 22 on fresh install

sudo apt update && sudo apt upgrade -y

# ── Time sync — CRITICAL for K3s TLS certificates ──
# K3s TLS certificates are time-sensitive. If Node-2's clock drifts from
# Node-1 by more than a few seconds, the agent will fail to join with
# certificate errors. chrony is lighter than ntpd and works reliably.
sudo apt install -y chrony
sudo systemctl enable --now chrony
chronyc tracking   # confirm sync status — "System time" should be < 1ms offset

# Change SSH port to <SSH_PORT> (convention)
sudo nano /etc/ssh/sshd_config   # port <SSH_PORT>
sudo systemctl restart sshd

# Install K3s agent — no Docker needed, containerd is built in
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.33.11+k3s1 \
  K3S_URL=https://192.168.x.x:6443 \
  K3S_TOKEN=<token-from-phase-1.4> \
  sh -s - agent
  # ⚠️ MUST match Node-1's version exactly — mixed minor versions cause issues
```

### 4.4 — Verify Both Nodes on Mac Mini

```bash
kubectl get nodes -o wide
# NAME               STATUS   ROLES                  AGE
# elitedesk-node1       Ready    control-plane,master   Xh
# optiplex-worker    Ready    <none>                 2m
```

### 4.5 — Label Node-2

```bash
kubectl label node optiplex-worker workload=llm-inference
kubectl label node optiplex-worker workload=heavy-ml
```

---

## Phase 7 — Ollama as a K3s Pod on Node-2

After Node-2 joins the cluster (Phase 4):

```yaml
# ollama-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
    spec:
      nodeSelector:
        kubernetes.io/hostname: optiplex-worker   # always on Node-2
      containers:
        - name: ollama
          image: ollama/ollama:0.7.0  # pin — check https://hub.docker.com/r/ollama/ollama/tags
          ports:
            - containerPort: 11434
          env:
            - name: OLLAMA_KEEP_ALIVE
              value: "-1"
            - name: OLLAMA_NUM_PARALLEL
              value: "1"        # CPU-only: limit to 1 parallel request
            - name: OLLAMA_MAX_LOADED_MODELS
              value: "1"        # only keep 1 model in memory at a time
          resources:
            requests:
              cpu: "1"
              memory: "6Gi"
            limits:
              cpu: "4"          # i5-4590S has 4 cores
              memory: "14Gi"    # leave 2Gi headroom from 16Gi
          volumeMounts:
            - name: ollama-data
              mountPath: /root/.ollama
      volumes:
        - name: ollama-data
          hostPath:
            path: /var/lib/ollama
            type: DirectoryOrCreate
---
apiVersion: v1
kind: Service
metadata:
  name: ollama
  namespace: default
spec:
  selector:
    app: ollama
  ports:
    - port: 11434
      targetPort: 11434
  type: ClusterIP   # internal only — http://ollama:11434 inside cluster
```

```bash
kubectl apply -f ollama-deployment.yaml

# Pull models — CPU-only model recommendations (March 2026 enterprise guide)
# ✅ Recommended for CPU-only i5-4590S (16GB DDR3):
#   - phi4-mini (3.8B)   → best quality/speed tradeoff on CPU
#   - qwen2.5:1.5b       → very fast, good for short tasks
#   - smollm2:1.7b       → ultra-lightweight
# ⚠️ Acceptable but slow:
#   - qwen2.5:3b         → current default, usable but ~2–5 tok/s
# ❌ Avoid on CPU-only:
#   - anything > 7B parameters at Q4 quantization fills all 16GB

kubectl exec -it deploy/ollama -- ollama pull phi4-mini
kubectl exec -it deploy/ollama -- ollama pull qwen2.5:1.5b

# Verify pod is on Node-2
kubectl get pods -o wide | grep ollama
# ollama-xxx   1/1   Running   optiplex-worker
```

---

## Phase 8 — CloudNativePG (Production PostgreSQL)

**Medium blog angle:** *"Running production-grade PostgreSQL on K3s with CloudNativePG — no more SQLite"*

> This is what Mischa van den Burg (KubeCraft) and production Kubernetes teams use.
> It manages the full PostgreSQL lifecycle: provisioning, backups, failover, upgrades.

### 8.1 — Install CloudNativePG Operator

> 🔴 **CRITICAL:** Do NOT install 1.25.1 or anything older than 1.28.3/1.29.1.
> CVE-2026-44477 (Critical, CVSS 9.4) was disclosed May 2026 — the metrics
> exporter authenticated as postgres superuser, allowing privilege escalation.
> CNPG team: *"All users should upgrade immediately."*
> Current supported series: **1.29.1** (latest) and **1.28.3**.

```bash
# Install CNPG 1.29.1 — pinned version (confirmed CVE-free as of May 2026)
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.29/releases/cnpg-1.29.1.yaml

kubectl get pods -n cnpg-system -w
# cloudnative-pg-xxxx   1/1   Running
```

### 8.2 — Create PostgreSQL Cluster

> ⚠️ **Namespace:** ALL CNPG resources (Cluster, Databases, Secrets) must be in the
> SAME namespace. We use `databases`. Keep this consistent throughout.
>
> ⚠️ **local-path storage honesty:** `local-path` = hostPath under the hood.
> If Node-1's SSD fails, your data is gone. R2 backup (below) is your ONLY safety net.
> In your ADR, document: *"RPO ~5min via WAL streaming, RTO ~30min via R2 restore.
> local-path chosen for homelab simplicity. Not suitable if Node-1 disk fails."*

```yaml
# postgres-cluster.yaml — CNPG 1.29.1, namespace: databases, backup from minute zero
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-cluster
  namespace: databases          # ← consistent namespace — everything CNPG goes here
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:17.5  # PostgreSQL 17 LTS (CNPG 1.29 default)

  postgresql:
    pg_hba:
      - host all all 10.42.0.0/16 scram-sha-256

  storage:
    size: 10Gi
    storageClass: local-path

  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - elitedesk-node1

  bootstrap:
    initdb:
      database: portfolio
      owner: portfolio_user
      secret:
        name: portfolio-db-secret   # must also be in namespace: databases

  # ── Backups — MUST be in initial manifest, not added later ──────────────────
  # Any data written before backup is configured has NO off-machine copy.
  backup:
    barmanObjectStore:
      destinationPath: s3://homelab-backups/postgres/
      endpointURL: https://<account-id>.r2.cloudflarestorage.com
      s3Credentials:
        accessKeyId:
          name: cloudflare-r2-secret
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: cloudflare-r2-secret
          key: SECRET_ACCESS_KEY
    retentionPolicy: "30d"        # 30 days, not 7d — gives you a month to notice data loss
```

```bash
# Create R2 secret FIRST, then DB secret, then cluster
kubectl create secret generic cloudflare-r2-secret \
  --from-literal=ACCESS_KEY_ID=<r2-key-id> \
  --from-literal=SECRET_ACCESS_KEY=<r2-secret> \
  -n databases

# Create DB secret in SAME namespace as Cluster
kubectl create secret generic portfolio-db-secret \
  --from-literal=username=portfolio_user \
  --from-literal=password=<strong-random-password> \
  -n databases                  # ← must match Cluster namespace

kubectl apply -f postgres-cluster.yaml

# Watch cluster come up
kubectl get clusters -n databases -w
```

### 8.3 — Auto-Created Services

```
postgres-cluster-rw   → read-write primary   ← use this in Django/FastAPI
postgres-cluster-ro   → read-only replicas
postgres-cluster-r    → all instances
```

Django connection: `postgres-cluster-rw.default.svc.cluster.local:5432`

### 8.4 — Create Databases (Declarative CRD — NOT kubectl exec)

> ⚠️ **Critical:** Do NOT use `kubectl exec psql` for standard database creation.
> CloudNativePG v1.25+ provides a native `Database` CRD. This keeps your
> database state code-driven, tracked in Git, and fully resilient if the pod
> is rescheduled. Confirmed in official CNPG v1.25 documentation.

Save as `databases/tusher-portfolio-db.yaml`:

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: tusher-portfolio-db
  namespace: databases
spec:
  name: tusher_portfolio
  owner: portfolio_user
  cluster:
    name: postgres-cluster
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: safina-portfolio-db
  namespace: databases
spec:
  name: safina_portfolio
  owner: portfolio_user
  cluster:
    name: postgres-cluster
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: finance-agent-db
  namespace: databases
spec:
  name: finance_agent
  owner: portfolio_user
  cluster:
    name: postgres-cluster
```

```bash
kubectl apply -f databases/tusher-portfolio-db.yaml

# Verify all 3 databases were created by the operator
kubectl get databases -n databases
# NAME                  APPLIED   AGE
# tusher-portfolio-db   true      30s
# safina-portfolio-db   true      30s
# finance-agent-db      true      30s
```

### 8.5 — Accessing PostgreSQL from Mac Mini (Secure Port-Forward)

> **Never** expose PostgreSQL to the public internet via Traefik Ingress.
> Use `kubectl port-forward` — tunnels port 5432 securely over your kubeconfig
> connection. No router holes, no public DB exposure.

```bash
# On your Mac mini — forward local 5432 to the cluster primary
kubectl port-forward svc/postgres-cluster-rw 5432:5432 -n databases

# Now connect from another terminal using any Postgres client
psql -h localhost -U portfolio_user -d tusher_portfolio
# or: use TablePlus / DBeaver pointing to localhost:5432
```

Add this to your runbook: `docs/runbooks/database-access.md`

### 8.5 — Database CRDs Namespace Fix

> All `Database` CRDs must be in the same namespace as the `Cluster` (`databases`).
> The `cluster.name` reference is namespace-local — there is no cross-namespace lookup.

```bash
# Verify everything is in the databases namespace
kubectl get clusters,databases,secrets -n databases
```

### 8.6 — Django Connection String (Updated Namespace)

```python
# settings.py — use databases namespace in the service DNS
DATABASES = {
    'default': {
        'HOST': 'postgres-cluster-rw.databases.svc.cluster.local',  # ← not default
        'PORT': '5432',
    }
}
```

---

## Phase 9 — Full Portfolio Rebuild (tusher16.com + safinakhan.com)

**Replaces the static landing pages from Phase 3 when ready.**

### Stack

- Django 5 + Gunicorn
- Tailwind CSS (modern, no jQuery, no Bootstrap from 2018)
- PostgreSQL via CloudNativePG (`postgres-cluster-rw`)
- GitHub Actions CI/CD → push to main → auto-deploy to K3s

### Content — Mohammad's Portfolio (tusher16.com)

```
Hero        — Name, title, 1-line pitch, GitHub + LinkedIn + CV buttons
About       — Bio: Data/ML Engineer, Berlin, homelab builder
Skills      — Icon grid: Python, FastAPI, Django, K3s, Docker, Ollama, PyTorch
Projects    — Cards from DB: RAG Studio, Finance Agent, Flashcard App, homelab
Experience  — Timeline from Django admin
Contact     — Form → SMTP email
```

### Deployment to K3s

```yaml
# Replace tusher-landing Ingress with the Django app
# Same host: tusher16.com, new backend: tusher-portfolio:8000
```

---

## Final State — Node Summary

### Node-1 — HP EliteDesk 705 G4 (192.168.x.x) — K3s Master
| Service | Domain | Type |
|---|---|---|
| Traefik | — | Built-in ingress controller |
| cert-manager | — | Automatic SSL for all services |
| tusher16.com | tusher16.com | Static → later Django portfolio |
| safinakhan.com | safinakhan.com | Static → later Django portfolio |
| Flashcard App | flashcard.tusher16.com | K3s pod |
| RAG Studio | rag.tusher16.com | K3s pod |
| Finance Agent | finance.tusher16.com | K3s pod |
| n8n | n8n.tusher16.com | K3s pod |
| Headlamp | headlamp.tusher16.com | K3s pod |
| CloudNativePG | internal | K3s pod |

### Node-2 — Dell OptiPlex 9020 (192.168.x.x) — K3s Worker
| Service | Access | Type |
|---|---|---|
| Ollama | http://ollama:11434 (internal) | K3s pod, nodeSelector: optiplex-worker |
| ML batch jobs | — | K3s pods, label: llm-inference |

> Can be shut down when idle — ~€14/month power saving.

### Node-3 — Arduino Uno Q — Monitoring (Standalone)
- Uptime Kuma, Grafana, Prometheus — always on, ARM64, low power

### Mac Mini — Management
- k9s, kubectl — connects via kubeconfig to Node-1

---

## Master Checklist

### Phase 0 — Network
```
[ ] Node-1 static IP: 192.168.x.x
[ ] Node-2 static IP: 192.168.x.x (unchanged)
[ ] Router: port 80/443 forwarded to Node-1
```

### Phase 1 — K3s Master
```
[ ] K3s installed on Node-1
[ ] kubectl get nodes shows elitedesk-node1 Ready
[ ] kubeconfig copied to Mac mini (~/.kube/config)
[ ] k9s installed and connects
[ ] Worker join token saved
```

### Phase 2 — Traefik + cert-manager
```
[ ] cert-manager pods running in cert-manager namespace
[ ] ClusterIssuer letsencrypt-prod created and Ready
[ ] Test Ingress: deploy whoami pod, verify HTTPS works end-to-end
```

### Phase 3 — Landing Pages
```
[ ] tusher16.com landing page deployed (ConfigMap + Deployment + Ingress)
[ ] safinakhan.com landing page deployed
[ ] Both load with valid Let's Encrypt SSL
[ ] Both Cloudflare A records switched to orange cloud (proxied)
[ ] ddclient.conf updated on Node-1
```

### Phase 4 — Node-2 Reinstall
```
[ ] All Node-2 services confirmed on Node-1
[ ] Ollama model list backed up
[ ] Ubuntu Server 24.04 LTS installed (no desktop, no Docker)
[ ] Static IP 192.168.x.x assigned
[ ] SSH port changed to <SSH_PORT>
[ ] K3s agent installed and joined cluster
[ ] kubectl get nodes shows both nodes Ready
[ ] Node-2 labeled: workload=llm-inference
```

### Phase 5 — Cluster Management
```
[ ] k9s connects, shows all pods
[ ] Headlamp deployed and accessible at headlamp.tusher16.com
[ ] portainer.tusher16.com DNS record deleted from Cloudflare
```

### Phase 6 — Projects
```
[ ] resume-tailor decommissioned
[ ] Flashcard App deployed at flashcard.tusher16.com
[ ] RAG Studio migrated to K3s at rag.tusher16.com
[ ] Finance Agent migrated to K3s at finance.tusher16.com (data files SCP'd)
[ ] n8n migrated
[ ] All services have valid HTTPS via Traefik + cert-manager
```

### Phase 7 — Ollama on K3s
```
[ ] ollama Deployment applied, pod on optiplex-worker
[ ] qwen2.5:3b pulled inside pod
[ ] RAG Studio OLLAMA_BASE_URL=http://ollama:11434 confirmed working
```

### Phase 8 — CloudNativePG
```
[ ] Operator installed
[ ] postgres-cluster running (1 instance on Node-1)
[ ] All databases created
[ ] Backups configured (Cloudflare R2 or MinIO)
```

---

## Timeline Estimate

| Phase | What | Time |
|---|---|---|
| 0 | Network pre-flight | 30 min |
| 1 | K3s on Node-1 | 30 min |
| 2 | Traefik + cert-manager | 45 min |
| 3 | Both landing pages live | 30 min |
| 4 | Node-2 reinstall + join cluster | 2–3 hours |
| 5 | k9s + Headlamp | 30 min |
| 6 | Flashcard + RAG + Finance deploy | 1 evening |
| 7 | Ollama on K3s | 30 min |
| 8 | CloudNativePG | 2–3 hours |
| 9 | Full portfolio rebuild | 2–3 days |

**MVP (Phases 0–3): Get cluster running + landing pages live = ~2.5 hours one evening.**

---

## Medium Blog Series — Article Map

| Article | Phase | Title Idea |
|---|---|---|
| 1 | 0–1 | "Installing K3s on a €80 refurbished PC — my production homelab" |
| 2 | 2 | "Replacing jwilder/nginx-proxy with K3s-native Traefik + cert-manager" |
| 3 | 3 | "Deploying a static site to Kubernetes in 5 minutes with ConfigMaps" |
| 4 | 4 | "Wiping a Docker server and rebuilding it as a K3s worker node" |
| 5 | 5 | "Replacing Portainer: k9s and Headlamp for Kubernetes cluster management" |
| 6 | 6–7 | "Migrating RAG Studio from Docker Compose to K3s — what changed" |
| 7 | 8 | "Running production PostgreSQL on K3s with CloudNativePG" |
| 8 | 9 | "Rebuilding my portfolio from scratch: Django + Tailwind + CloudNativePG on K3s" |


---

## Mimir / Jotunheim Architecture — Adapted for Your 2-Node Setup

From Mischa's screenshots (Image 1), his architecture separates two clusters:
- **Mimir** = stateful workloads (Databases + Git server)
- **Jotunheim** = stateless workloads (Applications)

With 2 x86 nodes you cannot run two fully separate clusters. But you can **mirror this
exact pattern using Kubernetes namespaces + node affinity** — and it's arguably cleaner.

### Your Adapted Architecture (Namespaces = Logical Clusters)

```
┌─────────────────────────────────────────────────────────┐
│  Node-1: HP EliteDesk (K3s Master — 192.168.x.x)     │
│                                                          │
│  namespace: infra          ← Traefik, cert-manager,      │
│                               Headlamp, Homepage         │
│                                                          │
│  namespace: databases      ← CloudNativePG Cluster       │
│  (= "Mimir" concept)          nodeSelector: elitedesk-node1 │
│                               All DB clusters live here  │
│                                                          │
│  namespace: apps           ← Portfolios, RAG Studio,     │
│  (= "Jotunheim" concept)      Finance Agent, n8n,        │
│                               Flashcard App              │
└────────────────────┬────────────────────────────────────┘
                     │ K3s cluster (containerd)
┌────────────────────▼────────────────────────────────────┐
│  Node-2: Dell OptiPlex (K3s Worker — 192.168.x.x)    │
│                                                          │
│  namespace: ml             ← Ollama, LayoutLMv3,         │
│  (heavy compute)              ML batch jobs              │
│                               nodeSelector: optiplex     │
│                               Shut down when idle        │
└─────────────────────────────────────────────────────────┘
```

### Why This Separation Matters (and What It Teaches You)

| Mischa's Concept | Your Implementation | Production Equivalent |
|---|---|---|
| Mimir cluster (stateful) | `databases` namespace + node affinity | AWS RDS / GCP Cloud SQL isolation |
| Jotunheim cluster (stateless) | `apps` namespace, can float to either node | Application tier, horizontally scalable |
| Separate Git server (Forgejo) | GitHub (public) + private repo | GitOps source of truth |
| Two physical clusters | Two namespaces + node labels | Multi-environment (staging/prod) separation |

> The reason production teams separate stateful from stateless is operational:
> you can scale, restart, and redeploy stateless app pods freely without ever
> touching the database tier. CloudNativePG in its own namespace enforces this boundary.

### Create the Namespaces

```bash
kubectl create namespace infra
kubectl create namespace databases
kubectl create namespace apps
kubectl create namespace ml

# Label for readability in k9s and Headlamp
kubectl label namespace databases purpose=stateful
kubectl label namespace apps purpose=stateless
kubectl label namespace ml purpose=heavy-compute
```

---

## Homepage Dashboard — Your Service Control Panel

This is exactly what Mischa runs in Image 2 at `homepage.mischavandenburg.net`.
It is the **gethomepage.dev** project — a Kubernetes-native dashboard that
**auto-discovers all your services from Ingress annotations**. No manual config needed.

### Why Homepage over Everything Else

| Feature | Homepage | Heimdall | Homarr |
|---|---|---|---|
| Kubernetes-native service discovery | ✅ Auto via Ingress annotations | ❌ Manual | ❌ Manual |
| Real-time pod status | ✅ Yes | ❌ No | ❌ No |
| CPU/memory cluster widgets | ✅ Yes | ❌ No | Partial |
| Config as code (GitOps) | ✅ YAML ConfigMap | ❌ UI-driven | ❌ UI-driven |
| K3s + Traefik integration | ✅ Native | ❌ No | ❌ No |

### Deploy Homepage to K3s

Save as `homepage.yaml`:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: homepage
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: homepage
  namespace: homepage
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: homepage
rules:
  - apiGroups: [""]
    resources: ["namespaces", "pods", "nodes", "services", "endpoints"]
    verbs: ["get", "list"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list"]
  - apiGroups: ["metrics.k8s.io"]
    resources: ["nodes", "pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: homepage
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: homepage
subjects:
  - kind: ServiceAccount
    name: homepage
    namespace: homepage
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: homepage-config
  namespace: homepage
data:
  settings.yaml: |
    title: "Tusher Homelab"
    theme: dark
    color: slate
  kubernetes.yaml: |
    mode: cluster
  widgets.yaml: |
    - kubernetes:
        cluster:
          show: true
          cpu: true
          memory: true
          showLabel: true
          label: "elitedesk-node1 (master)"
        nodes:
          show: true
          cpu: true
          memory: true
  services.yaml: |
    - Infrastructure:
        - Headlamp:
            href: https://headlamp.tusher16.com
            description: K3s cluster UI
            icon: kubernetes.png
        - Grafana:
            href: http://192.168.x.x:3000
            description: Metrics dashboards
            icon: grafana.png
        - Uptime Kuma:
            href: http://192.168.x.x:3001
            description: Uptime monitoring
            icon: uptime-kuma.png
    - Projects:
        - RAG Studio:
            href: https://rag.tusher16.com
            description: ML/RAG pipeline
        - Finance Agent:
            href: https://finance.tusher16.com
            description: Family finance AI
        - Flashcard App:
            href: https://flashcard.tusher16.com
            description: Flashcard learning app
        - n8n:
            href: https://n8n.tusher16.com
            description: Workflow automation
    - Portfolios:
        - Mohammad:
            href: https://tusher16.com
        - Safina:
            href: https://safinakhan.com
    - Create:
        - GitHub:
            href: https://github.com/tusher16
        - Medium:
            href: https://medium.com/@tusher16
        - LinkedIn:
            href: https://linkedin.com/in/tusher16
  bookmarks.yaml: |
    - Dev Tools:
        - Cloudflare:
            - href: https://dash.cloudflare.com
        - GitHub:
            - href: https://github.com/tusher16
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: homepage
  namespace: homepage
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: homepage
  template:
    metadata:
      labels:
        app.kubernetes.io/name: homepage
    spec:
      serviceAccountName: homepage
      automountServiceAccountToken: true
      nodeSelector:
        kubernetes.io/hostname: elitedesk-node1
      containers:
        - name: homepage
          image: ghcr.io/gethomepage/homepage:latest
          ports:
            - containerPort: 3000
          volumeMounts:
            - mountPath: /app/config
              name: config
      volumes:
        - name: config
          configMap:
            name: homepage-config
---
apiVersion: v1
kind: Service
metadata:
  name: homepage
  namespace: homepage
spec:
  selector:
    app.kubernetes.io/name: homepage
  ports:
    - port: 3000
      targetPort: 3000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: homepage
  namespace: homepage
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: traefik
  rules:
    - host: home.tusher16.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: homepage
                port:
                  number: 3000
  tls:
    - hosts:
        - home.tusher16.com
      secretName: homepage-tls
```

```bash
kubectl apply -f homepage.yaml

# Add DNS: Cloudflare A record 'home' → <home-public-ip> → orange cloud
# Add home.tusher16.com to ddclient.conf
```

### Auto-Discovery: Add This Annotation to Every Ingress

Once Homepage is deployed, any service with these annotations **appears automatically**:

```yaml
# Add to every Ingress metadata.annotations:
annotations:
  gethomepage.dev/enabled: "true"
  gethomepage.dev/name: "RAG Studio"
  gethomepage.dev/group: "Projects"
  gethomepage.dev/icon: "https://raw.githubusercontent.com/.../icon.png"
  gethomepage.dev/description: "ML/RAG pipeline — ChromaDB + Ollama"
```

No manual services.yaml update needed — Homepage auto-discovers it.

---

## Git Repository Strategy — Full Picture

### The Complete GitHub Ecosystem (All Your Repos)

You have **two layers** of repos. This is important to understand:

```
Layer 1 — Infrastructure (NEW — to create)
  tusher16/homelab          → PUBLIC  → your living CV, all K3s manifests, ADRs, docs
  tusher16/homelab-private  → PRIVATE → secrets, real IPs, tokens, .env files

Layer 2 — Application Repos (EXISTING — already have CI/CD)
  tusher16/rag-studio               → PUBLIC  → RAG Studio (FastAPI + ChromaDB)
  tusher16/rag-from-scratch         → PUBLIC  → Original RAG research
  tusher16/family-finance-agent     → PRIVATE → Finance Agent (FastAPI)
  tusher16/flashcard-app            → PUBLIC  → Flashcard App (ready to deploy)
  tusher16/my-portfolio-project-django → PUBLIC  → Old portfolio (to be rebuilt)
  tusher16/safinakhan-portfolio-website-flask → PUBLIC → Safina's old portfolio
  tusher16/resume-tailor            → PUBLIC  → (decommissioning — archived)
```

### How the Two Layers Relate

```
tusher16/homelab  (infrastructure layer)
    └── apps/rag-studio/
        ├── deployment.yaml     ← K3s Deployment pointing to ghcr.io/tusher16/rag-studio
        ├── service.yaml
        └── ingress.yaml        ← host: rag.tusher16.com

tusher16/rag-studio  (application layer)
    ├── backend/main.py
    ├── Dockerfile
    ├── docker-compose.yml      ← local dev only
    └── .github/workflows/
        └── deploy.yml          ← builds image → pushes to ghcr.io → SSH deploy to K3s
```

The homelab repo holds **where and how** things run on the cluster.
The application repos hold **what** the application does.
These never mix.

---

### Where Does This Master Plan MD File Live?

**`tusher16/homelab` → `docs/master-plan.md`**

It is part of the public homelab repo documentation. Sanitised before committing
(no real IPs, no SSH port). It becomes part of your engineering story.

```
tusher16/homelab/
└── docs/
    ├── master-plan.md          ← THIS FILE (sanitised version)
    ├── architecture.md
    ├── cost-analysis.md
    ├── roadmap.md
    └── adr/
        └── ...
```

The raw version with real IPs and tokens lives in `tusher16/homelab-private`.

---

### Public Repo — `tusher16/homelab` (Complete Structure)

This is your living CV. Every hiring manager who looks at your GitHub sees this first.

```
tusher16/homelab/                              PUBLIC — your portfolio
│
├── README.md                                  ← architecture diagram + the story
│                                                 "3-node K3s cluster on refurbished hardware
│                                                  running real ML workloads — Berlin"
├── CHANGELOG.md                               ← versioned infra history
├── CONTRIBUTING.md                            ← commit conventions + PR guide
├── Taskfile.yml                               ← task runner (modern Makefile)
├── .gitignore                                 ← *.env, data/, secrets/, kubeconfig
│
├── nodes/                                     ← HARDWARE SPECS (safe, no IPs)
│   ├── README.md                              ← comparison table
│   ├── node-1-elitedesk-node1-705g4.md           ← Ryzen 3, 16GB DDR4, 256GB SSD
│   ├── node-2-dell-optiplex-9020.md           ← i5-4590S, 16GB DDR3
│   └── node-3-arduino-uno-q.md               ← ARM64, 4GB, monitoring only
│
├── cluster/                                   ← K3S BOOTSTRAP
│   ├── README.md
│   ├── k3s-install-master.sh                  ← Node-1 install script
│   ├── k3s-join-worker.sh                     ← K3S_TOKEN=<JOIN_TOKEN> placeholder
│   ├── namespaces.yaml                        ← infra/databases/apps/ml
│   └── node-labels.sh                         ← workload=llm-inference etc.
│
├── apps/                                      ← K3S MANIFESTS (per service)
│   │
│   ├── infra/                                 ← cluster infrastructure
│   │   ├── traefik-helmchartconfig.yaml       ← Traefik customisation (NOT traefik.yaml)
│   │   ├── cert-manager.yaml                  ← install manifest URL reference
│   │   ├── cluster-issuer.yaml                ← letsencrypt-prod ClusterIssuer
│   │   └── headlamp/
│   │       ├── values.yaml
│   │       └── README.md
│   │
│   ├── homepage/                              ← SERVICE DASHBOARD
│   │   ├── homepage.yaml                      ← full Deployment + RBAC + Ingress
│   │   └── README.md                          ← how auto-discovery works
│   │
│   ├── databases/                             ← CLOUDNATIVEPG (stateful namespace)
│   │   ├── postgres-cluster.yaml              ← passwords replaced with <SECRET>
│   │   ├── postgres-secret.example.yaml       ← template, no real values
│   │   └── README.md                          ← how CloudNativePG works + backup config
│   │
│   ├── rag-studio/                            ← links to tusher16/rag-studio
│   │   ├── deployment.yaml                    ← image: ghcr.io/tusher16/rag-studio:latest
│   │   ├── service.yaml
│   │   ├── ingress.yaml                       ← host: rag.tusher16.com
│   │   └── README.md                          ← points to tusher16/rag-studio for app code
│   │
│   ├── finance-agent/                         ← links to tusher16/family-finance-agent
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml                       ← host: finance.tusher16.com
│   │   ├── pvc.yaml                           ← data/ volume for family_budget.json
│   │   └── README.md
│   │
│   ├── flashcard-app/                         ← links to tusher16/flashcard-app
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml                       ← host: flashcard.tusher16.com
│   │   └── README.md
│   │
│   ├── portfolios/
│   │   ├── tusher-landing.yaml                ← static landing (ConfigMap + nginx)
│   │   ├── safina-landing.yaml
│   │   └── README.md                          ← notes full rebuild in progress
│   │
│   ├── ollama/                                ← LLM inference on Node-2
│   │   ├── deployment.yaml                    ← nodeSelector: optiplex-worker
│   │   ├── service.yaml                       ← ClusterIP: http://ollama:11434
│   │   └── README.md                          ← CPU-only inference benchmarks
│   │
│   └── n8n/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       └── pvc.yaml
│
├── monitoring/                                ← NODE-3 STANDALONE STACK
│   ├── README.md                              ← ARM64 only — monitoring node
│   ├── uptime-kuma/docker-compose.yml
│   ├── grafana/docker-compose.yml
│   └── prometheus/
│       ├── docker-compose.yml
│       └── prometheus.yml                     ← scrape_configs for Node-1 + Node-2
│
├── docs/                                      ← WHERE HIRING MANAGERS LINGER
│   │
│   ├── master-plan.md                         ← THIS FILE (sanitised version)
│   │
│   ├── adr/                                   ← ARCHITECTURE DECISION RECORDS
│   │   ├── README.md                          ← what is an ADR, when to write one
│   │   ├── 0001-k3s-over-full-kubernetes.md
│   │   ├── 0002-traefik-over-nginx-proxy.md
│   │   ├── 0003-cpu-only-ollama-inference.md
│   │   ├── 0004-cloudnativepg-over-vanilla-postgres.md
│   │   ├── 0005-namespace-separation-stateful-stateless.md
│   │   └── 0006-homepage-over-heimdall-homarr.md
│   │
│   ├── runbooks/
│   │   ├── adding-new-service.md              ← step by step: namespace + deploy + ingress
│   │   ├── worker-node-shutdown.md            ← kubectl drain procedure + safe poweroff
│   │   ├── ssl-cert-troubleshooting.md        ← cert-manager debug steps
│   │   └── disaster-recovery.md              ← reinstall K3s, restore from backup
│   │
│   ├── architecture.md                        ← narrative explanation of the full stack
│   ├── cost-analysis.md                       ← €28/month power, AWS equivalent, ROI
│   └── roadmap.md                             ← what's next: Flux GitOps, Talos long-term
│
├── diagrams/
│   ├── architecture.png                       ← sanitised IPs (192.168.x.x)
│   ├── mimir-jotunheim-adapted.png            ← namespace separation diagram
│   ├── network-topology.png
│   └── rag-pipeline.png                       ← from rag-studio docs
│
└── scripts/
    ├── health-check.sh
    ├── node-shutdown.sh                       ← kubectl drain + idle Node-2 (never raw poweroff)
    └── backup.sh
```

### Private Repo — `tusher16/homelab-private` (Never Published)

Source of truth for everything sensitive. Clone to Mac mini only.

```
tusher16/homelab-private/                      PRIVATE — never published
│
├── README.md                                  ← "this repo is private — see homelab for public"
│
├── secrets/
│   ├── cloudflare-api-token.env
│   ├── k3s-join-token.txt                     ← real token
│   ├── postgres-passwords.env
│   ├── n8n-encryption-key.env
│   └── ssh-keys/
│       └── id_ed25519.pub                     ← public key only
│
├── network/
│   ├── ddclient.conf                          ← real tokens + all subdomains
│   ├── router-config.md                       ← real IPs, port <SSH_PORT>, port forwarding
│   └── fritz-box-static-ips.md
│
├── nodes/
│   ├── node-1-connection.md                   ← real IP + SSH port
│   └── node-2-connection.md
│
└── apps/                                      ← .env files for every service
    ├── finance-agent.env                      ← ANTHROPIC_API_KEY, LOGIN_PASS, SECRET_KEY
    ├── rag-studio.env
    ├── n8n.env
    └── postgres-passwords.env
```

### Application Repos — What Changes in Each

Each existing app repo gets **two small additions** — no restructuring needed:

**1. K3s deployment manifests moved to homelab repo**  
The `docker-compose.yml` in each app repo stays for local dev.  
The K3s YAML (`deployment.yaml`, `ingress.yaml`) lives in `homelab/apps/<service>/`.

**2. GitHub Actions updated to push image to ghcr.io**  

```yaml
# .github/workflows/deploy.yml — updated pattern for K3s
name: Deploy
on:
  push:
    branches: [main]
jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Build and push image to GitHub Container Registry
      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          push: true
          tags: ghcr.io/tusher16/${{ github.event.repository.name }}:latest

      # SSH into Node-1 and roll the K3s deployment
      - name: Deploy to K3s
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SERVER_IP }}
          username: tusher16
          key: ${{ secrets.SSH_KEY }}
          port: ${{ secrets.SSH_PORT }}
          script: |
            kubectl rollout restart deployment/<service-name> -n apps
```

### Sanitisation Rules — What's Safe to Publish

| Content | Public? | Action |
|---|---|---|
| Hardware specs (CPU, RAM, storage) | ✅ Yes | Already in cluster-nodes-hardware.md |
| Architecture diagrams | ✅ Yes | Replace IPs with `192.168.x.x` |
| K3s manifests (deployment/service/ingress) | ✅ Yes | No secrets in these |
| GitHub Actions deploy.yml | ✅ Yes | Uses `${{ secrets.X }}` — safe |
| ADRs and runbooks | ✅ Yes | Write as generic guides |
| Subdomain names (rag.tusher16.com) | ✅ Yes | Already public DNS |
| `.env.example` files | ✅ Yes | Placeholder values only |
| LAN IP addresses | ❌ No | Replace with `192.168.x.x` |
| SSH port | ❌ No | Use `<SSH_PORT>` placeholder |
| Cloudflare API tokens | ❌ No | Move to homelab-private |
| K3s join token | ❌ No | Move to homelab-private |
| Real `.env` files | ❌ No | Move to homelab-private/apps/ |
| kubeconfig | ❌ No | Never commit — add to .gitignore |

### ADR Template — Use For Every Major Decision

```markdown
# ADR-0002: Traefik over jwilder/nginx-proxy

**Status:** Accepted
**Date:** May 2026

## Context
Running multiple public HTTPS websites from a single home server.
Previously used jwilder/nginx-proxy + letsencrypt-companion (Docker Compose).
Migrating to K3s — need Kubernetes-native routing and SSL.

## Options Considered
1. Keep jwilder/nginx-proxy alongside K3s (Docker container)
2. NGINX Ingress Controller (retired Nov 2025 by Kubernetes SIG Network)
3. Traefik — built into K3s, zero extra installation

## Decision
Use Traefik (K3s built-in) + cert-manager.

## Reasoning
- Zero extra install — running immediately after K3s setup
- cert-manager handles full SSL lifecycle — no companion container
- Pure YAML Ingress resources — version-controlled in Git
- Same pattern used by production Kubernetes platform teams

## Consequences
- Must customise via HelmChartConfig, not traefik.yaml directly
- Slight learning curve vs VIRTUAL_HOST env vars — worth it
```

---

## Updated Master Checklist (Complete)

### Phase 0 — Network
```
[ ] Node-1 static IP: 192.168.x.x
[ ] Node-2 static IP: 192.168.x.x (unchanged)
[ ] Router: port 80/443 forwarded to Node-1
```

### Phase 1 — K3s Master
```
[ ] K3s installed on Node-1
[ ] kubectl get nodes shows elitedesk-node1 Ready
[ ] kubeconfig copied to Mac mini (~/.kube/config, server address updated)
[ ] k9s installed on Mac and connects
[ ] Worker join token saved to homelab-private repo
```

### Phase 2 — Traefik + cert-manager
```
[ ] cert-manager pods running in cert-manager namespace
[ ] Cloudflare API token created (Zone:DNS:Edit permission)
[ ] cloudflare-api-token-secret created in cert-manager namespace
[ ] ClusterIssuer letsencrypt-prod created with DNS-01 solver (NOT http01)
[ ] ClusterIssuer shows Ready
[ ] traefik-helmchartconfig.yaml applied (HTTP→HTTPS redirect + Cloudflare trusted IPs)
[ ] Traefik reloaded — kubectl rollout status deployment/traefik -n kube-system
[ ] Test Ingress: deploy test pod, verify HTTPS works + real IP visible in logs
```

### Phase 3 — Namespaces (Mimir/Jotunheim adapted)
```
[ ] namespace: infra created
[ ] namespace: databases created and labelled purpose=stateful
[ ] namespace: apps created and labelled purpose=stateless
[ ] namespace: ml created and labelled purpose=heavy-compute
```

### Phase 4 — Landing Pages
```
[ ] tusher16.com landing page live (ConfigMap + nginx:alpine)
[ ] safinakhan.com landing page live
[ ] Both have valid Let's Encrypt SSL via cert-manager
[ ] Both Cloudflare A records set to orange cloud (proxied)
```

### Phase 5 — Homepage Dashboard
```
[ ] homepage.yaml applied to homepage namespace
[ ] home.tusher16.com DNS record added to Cloudflare
[ ] home.tusher16.com added to ddclient.conf
[ ] Dashboard loads at https://home.tusher16.com
[ ] Cluster CPU/memory widgets showing
[ ] All Ingress annotations added for auto-discovery
```

### Phase 6 — Node-2 Reinstall
```
[ ] All services confirmed running on Node-1
[ ] Ollama model list backed up
[ ] Ubuntu Server 24.04 LTS installed (no desktop, no Docker)
[ ] Static IP 192.168.x.x re-assigned
[ ] SSH port <SSH_PORT> set
[ ] K3s agent joined cluster (no Docker needed)
[ ] Both nodes Ready in kubectl get nodes
[ ] Node-2 labelled: workload=llm-inference
```

### Phase 7 — Cluster Management
```
[ ] k9s daily workflow established
[ ] Headlamp deployed at headlamp.tusher16.com
[ ] portainer DNS record deleted from Cloudflare
```

### Phase 8 — Projects Deploy
```
[ ] resume-tailor decommissioned
[ ] Flashcard App live at flashcard.tusher16.com
[ ] RAG Studio migrated to K3s at rag.tusher16.com
[ ] Finance Agent migrated (data files SCP'd to Node-1)
[ ] n8n migrated
[ ] All services have Homepage auto-discovery annotations
[ ] All services appear in home.tusher16.com dashboard
```

### Phase 9 — Ollama on K3s
```
[ ] ollama Deployment in ml namespace
[ ] Pod running on optiplex-worker (kubectl get pods -n ml -o wide)
[ ] qwen2.5:3b pulled inside pod
[ ] RAG Studio OLLAMA_BASE_URL=http://ollama.ml.svc.cluster.local:11434
```

### Phase 10 — CloudNativePG
```
[ ] Operator installed in databases namespace
[ ] postgres-cluster running, 1 instance on Node-1
[ ] All 3 Database CRDs applied (tusher-portfolio-db, safina-portfolio-db, finance-agent-db)
[ ] kubectl get databases -n databases shows all Applied: true
[ ] kubectl port-forward tested from Mac mini — can connect with psql/TablePlus
[ ] Backups to Cloudflare R2 configured (free tier)
[ ] PostgreSQL NOT exposed via any public Ingress
```

### Phase 11 — Git Repos
```
[ ] tusher16/homelab public repo created on GitHub
[ ] README.md with architecture diagram + story
[ ] All sanitised configs committed (no real IPs/tokens)
[ ] ADRs written for: K3s, Traefik, CloudNativePG, namespace separation, Homepage
[ ] tusher16/homelab-private repo created (private)
[ ] All secrets moved to homelab-private
[ ] GitHub topics: k3s homelab ollama rag fastapi berlin cloudnativepg traefik
```

---

## Updated Timeline

| Phase | What | Time |
|---|---|---|
| 0 | Network pre-flight | 30 min |
| 1 | K3s on Node-1 | 30 min |
| 2 | Traefik + cert-manager | 45 min |
| 3 | Namespace structure | 10 min |
| 4 | Both landing pages live | 30 min |
| 5 | Homepage dashboard | 45 min |
| 6 | Node-2 reinstall + join cluster | 2–3 hours |
| 7 | k9s + Headlamp | 30 min |
| 8 | Flashcard + RAG + Finance deploy | 1 evening |
| 9 | Ollama on K3s | 30 min |
| 10 | CloudNativePG | 2–3 hours |
| 11 | Git repos + ADRs | 1–2 hours |
| 12 | Full portfolio rebuild | 2–3 days |

**MVP (Phases 0–5): Cluster running + landing pages live + dashboard = ~3 hours one evening.**

---

## Medium Blog Series — Article Map

| # | Phase | Title |
|---|---|---|
| 1 | 0–1 | "Installing K3s on a €80 refurbished PC — my production homelab" |
| 2 | 2 | "Replacing jwilder/nginx-proxy with built-in K3s Traefik + cert-manager" |
| 3 | 3–4 | "Deploying a static site to Kubernetes in 5 minutes using ConfigMaps" |
| 4 | 5 | "Building a Kubernetes homelab dashboard with gethomepage.dev" |
| 5 | 6 | "Wiping a Docker server and rebuilding it as a clean K3s worker node" |
| 6 | 7 | "Replacing Portainer: k9s and Headlamp for K3s cluster management" |
| 7 | 8–9 | "Migrating RAG Studio from Docker Compose to K3s — what actually changed" |
| 8 | 10 | "Running production PostgreSQL on K3s with CloudNativePG" |
| 9 | 11 | "How I structure my homelab Git repos: public portfolio + private secrets" |
| 10 | 12 | "Rebuilding my portfolio from scratch: Django + Tailwind + CloudNativePG on K3s" |

---

---

## 🛡️ node-shutdown.sh — Corrected Safe Version

> Always drain before shutdown. Never raw poweroff a K3s worker node.
> An abrupt shutdown causes the K3s control plane to spend 5–15 minutes
> checking if Node-2 is dead, throwing NotReady alerts.

```bash
#!/bin/bash
# scripts/node-shutdown.sh
# Usage: ./node-shutdown.sh
# Safely drains Node-2 and shuts it down to save ~€14/month power

NODE="optiplex-worker"

echo "→ Draining $NODE (gracefully evicting all pods)..."
kubectl drain "$NODE" \
  --delete-emptydir-data \
  --ignore-daemonsets \
  --force \
  --timeout=120s

if [ $? -eq 0 ]; then
  echo "✓ Drain complete. Shutting down $NODE..."
  ssh -p <SSH_PORT> tusher16@192.168.x.x "sudo shutdown now"
  echo "✓ $NODE is offline. Save €14/month until next job."
else
  echo "✗ Drain failed. NOT shutting down. Check: kubectl get pods -o wide"
  exit 1
fi
```

```bash
# When you want Node-2 back (start it, then uncordon)
# 1. Power on Node-2 physically (or via WoL if configured)
# 2. Wait for K3s agent to reconnect (~60 seconds)
kubectl uncordon optiplex-worker
kubectl get nodes   # both should show Ready
```

---

## 🔍 Gemini CTO Review — Applied Corrections Summary

A senior infrastructure review identified three critical landmines in the original plan.
All three were verified against official documentation and are now fixed above.

| Issue | Severity | Status | Fix Applied |
|---|---|---|---|
| **http01 solver breaks with Cloudflare proxy** | 🔴 Critical | ✅ Fixed | Phase 2.2–2.3: Changed to `dns01` + Cloudflare API token secret |
| **Traefik config via traefik.yaml** | 🔴 Critical | ✅ Fixed | Phase 2.4: `HelmChartConfig` with HTTP redirect + trusted Cloudflare IPs |
| **kubectl exec psql for DB creation** | 🟡 Anti-pattern | ✅ Fixed | Phase 8.4: Declarative `Database` CRD for all databases |
| **kubectl port-forward for local DB access** | 🟡 Missing runbook | ✅ Added | Phase 8.5: Secure tunnel, no public DB exposure |
| **kubectl drain before Node-2 shutdown** | 🟡 Operational gap | ✅ Fixed | `scripts/node-shutdown.sh` with drain + confirmation |

### Why These Matter for Interviews

When a tech lead at a Berlin SRE/Platform Engineering role asks:

> *"Walk me through how you handle certificate lifecycle in your homelab"*

You say: *"I use cert-manager with a dns01 Cloudflare solver because my origin is
behind the Cloudflare proxy — http01 fails on renewal with a 526 error. I discovered
this through reviewing the cert-manager GitHub issues and fixed it before it blew up."*

That answer tells them you understand production failure modes, not just happy paths.

> *"How do you manage your PostgreSQL databases?"*

You say: *"Declaratively — I use CloudNativePG's `Database` CRD. No kubectl exec.
Every database is defined as a YAML resource in Git, the operator reconciles it,
and I use port-forward for local access rather than exposing port 5432 to the internet."*

That's exactly what a senior engineer running CloudNativePG in production does.

---

## ⚠️ Architecture Risks & Single Points of Failure

### Known SPOF: Single K3s Master Node

With only one master node (Node-1), the embedded etcd datastore is a single point of failure.
If Node-1 fails, the entire cluster goes down including all public websites.

| Risk | Impact | Mitigation |
|---|---|---|
| Node-1 hardware failure | All services offline | Phase 12: Add third x86 node as second master (HA etcd) |
| etcd corruption | Cluster unrecoverable | CloudNativePG backups to R2 protect DB data; K3s state is separate |
| Node-2 failure | Ollama offline, ML jobs stop | Public sites unaffected (all on Node-1) — drain + restart Node-2 |
| Node-3 failure | Monitoring blind | Uptime Kuma external check (uptimerobot.com) as backup |

> For a job portfolio homelab, single-master is acceptable and expected.
> Acknowledge this trade-off explicitly in your ADRs — interviewers respect
> engineers who know their architecture's limits, not ones who pretend it's perfect.

### Resource Limits — Required on Every Deployment

Without CPU/memory limits, a single runaway pod (RAG ingestion, Ollama, n8n workflow)
can starve all other services on Node-1.

```yaml
# Add to every Deployment spec.containers[]:
resources:
  requests:
    cpu: "100m"      # minimum guaranteed CPU
    memory: "256Mi"  # minimum guaranteed memory
  limits:
    cpu: "500m"      # hard cap — prevents starvation
    memory: "512Mi"  # adjust per service

# Rough limits per service:
# tusher-landing: cpu 50m/100m, memory 32Mi/64Mi
# rag-studio:     cpu 500m/2000m, memory 1Gi/4Gi
# finance-agent:  cpu 200m/500m, memory 256Mi/512Mi
# n8n:            cpu 200m/500m, memory 512Mi/1Gi
# ollama:         cpu 1000m/4000m, memory 6Gi/14Gi  (Node-2 only)
```

### Resource Quotas per Namespace

```yaml
# Apply per-namespace quotas to prevent one namespace consuming everything
apiVersion: v1
kind: ResourceQuota
metadata:
  name: apps-quota
  namespace: apps
spec:
  hard:
    requests.cpu: "2"
    requests.memory: "4Gi"
    limits.cpu: "4"
    limits.memory: "8Gi"
    pods: "20"
```

---

## 🔒 Security Hardening Checklist

### Headlamp & Homepage — Restrict Public Access

Both services are exposed via public Ingress. Without auth, anyone can reach them.

**Option A — Traefik BasicAuth Middleware (simplest):**
```yaml
# Create middleware
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: basic-auth
  namespace: kube-system
spec:
  basicAuth:
    secret: basic-auth-secret
---
# Create the secret (htpasswd format)
# htpasswd -nb tusher16 <password> | base64
kubectl create secret generic basic-auth-secret \
  --from-literal=users="tusher16:<htpasswd-hash>" \
  -n kube-system
```

Then add to Headlamp and Homepage Ingress annotations:
```yaml
traefik.ingress.kubernetes.io/router.middlewares: kube-system-basic-auth@kubernetescrd
```

**Option B — OIDC via Headlamp (production-grade):**
Headlamp supports OIDC authentication natively. Combine with Authentik or Keycloak
(self-hosted) or use GitHub OAuth for a single sign-on experience across all cluster UIs.

### Certificate Expiration Monitoring

Add to Uptime Kuma on Node-3:
- Monitor type: **SSL Certificate**
- Add each domain: tusher16.com, rag.tusher16.com, finance.tusher16.com, etc.
- Alert when certificate expires in < 14 days (cert-manager renews at ~30 days, this is your safety net)

```bash
# Also check via kubectl
kubectl get certificates -A
# NAME              READY   SECRET            AGE
# tusher-tls        True    tusher-tls        10d
# rag-studio-tls    True    rag-studio-tls    5d
```

### Pod Security Standards

```yaml
# Apply to production namespaces
kubectl label namespace apps pod-security.kubernetes.io/enforce=baseline
kubectl label namespace databases pod-security.kubernetes.io/enforce=restricted
```

---

## 🚀 Roadmap — What Comes After the MVP

### Phase 12 — GitOps with Flux (Recommended Next Step)

Currently the plan uses `kubectl apply` manually. The production-grade evolution is **Flux CD**:

- Flux watches your `tusher16/homelab` Git repo
- Any commit to `main` → Flux automatically reconciles the cluster
- Provides automatic rollback, drift detection, and full audit trail
- This is exactly what Mischa van den Burg runs in production

```bash
# Install Flux CLI on Mac mini
brew install fluxcd/tap/flux

# Bootstrap Flux into your cluster (connects to your GitHub repo)
flux bootstrap github \
  --owner=tusher16 \
  --repository=homelab \
  --branch=main \
  --path=./apps \
  --personal
```

After this, `git push` IS your deployment. No more SSH + kubectl apply.

### Phase 13 — Gateway API Migration (Future-Proofing)

K3s v1.32+ ships with **Traefik v3** which includes Gateway API support.
K3s comes with Traefik v3, which includes optional support for the Gateway API. To enable it, deploy a HelmChartConfig that sets `providers.kubernetesGateway.enabled: true`.

Gateway API offers more expressive routing than Ingress — think `HTTPRoute` instead of
`Ingress` objects. Not required now, but worth migrating to for future-proofing.

```yaml
# Enable Gateway API in your existing HelmChartConfig
# Add to traefik-helmchartconfig.yaml:
spec:
  valuesContent: |
    providers:
      kubernetesGateway:
        enabled: true
    # ... rest of your existing config
```

> Migrate from Ingress → HTTPRoute one service at a time. Both work simultaneously.

### Phase 14 — HA Master (Third x86 Node)

Add a third x86 node (another refurbished OptiPlex or EliteDesk from Kleinanzeigen):
- Eliminates the single-master SPOF
- K3s supports embedded etcd HA with 3 master nodes natively
- Node-3 (Arduino) stays as monitoring — ARM64 limitations unchanged

---

## 📋 ChatGPT Review — Applied Additions Summary

A second independent technical review identified 14 items not covered in the original plan.
All have been verified and applied above.

| Addition | Priority | Applied Where |
|---|---|---|
| **chrony time sync before K3s join** | 🔴 Critical | Phase 4.3 — added as first post-install step |
| **K3s v1.32+ ships Traefik v3** | ✅ Info | Fact-check table updated |
| **Gateway API available in K3s via HelmChartConfig** | ✅ Info | Fact-check + Phase 13 Roadmap |
| **Ollama resource requests/limits** | 🟡 Operational | Phase 7 — added to Deployment YAML |
| **Ollama NUM_PARALLEL + MAX_LOADED_MODELS** | 🟡 Operational | Phase 7 — added env vars |
| **Phi-4-mini / SmolLM2 model recommendations** | 🟡 Operational | Phase 7 — model selection guide |
| **Resource requests/limits on all pods** | 🟡 Required | Architecture Risks section |
| **Resource quotas per namespace** | 🟡 Required | Architecture Risks + Security section |
| **Liveness/readiness probes for static sites** | 🟡 Operational | Architecture Risks section |
| **OIDC / BasicAuth for Headlamp + Homepage** | 🟡 Security | Security Hardening section |
| **Certificate expiration alerts in Uptime Kuma** | 🟡 Monitoring | Security Hardening section |
| **Pod security standards per namespace** | 🟡 Security | Security Hardening section |
| **Flux GitOps as next evolution** | 📅 Roadmap | Phase 12 added |
| **Single-master SPOF acknowledged** | 📅 Architecture | Architecture Risks section |

### Where ChatGPT Differs from Gemini

| Topic | Gemini | ChatGPT | Verdict |
|---|---|---|---|
| dns01 vs http01 with Cloudflare | "ALWAYS dns01" | "http01 or dns01 as appropriate" | **Gemini is correct** — if orange cloud is on, http01 WILL fail. dns01 is mandatory. |
| Traefik config | HelmChartConfig only | HelmChartConfig only | Both agree ✅ |
| CloudNativePG Database CRD | Must use CRD | CRD is correct | Both agree ✅ |

---

## Phase 0 — Cloudflare Tunnel (Replaces Port Forwarding Entirely)

> This is the biggest architectural upgrade in the plan.
> Cloudflare Tunnel establishes an outgoing connection from your server to
> Cloudflare's network — no inbound ports, no port forwarding, no ddclient,
> your home IP never exposed. Free tier. Works behind CGNAT.

### What Changes vs. Port Forwarding

| Before (port forwarding) | After (Cloudflare Tunnel) |
|---|---|
| Router: port 80/443 → Node-1 | No inbound rules on router — zero |
| ddclient updates A records when IP changes | Tunnel doesn't care about your IP |
| "30 seconds downtime when switching port forwarding" | No switching needed, ever |
| Home IP visible momentarily to attackers | Home IP never exposed — Cloudflare sees only their own edge |
| cert-manager + dns01 solver needed for SSL | Optional — Cloudflare can terminate SSL at edge |
| ISP blocks inbound port 80/443? Stuck | Works through CGNAT, any ISP |

### Setup — cloudflared as K3s Deployment

**Step 1:** Create the tunnel in Cloudflare dashboard:
1. Cloudflare dashboard → Zero Trust → Networks → Tunnels → Create tunnel
2. Select **Cloudflared** → name it `homelab-k3s`
3. Copy the tunnel token — save to `homelab-private/secrets/cloudflare-tunnel-token.txt`

**Step 2:** Create the K3s secret and deployment:

```bash
# Create secret in kube-system namespace
kubectl create secret generic cloudflare-tunnel-credentials \
  --from-literal=token=<YOUR-TUNNEL-TOKEN> \
  -n kube-system
```

Save as `apps/infra/cloudflared-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: kube-system
spec:
  replicas: 2   # 2 replicas = automatic failover if one pod crashes
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      nodeSelector:
        kubernetes.io/hostname: elitedesk-node1
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared:2025.5.0   # pin version
          args:
            - tunnel
            - --no-autoupdate
            - run
            - --token
            - $(TUNNEL_TOKEN)
          env:
            - name: TUNNEL_TOKEN
              valueFrom:
                secretKeyRef:
                  name: cloudflare-tunnel-credentials
                  key: token
          livenessProbe:
            httpGet:
              path: /ready
              port: 2000
            initialDelaySeconds: 10
            periodSeconds: 10
```

```bash
kubectl apply -f apps/infra/cloudflared-deployment.yaml
```

**Step 3:** Configure public hostnames in Cloudflare dashboard:

In Zero Trust → Tunnels → your tunnel → Public Hostnames, add each service:

| Subdomain | Domain | Service (internal) |
|---|---|---|
| `@` (root) | tusher16.com | `http://tusher-landing.apps.svc.cluster.local:80` |
| `rag` | tusher16.com | `http://rag-studio.apps.svc.cluster.local:8000` |
| `finance` | tusher16.com | `http://finance-agent.apps.svc.cluster.local:8000` |
| `n8n` | tusher16.com | `http://n8n.apps.svc.cluster.local:5678` |
| `headlamp` | tusher16.com | `http://headlamp.kube-system.svc.cluster.local:3000` |
| `home` | tusher16.com | `http://homepage.homepage.svc.cluster.local:3000` |

No changes to Cloudflare DNS needed — Cloudflare manages the routing via the tunnel config.

### SSL With Cloudflare Tunnel

**Option A — Cloudflare terminates SSL (simplest, no cert-manager needed):**
- Cloudflare dashboard → SSL/TLS → Overview → set to **Full (Strict)**
- Cloudflare handles the public certificate
- cert-manager is still useful for internal services; optional for public ones

**Option B — Keep cert-manager + dns01 (defence in depth):**
- cert-manager issues certificates at origin
- Cloudflare re-encrypts via Full (Strict) mode
- Slightly more complex, slightly more secure
- **Recommended** — you've already configured it in Phase 2

### Does This Replace ddclient?

**Yes, for public traffic.** Cloudflare Tunnel doesn't need your home IP at all.
However keep ddclient running for:
- `ssh.tusher16.com` — CI/CD SSH access still needs a direct DNS record
- Any service you deliberately expose outside the tunnel

### Checklist Addition

```
[ ] Cloudflare Zero Trust account activated (free tier)
[ ] Tunnel created in Cloudflare dashboard, token saved to homelab-private
[ ] cloudflared Deployment running in kube-system (2 replicas)
[ ] All public hostnames configured in tunnel dashboard
[ ] Router port 80/443 forwarding REMOVED (no longer needed)
[ ] ddclient kept only for ssh.tusher16.com
[ ] Cloudflare Access configured for headlamp + home subdomains (see security section)
```

---

## Cloudflare Access — Replace BasicAuth (Free, Zero-Config Auth)

> Replaces both BasicAuth (weak) and self-hosted OIDC (complex).
> Free for up to 50 users. Uses GitHub/Google as identity provider.
> This is what production homelabs actually use for admin UI protection.

**Setup:**
1. Cloudflare Zero Trust → Access → Applications → Add application
2. Type: **Self-hosted**
3. App domain: `headlamp.tusher16.com` (repeat for `home.tusher16.com`)
4. Identity provider: GitHub (connect your account)
5. Policy: Email = `tusher16@gmail.com` → Allow
6. Done. Anyone hitting `headlamp.tusher16.com` gets a GitHub login prompt first.

No secrets to rotate. No htpasswd. No Authentik to maintain.

**Remove the BasicAuth middleware** from your Traefik config — Cloudflare Access
sits in front of the tunnel, before traffic ever reaches Traefik.

---

## Monitoring — Grafana Cloud Free Tier (Recommended over Uno Q)

> Running Prometheus + Grafana on the Arduino Uno Q (4GB ARM) will OOM within weeks.
> Prometheus scales memory with active series — a 2-node cluster with kube-state-metrics
> and node-exporter easily hits 1.2–1.5 GB RSS, leaving no headroom on a 2GB board.

### Recommended: Remote Write to Grafana Cloud (Free Tier)

Grafana Cloud free tier: 10,000 active metrics series, 14-day retention, free forever.

```yaml
# Deploy kube-prometheus-stack on Node-1 (K3s cluster) with remote write
# Values file: monitoring/kube-prometheus-stack-values.yaml
prometheus:
  prometheusSpec:
    remoteWrite:
      - url: https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/push
        basicAuth:
          username:
            name: grafana-cloud-secret
            key: username
          password:
            name: grafana-cloud-secret
            key: api-key
    retention: 2d        # local only 2 days — long-term in Grafana Cloud
    resources:
      requests:
        memory: 512Mi    # much lighter when not storing long-term
      limits:
        memory: 1Gi
```

```bash
# Create Grafana Cloud secret
kubectl create secret generic grafana-cloud-secret \
  --from-literal=username=<grafana-cloud-user-id> \
  --from-literal=api-key=<grafana-cloud-api-key> \
  -n monitoring
```

**Uno Q then only runs:** Uptime Kuma (monitors public endpoints, ~100MB RAM). Fits.

---

## Operational Runbooks — Incidents Log

> "Three real post-mortems beat ten architecture posts." — Claude Opus review
> Create this directory now. Fill it as things break (they will).

```
homelab/docs/incidents/
├── README.md                ← incident template (severity, timeline, RCA, action items)
├── 2026-XX-dns01-renewal.md ← cert-manager DNS-01 TXT record not cleaned up at 3am
├── 2026-XX-ollama-oom.md    ← Ollama OOM-killed itself after loading wrong model
└── 2026-XX-node2-drain.md   ← learned about reclaim policy the hard way
```

**Incident template:**
```markdown
# INC-001: [Short description]
**Date:** YYYY-MM-DD  
**Severity:** P1 / P2 / P3  
**Duration:** Xh Ym  

## Timeline
- HH:MM — first symptom detected
- HH:MM — diagnosis
- HH:MM — fix applied
- HH:MM — service restored

## Root Cause
One paragraph. No blame.

## What Broke
Technical explanation.

## Fix Applied
Commands or config changes.

## Action Items
- [ ] Add alert for X in Uptime Kuma
- [ ] Update runbook Y
```

---

## 📋 Claude Opus Review — Applied Corrections Summary

Independent "CTO-level" review by Claude Opus. All 12 missing items verified and applied.

| Issue | Severity | Applied Where |
|---|---|---|
| **CNPG 1.25.1 has CVE-2026-44477 (CVSS 9.4)** | 🔴 Ship-stopper | Phase 8.1: Updated to `cnpg-1.29.1.yaml` |
| **Cloudflare Tunnel replaces port forwarding** | 🔴 Architecture upgrade | New Phase 0: cloudflared K3s Deployment |
| **Backup must be in initial cluster manifest** | 🔴 Data loss risk | Phase 8.2: backup block merged into Cluster YAML |
| **CNPG namespace inconsistency (default vs databases)** | 🔴 Operator failure | Phase 8.2: all resources now consistently in `databases` |
| **PostgreSQL 16.3 → 17.5 (CNPG 1.29 default)** | 🟡 Version hygiene | Phase 8.2: imageName updated |
| **`--write-kubeconfig-mode 644` → 600** | 🟡 Security | Phase 1.1: fixed |
| **Phase 1.1 heading mismatch** | 🟡 Documentation | Phase 1.1: heading corrected |
| **Pin ALL versions (K3s, cert-manager, nginx, ollama)** | 🟡 Reproducibility | Phases 1, 2, 3, 7: explicit versions pinned |
| **Cloudflare IPv6 trusted IP ranges missing** | 🟡 Real IP logging | Phase 2.4: IPv6 ranges added to HelmChartConfig |
| **Cloudflare Access replaces BasicAuth** | 🟡 Security upgrade | Security section + new Cloudflare Access section |
| **Grafana Cloud free tier for monitoring** | 🟡 Operational | New monitoring section — Uno Q runs Uptime Kuma only |
| **Incidents log directory** | 📅 Portfolio value | New docs/incidents/ section with template |
| **RPO/RTO in CloudNativePG ADR** | 📅 Interview readiness | Phase 8.2: documented in inline comment |

### Scorecard — All Three Reviews Combined

| Review | Critical fixes | Important fixes | Bugs caught |
|---|---|---|---|
| Gemini | 3 | 2 | 0 |
| ChatGPT 5.5 | 1 | 10 | 0 |
| Claude Opus | 3 | 7 | 5 |
| **Total applied** | **7** | **19** | **5** |

*Last updated: May 2026 — Berlin, Germany*  
*All claims fact-checked against official docs and community sources, May 2026*  
*Stack: K3s · Traefik · cert-manager · CloudNativePG · Homepage · Ollama · Django · FastAPI*  
*Hardware: HP EliteDesk 705 G4 + Dell OptiPlex 9020 + Arduino Uno Q*  
*References: K3s docs (k3s.io), cert-manager.io, cloudnative-pg.io, gethomepage.dev, KubeCraft (Mischa van den Burg)*

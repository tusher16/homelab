# Docker Era Setup Guide
> Single-node home server · Docker Compose · 2023–2025

This is the complete setup guide for running multiple HTTPS websites on one old PC using Docker Compose. I ran this for three years on a Dell OptiPlex 9020 (€80, second-hand) without major issues.

Full story on Medium: [How I Ran My Entire Portfolio on a Single Second-Hand PC and Docker](https://medium.com/@tusher16)

---

## What You Need

**Hardware**
- Any x86 PC with at least 8 GB RAM and 100 GB storage
- Ethernet connection (WiFi works but ethernet is more stable for a server)
- Anything from eBay/Kleinanzeigen for €60–120 is fine: Dell OptiPlex, HP EliteDesk, Lenovo ThinkCentre

**Accounts (all free)**
- [Cloudflare](https://cloudflare.com) — DNS + proxy (free tier)
- [GitHub](https://github.com) — source code + CI/CD (free tier)
- A domain name — around €10/year from Namecheap or Cloudflare Registrar

**Software**
- Ubuntu Server 24.04 LTS (no desktop — headless server)
- Docker + Docker Compose
- ddclient

---

## Step 1 — Install Ubuntu Server

Download Ubuntu Server 24.04 LTS, flash it to a USB stick with [Balena Etcher](https://etcher.balena.io), and install it on your machine.

During install:
- Set a hostname (e.g. `homeserver`)
- Create a user (e.g. `yourname`)
- Enable OpenSSH server
- No desktop environment needed

After install, SSH in from your laptop:
```bash
ssh yourname@<server-local-ip>
```

---

## Step 2 — Install Docker

```bash
# Update packages
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh

# Add your user to the docker group (so you don't need sudo every time)
sudo usermod -aG docker $USER

# Log out and back in, then verify
docker --version
docker compose version
```

---

## Step 3 — Change SSH Port (security hardening)

Using port 22 means your server gets hammered by bots constantly. Change it to something non-standard.

```bash
sudo nano /etc/ssh/sshd_config
# Change: Port 22
# To:     port <SSH_PORT>  (or any number between 1024–65535)

sudo systemctl restart sshd
```

From now on SSH with:
```bash
ssh yourname@<server-ip> -p <SSH_PORT>
```

Add the shortcut to `~/.ssh/config` on your local machine. See [`ssh-config.example`](../ssh-config.example).

---

## Step 4 — Point Your Domain to Cloudflare

1. Create a free Cloudflare account
2. Add your domain — Cloudflare will give you nameservers
3. Update your domain registrar to use Cloudflare's nameservers
4. Wait 10–30 minutes for propagation

---

## Step 5 — Create DNS Records in Cloudflare

For each subdomain you want to host, add an A record in Cloudflare:

| Type | Name | Content | Proxy |
|---|---|---|---|
| A | `@` (root domain) | your-home-ip | Grey cloud first |
| A | `ssh` | your-home-ip | **Always grey cloud** |
| A | `n8n` | your-home-ip | Grey cloud first |
| A | `finance` | your-home-ip | Grey cloud first |

> **Grey cloud first, orange cloud after.** Let's Encrypt needs to reach port 80 directly to issue your SSL cert. Cloudflare's orange cloud (proxy mode) blocks this. Deploy first → get SSL cert → then switch to orange cloud.
>
> `ssh.yourdomain.com` must **always** stay grey cloud. Cloudflare proxy doesn't forward raw TCP, so SSH through it doesn't work.

---

## Step 6 — Install ddclient (Dynamic DNS)

Your home IP changes occasionally. ddclient keeps Cloudflare updated automatically.

```bash
sudo apt install -y ddclient
sudo nano /etc/ddclient.conf
```

Copy the contents of [`ddclient.conf.example`](../ddclient.conf.example) and fill in your domain and Cloudflare API token.

To get your Cloudflare API token:
- Cloudflare dashboard → My Profile → API Tokens → Create Token
- Use the "Edit zone DNS" template
- Scope it to your specific zone

```bash
# Enable and start ddclient
sudo systemctl enable ddclient
sudo systemctl start ddclient

# Test it works
sudo ddclient -force -verbose
# Should show: Setting yourdomain.com to <your-ip>
```

---

## Step 7 — Open Router Ports

In your router settings (usually at 192.168.1.1 or 192.168.x.1):
- Forward port **80** → your server's local IP
- Forward port **443** → your server's local IP

Also assign your server a **static local IP** via DHCP reservation so the port forwarding doesn't break when the server restarts.

---

## Step 8 — Create the Docker Network

This network connects all your containers. Create it once:

```bash
docker network create nginx-proxy
```

---

## Step 9 — Start the Proxy

The proxy is the only container that owns ports 80 and 443. Start it first, before any services.

```bash
cd /home/<your-user>
git clone https://github.com/tusher16/homelab.git
cd homelab/legacy/proxy

# Edit the DEFAULT_EMAIL in docker-compose.yml to your email
docker compose up -d

# Verify it's running
docker ps | grep nginx-proxy
```

---

## Step 10 — Deploy Your First Service

Use the template in `legacy/services/template/` as a starting point.

```bash
# Copy the template
cp -r legacy/services/template my-app
cd my-app

# Edit docker-compose.yml:
# - Set VIRTUAL_HOST to your subdomain
# - Set VIRTUAL_PORT to whatever port your app uses inside the container
# - Set LETSENCRYPT_HOST to match VIRTUAL_HOST
# - Set LETSENCRYPT_EMAIL to your email

# Create your .env file (never committed to git)
cp .env.example .env
nano .env

# Deploy
docker compose up --build -d

# Watch the SSL cert get issued (takes ~60 seconds)
docker logs -f nginx-proxy-le

# Once you see the cert issued, visit https://yoursubdomain.yourdomain.com
# Then switch the Cloudflare DNS record to orange cloud (proxied)
```

---

## Step 11 — Set Up CI/CD with GitHub Actions

So you never have to SSH in to deploy again.

**One-time manual step per project** (the repo must exist on the server before Actions can deploy to it):
```bash
ssh my-server
cd /home/<your-user>
git clone https://github.com/<you>/<your-repo>.git
cd <your-repo>
nano .env   # create the .env file here
```

**Add the deploy workflow** to your app repo at `.github/workflows/deploy.yml`.
Copy from [`legacy/.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) and fill in your values.

**Add GitHub Secrets** in your repo → Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `SERVER_IP` | `ssh.yourdomain.com` |
| `SSH_KEY` | Contents of `~/.ssh/id_ed25519` (your private key) |

Now every push to `main` auto-deploys.

---

## Common Mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Cloudflare orange cloud during first deploy | SSL cert fails silently | Grey cloud first, orange after cert |
| `external: false` on nginx-proxy network | App can't reach proxy, 503 errors | Always `external: true` |
| Exposing port 80/443 on app container | Conflicts with proxy | Remove port mappings on app containers |
| `SERVER_IP` set to local IP in GitHub Secrets | CI/CD times out | Use `ssh.yourdomain.com` |
| Forgetting one-time `git clone` before first push | "No such file or directory" in Actions | Clone manually first |
| Committing `.env` or `data/` | Secrets/data in public git | Add both to `.gitignore` |
| Giving Ollama a `VIRTUAL_HOST` | Proxy routes public traffic to your LLM | Internal containers: no `VIRTUAL_HOST` |

---

## Useful Commands

```bash
# See all running containers
docker ps

# Live logs for any container
docker logs -f <container-name>

# Check if SSL cert was issued
docker logs nginx-proxy-le | tail -30

# Rebuild and restart one service
docker compose up --build -d

# Check the nginx-proxy network exists
docker network ls | grep nginx-proxy

# Copy a data file to the server
scp -P <ssh-port> ./data/file.json user@server:~/project/data/

# Pull an Ollama model inside the container
docker exec -it ollama ollama pull qwen2.5:3b

# List loaded Ollama models
docker exec -it ollama ollama list
```

---

## Architecture Diagram

```
Your laptop / phone
        ↓
Cloudflare (DNS + proxy, hides your home IP)
        ↓
Your router (ports 80 + 443 forwarded to server)
        ↓
Your server — Ubuntu, Docker
        ↓
nginxproxy/nginx-proxy  ← reads VIRTUAL_HOST from each container
        ├── yoursite.com         → app container A
        ├── project.yourdomain.com → app container B
        └── n8n.yourdomain.com   → n8n container

nginxproxy/acme-companion ← reads LETSENCRYPT_HOST, gets SSL certs

ddclient ← runs on server, updates Cloudflare DNS when your IP changes

All containers on one Docker network: nginx-proxy
```

---

## What This Costs

| Item | Cost |
|---|---|
| Old PC (OptiPlex/EliteDesk/ThinkCentre) | €60–120 one-time |
| SSD (if not included) | €20–30 one-time |
| Domain name | ~€10/year |
| Cloudflare | Free |
| GitHub Actions | Free |
| Let's Encrypt SSL | Free |
| Power (15–30W at €0.40/kWh) | €4–9/month |

Total running cost: roughly **€5–10/month** depending on your electricity rate and how much the machine is under load.

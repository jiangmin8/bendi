# Deployment Options Matrix

## Railway (One-Click)

**Setup**: Click template button, set env vars, deploy.

**Pros**:
- Zero server management
- Automatic HTTPS
- Built-in CI/CD (git push to deploy)
- Managed PostgreSQL/Redis if needed

**Cons**:
- No GPU support (cloud LLMs only)
- Higher cost at scale
- Limited customization
- Vendor lock-in

**Cost**: Free tier (sleep after inactivity), Starter $5/mo, Pro $20/mo

**Best for**: Prototyping, small teams, no GPU needed

---

## Docker Compose (Self-Hosted)

**Setup**: `git clone`, configure `.env`, `docker compose up -d`.

**Pros**:
- Full control
- GPU passthrough for Ollama
- Data stays on your hardware
- Predictable costs

**Cons**:
- Manual server management
- Self-managed backups
- No auto-scaling

**Requirements**:
- Linux/macOS host (Windows via WSL2)
- Docker + Docker Compose
- For GPU: NVIDIA drivers + Container Toolkit
- 8GB+ RAM (16GB+ for local models)

**Cost**: VPS $5-40/mo, or home server electricity

---

## VPS Cloud (DigitalOcean, Linode, Hetzner)

**Popular options**:

| Provider | 2vCPU/4GB | 4vCPU/8GB | GPU Instance |
|----------|-----------|-----------|--------------|
| DigitalOcean | $24/mo | $48/mo | N/A |
| Linode | $24/mo | $48/mo | N/A |
| Hetzner | ~$5/mo | ~$10/mo | ~$100/mo |
| RunPod | - | - | $0.20/hr (A4000) |

---

## GPU Requirements for Local Models

| Model Size | VRAM Required | RAM Required | GPU Example |
|------------|--------------|--------------|-------------|
| 7B (Llama 3 8B) | 6-8 GB | 16 GB | RTX 3060 12GB |
| 13B | 10-12 GB | 32 GB | RTX 3090 24GB |
| 70B | 40-48 GB | 64 GB | A6000 48GB |

**CPU fallback**: Ollama can run on CPU but 10-100x slower.

---

## Reverse Proxy Comparison

| Proxy | Ease | Features | Odysseus Setup |
|-------|------|----------|---------------|
| **Nginx** | Medium | Battle-tested, fast | `nginx.conf` + SSL |
| **Traefik** | Easy | Auto-discovery, Let's Encrypt | Labels on containers |
| **Caddy** | Easiest | Automatic HTTPS, simple config | Single `Caddyfile` |

**Recommended for Odysseus**: Caddy for simplicity, Nginx for performance.

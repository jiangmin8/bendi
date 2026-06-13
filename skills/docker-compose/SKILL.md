---
name: docker-compose
description: Docker Compose deployment analysis for multi-container applications. Use when analyzing, auditing, or modifying docker-compose.yml configurations, container orchestration, service dependencies, networking, volumes, and environment variable management. Covers development and production deployment patterns for AI Agent platforms like Odysseus.
---

# Docker Compose Analysis

Analyze Docker Compose deployments for containerized AI Agent platforms.

## Core Concepts

Docker Compose orchestrates multi-container applications via declarative YAML:

| Concept | Purpose |
|---------|---------|
| **Services** | Container definitions (app, db, cache, etc.) |
| **Networks** | Internal communication between services |
| **Volumes** | Persistent data storage |
| **Dependencies** | Startup order via `depends_on` |
| **Environment** | Config injection via `.env` files |

## Odysseus Compose Architecture

Odysseus typically runs as 3-4 services:

1. **app** — Main FastAPI backend + React frontend (often combined)
2. **chromadb** — Vector database for persistent memory
3. **ollama** (optional) — Local LLM inference server
4. **nginx** (optional) — Reverse proxy for production

## Analysis Workflow

### When Analyzing a docker-compose.yml

1. List all services and their base images
2. Map service dependencies and startup order
3. Identify exposed ports and network topology
4. Audit volume mounts (host paths vs named volumes)
5. Check environment variable sources (hardcoded vs .env)
6. Verify security: no privileged mode, read-only rootfs where possible
7. Check restart policies and health checks
8. Assess resource limits (memory/CPU constraints)

### When Troubleshooting

Common issues and diagnostic commands:
- `docker compose logs -f [service]` — Follow logs
- `docker compose ps` — Check container status
- `docker exec -it <container> sh` — Shell into container
- `docker compose config` — Validate and render final YAML

## Key Files

- `references/docker-compose-yml.md` — Full docker-compose.yml structure and Odysseus-specific examples
- `references/deployment-patterns.md` — Dev vs production patterns

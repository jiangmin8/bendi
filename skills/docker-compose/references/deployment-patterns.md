# Deployment Patterns

## Development Mode

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    volumes:
      - .:/app  # live code reload
    environment:
      - DEBUG=true
      - HOT_RELOAD=true
```

- Live code mounting for rapid iteration
- Debug mode enabled, detailed stack traces
- Hot reload for both frontend and backend
- SQLite instead of external database

## Production Mode

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    restart: always
    read_only: true
    tmpfs:
      - /tmp
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
```

- Read-only rootfs with tmpfs for /tmp
- All capabilities dropped, minimal set added
- No new privileges escalation
- Multi-stage Docker build for smallest image
- External reverse proxy (nginx/traefik) handles TLS

## GPU-Enabled Mode (Local LLMs)

Required for Ollama with NVIDIA GPU:

```yaml
  ollama:
    image: ollama/ollama:latest
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

Requires: NVIDIA Container Toolkit installed on host.

## Railway vs Docker Comparison

| Aspect | Railway | Docker Compose |
|--------|---------|---------------|
| Setup | One-click template | Manual compose up |
| Scaling | Auto | Manual replica config |
| Persistence | Managed volumes | Self-managed volumes |
| GPU | Not available | Full GPU passthrough |
| SSL | Auto | Manual (nginx/certbot) |
| Cost | $5-20/mo | VPS $5-40/mo |
| Privacy | Railway manages infra | Full self-hosted |

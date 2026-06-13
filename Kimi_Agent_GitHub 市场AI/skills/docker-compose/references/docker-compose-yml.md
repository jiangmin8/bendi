# Docker Compose YAML Structure

## Table of Contents
1. [Schema Version](#schema-version)
2. [Service Definition](#service-definition)
3. [Networks](#networks)
4. [Volumes](#volumes)
5. [Odysseus Example](#odysseus-example)

## Schema Version

Use `version: "3.8"` or omit (Compose spec v2+ auto-detects).

## Service Definition

```yaml
services:
  app:
    image: odysseus:latest           # or build: .
    container_name: odysseus-app
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - AUTH_ENABLED=true
      - VECTOR_DB_URL=http://chromadb:8000
    env_file:
      - .env
    volumes:
      - odysseus-data:/app/data
      - ./custom-tools:/app/tools:ro
    depends_on:
      chromadb:
        condition: service_healthy
    networks:
      - odysseus-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 4G
```

## Networks

```yaml
networks:
  odysseus-net:
    driver: bridge
    internal: false  # set true to block external access
```

## Volumes

```yaml
volumes:
  odysseus-data:
    driver: local
  chroma-data:
    driver: local
```

## Odysseus Example

Complete 3-service setup (app + chromadb + ollama):

```yaml
services:
  app:
    build: .
    ports:
      - "${PORT:-3000}:3000"
    environment:
      - DATABASE_URL=sqlite:///data/odysseus.db
      - CHROMA_URL=http://chromadb:8000
      - OLLAMA_URL=http://ollama:11434
    volumes:
      - app-data:/app/data
    depends_on:
      - chromadb
      - ollama

  chromadb:
    image: chromadb/chroma:latest
    volumes:
      - chroma-data:/chroma/chroma
    environment:
      - ALLOW_RESET=true
      - ANONYMIZED_TELEMETRY=false

  ollama:
    image: ollama/ollama:latest
    volumes:
      - ollama-models:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

volumes:
  app-data:
  chroma-data:
  ollama-models:
```

## Security Checklist

- [ ] No `privileged: true` anywhere
- [ ] No host Docker socket mounted (`/var/run/docker.sock`)
- [ ] Sensitive vars in `.env`, not hardcoded
- [ ] Volumes use named volumes, not host path binds where possible
- [ ] `read_only: true` for root filesystem if app supports it
- [ ] `user: nonroot` instead of running as root
- [ ] `security_opt: [no-new-privileges:true]`
- [ ] Internal networks for service-to-service traffic
- [ ] Health checks on all services

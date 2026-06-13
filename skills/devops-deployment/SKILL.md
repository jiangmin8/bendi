---
name: devops-deployment
description: Deployment architecture analysis for self-hosted AI applications. Use when comparing deployment strategies (Railway, Docker Compose, bare metal, Kubernetes), analyzing infrastructure requirements, GPU passthrough configurations, reverse proxy setup, SSL/TLS termination, and environment-specific optimizations for AI Agent platforms like Odysseus. Covers cost analysis, scaling patterns, and production readiness checklists.
---

# DevOps Deployment Analysis

Analyze deployment architectures for self-hosted AI applications.

## Core Concepts

| Concept | Purpose |
|---------|---------|
| **Deployment Target** | Where containers/services run |
| **Reverse Proxy** | TLS termination, routing, load balancing |
| **GPU Passthrough** | NVIDIA Container Toolkit for local LLMs |
| **Persistent Storage** | Named volumes, bind mounts, cloud disks |
| **Health Checks** | Container liveness/readiness probes |
| **Secret Management** | API keys, passwords outside of images |

## Odysseus Deployment Options

| Method | Effort | Cost | GPU | Best For |
|--------|--------|------|-----|----------|
| **Railway** | Low | $5-20/mo | No | Quick start, cloud APIs only |
| **Docker Compose** | Medium | $5-40/mo | Yes | Full control, local models |
| **VPS + Docker** | Medium | $5-20/mo | No | Budget, cloud APIs |
| **Dedicated GPU Server** | High | $100+/mo | Yes | Production, many users |
| **Home Server** | High | Hardware | Yes | Privacy-first, tinkerers |

## Analysis Workflow

### When Analyzing Deployment Setup

1. Identify deployment target and orchestration method
2. Check service topology (which containers, how they communicate)
3. Verify persistent storage strategy
4. Analyze network configuration (ports, TLS, internal networks)
5. Check secret management (env files, vaults, hardcoded?)
6. Review monitoring and logging setup
7. Assess backup strategy for user data

### When Comparing Deployment Options

Evaluate on: setup complexity, monthly cost, maintenance burden, GPU support, scalability, privacy level, uptime requirements.

## Key Files

- `references/deployment-matrix.md` — Detailed comparison matrix
- `references/production-checklist.md` — Production readiness checklist

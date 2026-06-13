---
name: python-backend
description: Python backend analysis for AI Agent systems. Use when analyzing FastAPI/Flask Python backends, agent logic implementation, tool registry patterns, async request handling, API routing, authentication middleware, and LLM integration layers. Covers agent decision loops, tool execution pipelines, and state management for MCP-based agents like Odysseus.
---

# Python Backend Analysis

Analyze Python backends powering AI Agent systems.

## Core Concepts

| Component | Purpose |
|-----------|---------|
| **Agent Loop** | Core decision cycle: observe -> think -> act |
| **Tool Registry** | Dynamic tool registration and discovery |
| **Schema Validation** | Pydantic models for request/response validation |
| **Async Handlers** | FastAPI async endpoints for concurrent LLM calls |
| **Streaming** | SSE (Server-Sent Events) for real-time token streaming |
| **State Management** | Session-based or DB-backed conversation state |

## Odysseus Backend Architecture

```
main.py (FastAPI app)
  -> routers/
     -> chat.py       (chat completions, streaming)
     -> tools.py      (MCP tool registry, execution)
     -> agents.py     (agent orchestration, deep research)
     -> memory.py     (ChromaDB vector operations)
     -> auth.py       (JWT authentication)
  -> core/
     -> agent.py      (agent loop implementation)
     -> tool_runner.py (tool execution sandbox)
     -> model_router.py (multi-model dispatch)
  -> tools/           (individual tool implementations)
  -> models/          (Pydantic schemas)
```

## Analysis Workflow

### When Analyzing Agent Logic

1. Find the main agent loop (usually `core/agent.py`)
2. Trace the message flow: user input -> LLM -> tool call -> result -> LLM -> response
3. Identify tool discovery mechanism (static import vs dynamic registry)
4. Check conversation history management (token limits, summarization)
5. Audit tool execution sandbox (subprocess, timeout, resource limits)
6. Map error handling: LLM errors, tool failures, timeouts, rate limits

### When Analyzing API Routes

1. List all routers and their endpoints
2. Check authentication middleware on protected routes
3. Verify input validation with Pydantic models
4. Trace streaming implementation (SSE vs WebSocket)
5. Check CORS configuration for frontend access
6. Audit for injection vulnerabilities in dynamic inputs

## Key Files

- `references/agent-loop.md` — Agent decision loop implementation details
- `references/tool-execution.md` — Tool runner and sandbox architecture

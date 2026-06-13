---
name: llm-integration
description: Multi-LLM integration analysis for AI platforms. Use when analyzing systems that integrate multiple language models (OpenAI, Claude, Gemini, DeepSeek, Ollama), model routing logic, streaming response handling, API abstraction layers, and model comparison features. Covers unified API patterns, model capability detection, token management, and the Compare/blind-test functionality found in Odysseus.
---

# Multi-LLM Integration Analysis

Analyze systems integrating multiple language model providers.

## Core Concepts

| Component | Purpose |
|-----------|---------|
| **Model Router** | Dispatch requests to appropriate provider |
| **Adapter Pattern** | Normalize different API formats to unified interface |
| **Streaming** | Real-time token delivery via SSE/WebSocket |
| **Capability Detection** | Per-model feature flags (tools, vision, JSON mode) |
| **Compare Mode** | Parallel multi-model inference for quality testing |

## Odysseus Model Support

| Provider | API Style | Streaming | Tools | Local |
|----------|-----------|-----------|-------|-------|
| OpenAI | HTTP + SDK | Yes | Yes | No |
| Anthropic Claude | HTTP + SDK | Yes | Yes | No |
| Google Gemini | HTTP + SDK | Yes | Yes | No |
| DeepSeek | OpenAI-compatible | Yes | Yes | No |
| Ollama | Local HTTP | Yes | Partial | Yes |

## Analysis Workflow

### When Analyzing Model Integration

1. List all model providers and their API clients
2. Check the adapter/abstraction layer (unified vs per-provider)
3. Trace streaming implementation for each provider
4. Verify tool calling format conversion (each provider differs)
5. Check API key management (rotation, masking, per-user)
6. Audit error handling: rate limits, timeouts, model unavailable
7. Analyze Compare feature: parallel calls, result aggregation

### When Analyzing Compare Feature

1. Check parallel execution model (asyncio.gather vs queue)
2. Verify anonymization (model names hidden from user)
3. Check voting/ranking mechanism
4. Audit for result bias in presentation

## Key Files

- `references/model-adapters.md` — Provider-specific API differences
- `references/compare-implementation.md` — Compare feature architecture

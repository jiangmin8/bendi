---
name: react-frontend
description: React frontend analysis for AI Agent web interfaces. Use when analyzing React-based frontends for AI chat applications, including component architecture, state management, real-time streaming UI, multi-model selection interfaces, tool call visualization, and the Compare/blind-test feature. Covers SSE streaming, WebSocket connections, markdown rendering, and responsive design patterns found in Odysseus.
---

# React Frontend Analysis

Analyze React frontends for AI Agent web interfaces.

## Core Concepts

| Component | Purpose |
|-----------|---------|
| **Chat Interface** | Message list, input, streaming display |
| **Model Selector** | Dropdown to choose LLM provider/model |
| **Tool Call Viewer** | Expandable cards showing tool execution |
| **Compare Panel** | Side-by-side model response comparison |
| **Memory Inspector** | Search/browse persistent memory |
| **Settings** | Auth config, model API keys, preferences |

## Odysseus Frontend Architecture

```
src/
  components/
    Chat/              # Main chat interface
      MessageList.tsx
      MessageInput.tsx
      StreamingText.tsx  # SSE token rendering
    ModelSelector.tsx  # Provider/model dropdown
    ToolCallCard.tsx   # Tool execution display
    ComparePanel.tsx   # Side-by-side comparison
    MemoryPanel.tsx    # Vector memory browser
  hooks/
    useStreaming.ts    # SSE connection management
    useAuth.ts         # JWT auth state
    useTools.ts        # Tool registry client-side
  api/
    client.ts          # API client (fetch/axios)
    streaming.ts       # SSE event source handler
```

## Analysis Workflow

### When Analyzing Frontend Code

1. Map component hierarchy and state flow
2. Check streaming implementation (EventSource vs WebSocket)
3. Analyze how tool calls are rendered (inline vs sidebar)
4. Review model switching logic and state reset
5. Check responsive design (mobile PWA support)
6. Audit API key handling (client-side storage?)
7. Verify auth flow (login/logout/session refresh)

### When Analyzing Streaming

1. Check SSE connection lifecycle (open, message, error, close)
2. Verify token-by-token rendering performance
3. Check cancellation (AbortController on new message)
4. Handle reconnection on network failure

## Key Files

- `references/frontend-architecture.md` — Detailed component breakdown
- `references/streaming-implementation.md` — SSE and real-time patterns

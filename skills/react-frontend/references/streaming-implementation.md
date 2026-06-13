# Streaming Implementation

## SSE (Server-Sent Events)

### Connection Setup
```typescript
// hooks/useStreaming.ts
class StreamManager {
  private abortController: AbortController | null = null;
  
  async startStream(messages: Message[], model: string) {
    this.abortController = new AbortController();
    
    const response = await fetch('/api/chat/stream', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ messages, model }),
      signal: this.abortController.signal
    });
    
    const reader = response.body!.getReader();
    const decoder = new TextDecoder();
    
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      
      const chunk = decoder.decode(value);
      for (const line of chunk.split('\n')) {
        if (line.startsWith('data: ')) {
          const event = JSON.parse(line.slice(6));
          this.handleEvent(event);
        }
      }
    }
  }
  
  handleEvent(event: StreamEvent) {
    switch (event.type) {
      case 'token':
        appendToken(event.content); break;
      case 'tool_call':
        showToolCall(event.tool); break;
      case 'tool_result':
        updateToolResult(event.result); break;
      case 'error':
        showError(event.message); break;
      case 'done':
        finalizeMessage(); break;
    }
  }
  
  stop() {
    this.abortController?.abort();
  }
}
```

### Event Types
```typescript
type StreamEvent = 
  | { type: 'token'; content: string }
  | { type: 'tool_call'; tool: { name: string; arguments: any } }
  | { type: 'tool_result'; result: string; duration: number }
  | { type: 'error'; message: string }
  | { type: 'done' };
```

## Compare Streaming

Challenge: Multiple parallel SSE connections.

Solution: Single endpoint returning multiplexed events:
```typescript
// Event format for compare
type CompareEvent = {
  type: 'token';
  modelIndex: number;  // 0, 1, 2...
  content: string;
};
```

## Cancellation

Critical: Abort previous stream on new user message:
```typescript
useEffect(() => {
  // Cancel any active stream when messages change (new user input)
  return () => streamManager.stop();
}, [messages.length]);
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Network drop | Auto-reconnect with exponential backoff |
| 401 Unauthorized | Redirect to login |
| 429 Rate limit | Show retry countdown |
| 500 Server error | Show error, preserve partial response |
| Parse error | Show raw text, log error |

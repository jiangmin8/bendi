# MCP Protocol Specification

## Table of Contents
1. [Transport Layer](#transport-layer)
2. [Message Format](#message-format)
3. [Lifecycle Methods](#lifecycle-methods)
4. [Tool Methods](#tool-methods)
5. [Resource Methods](#resource-methods)
6. [Prompt Methods](#prompt-methods)
7. [Error Handling](#error-handling)

## Transport Layer

MCP supports multiple transports:
- **stdio**: stdin/stdout for local processes
- **HTTP/SSE**: Server-Sent Events for remote servers
- **WebSocket**: Bidirectional persistent connection

## Message Format

All messages use JSON-RPC 2.0:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list",
  "params": {}
}
```

## Lifecycle Methods

### initialize
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "tools": {"listChanged": true},
      "resources": {"subscribe": true},
      "prompts": {"listChanged": true}
    },
    "clientInfo": {"name": "odysseus-client", "version": "1.0.0"}
  }
}
```

### tools/list
Returns array of available tools:
```json
{
  "tools": [
    {
      "name": "shell_exec",
      "description": "Execute shell command (admin only)",
      "inputSchema": {
        "type": "object",
        "properties": {
          "command": {"type": "string"},
          "timeout": {"type": "number", "default": 30}
        },
        "required": ["command"]
      }
    }
  ]
}
```

### tools/call
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "shell_exec",
    "arguments": {"command": "ls -la", "timeout": 10}
  }
}
```

### resources/list
Returns readable resources with URIs and metadata.

### prompts/list
Returns available prompt templates with arguments.

## Error Handling

Standard JSON-RPC errors with MCP-specific codes:
- `-32600`: Invalid Request
- `-32601`: Method not found
- `-32602`: Invalid params (schema validation failed)
- `1-99`: MCP implementation-specific errors

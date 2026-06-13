---
name: mcp-protocol
description: Model Context Protocol (MCP) analysis for AI Agent systems. Use when analyzing, auditing, or extending MCP-based agent implementations including tool registration, permission models, multi-agent orchestration, and tool call lifecycle. Covers server-client protocol flow, tool schemas, resource management, and prompt handling. Essential for understanding Odysseus AI Agent architecture.
---

# MCP Protocol Analysis

Analyze MCP (Model Context Protocol) based AI Agent systems.

## Core Concepts

MCP is a JSON-RPC 2.0 protocol for model-context exchange between AI hosts and tool servers. Three primitives:

| Primitive | Purpose |
|-----------|---------|
| **Tools** | Executable functions the model can call |
| **Resources** | Read-only data the model can reference |
| **Prompts** | Pre-defined templates for common tasks |

## Protocol Flow

1. **Handshake**: Client sends `initialize` with protocol version and capabilities
2. **Tool Discovery**: Client calls `tools/list` to get available tools with JSON schemas
3. **Tool Execution**: Model generates `tools/call` with validated arguments
4. **Response Handling**: Server returns `content` array with text/image/embedded_resource
5. **Capability Negotiation**: Both sides declare supported features at init

## Odysseus MCP Architecture

Odysseus uses MCP as its Agent backbone:

- **Server-side**: Python FastAPI handlers exposing tools via JSON-RPC
- **Client-side**: LLM generates tool calls; executor validates and routes
- **Tool Registry**: Dynamic registration with JSON Schema validation per tool
- **Permission Model**: Role-based access (admin/user) controls tool availability
- **Built-in Tools**: shell_exec, file_read, file_write, email_send, web_search, calendar_query

## Analysis Workflow

### When Analyzing MCP Agent Code

1. Identify the MCP server implementation (FastAPI/Flask/Express)
2. List all registered tools and their JSON schemas
3. Map the permission/authorization layer
4. Trace the tool call lifecycle (request -> validation -> execution -> response)
5. Check for tool sandboxing and resource isolation
6. Audit for prompt injection vulnerabilities in tool descriptions

### When Extending MCP Tools

1. Define JSON Schema for new tool arguments
2. Implement handler function with input validation
3. Register in tool registry with proper metadata
4. Set appropriate permission level (admin-only vs public)
5. Test with `tools/list` discovery and `tools/call` execution

## Key Files in Odysseus

- `references/mcp-spec.md` — Full MCP protocol specification
- `references/odysseus-mcp-tools.md` — Complete tool registry with schemas and permission levels
- `references/multi-agent-orchestration.md` — Multi-agent patterns using MCP

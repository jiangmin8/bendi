# Multi-Agent Orchestration Patterns

## Single MCP Server Pattern

One server hosts all tools. Agent uses `tools/list` discovery to decide which tools to call.

- **Pros**: Simple, unified permission model
- **Cons**: No agent specialization, single point of failure
- **Odysseus Default**: This pattern

## Multi-Server Federation

Each agent connects to multiple MCP servers:
- `system-server`: shell, file, network tools (high privilege)
- `app-server`: app-specific APIs (medium privilege)
- `data-server`: database queries, analytics (read-only)

Agent routes calls to appropriate server based on tool name prefix.

## Agent-to-Agent Delegation

One agent (orchestrator) calls another (worker) via MCP:
1. Orchestrator receives user task
2. Breaks into subtasks
3. Calls worker agent's MCP endpoint with subtask
4. Worker executes with its own tool set
5. Results flow back up the chain

## Odysseus Deep Research Implementation

Multi-step orchestration:
1. User query -> Planner Agent decomposes into search steps
2. Each step triggers `web_search` tool
3. Results stored in `memory_store` with embeddings
4. Aggregator Agent reads all memories via `memory_search`
5. Synthesizes final report with citations

## Race Condition Concerns

When multiple agents share tools:
- File write collisions on shared paths
- Database concurrent access without transactions
- Shell command interference between agents

Mitigation: Use tool-level locking or sandbox per agent session.

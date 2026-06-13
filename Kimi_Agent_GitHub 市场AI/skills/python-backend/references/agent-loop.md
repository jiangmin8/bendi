# Agent Decision Loop

## Table of Contents
1. [Basic Loop](#basic-loop)
2. [ReAct Pattern](#react-pattern)
3. [Odysseus Implementation](#odysseus-implementation)
4. [Streaming Architecture](#streaming-architecture)

## Basic Loop

```python
async def agent_loop(user_input: str, session_id: str) -> str:
    # 1. Load context
    history = await get_chat_history(session_id)
    tools = tool_registry.list_available_tools(user_role)
    
    # 2. Build prompt with tool descriptions
    system_prompt = build_system_prompt(tools)
    messages = [system_prompt] + history + [{"role": "user", "content": user_input}]
    
    # 3. Call LLM
    response = await llm_client.chat_completion(messages, tools=tools)
    
    # 4. Check for tool calls
    if response.tool_calls:
        for call in response.tool_calls:
            # Validate arguments against schema
            validated = validate_arguments(call.name, call.arguments)
            # Execute with sandbox
            result = await tool_runner.execute(call.name, validated)
            # Add to messages for next LLM call
            messages.append({"role": "tool", "content": result})
        
        # Recursive call with tool results
        return await agent_loop(user_input, session_id)  # or iterate
    
    # 5. Return final text response
    return response.content
```

## ReAct Pattern

Reasoning + Acting loop:
1. **Thought**: LLM reasons about what to do
2. **Action**: LLM emits tool call
3. **Observation**: Tool result fed back
4. **Repeat** until task complete

Odysseus uses a variant with streaming thoughts visible to user.

## Odysseus Implementation

Key files and patterns:

```python
# core/agent.py
class Agent:
    def __init__(self, model_router, tool_registry, memory_store):
        self.model_router = model_router
        self.tools = tool_registry
        self.memory = memory_store
    
    async def run(self, query: str, model: str, tools: list[str] = None):
        # Check memory first
        relevant_memories = await self.memory.search(query, top_k=3)
        
        # Build augmented prompt
        context = self._build_context(query, relevant_memories)
        
        # Stream response with tool interception
        async for chunk in self.model_router.stream(context, model, tools):
            if chunk.tool_call:
                yield await self._handle_tool_call(chunk.tool_call)
            else:
                yield chunk.content
```

## Streaming Architecture

SSE (Server-Sent Events) flow:
1. Client opens SSE connection to `/api/chat/stream`
2. Server sends `event: message` chunks as LLM generates tokens
3. Tool calls sent as `event: tool_call` with JSON payload
4. Tool results sent as `event: tool_result`
5. Final `event: done` closes stream

Frontend reconstructs full response from streamed chunks.

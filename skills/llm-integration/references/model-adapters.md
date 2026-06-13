# Model Provider Adapters

## Table of Contents
1. [OpenAI](#openai)
2. [Anthropic Claude](#anthropic)
3. [Google Gemini](#gemini)
4. [DeepSeek](#deepseek)
5. [Ollama](#ollama)
6. [Unified Interface](#unified-interface)

## OpenAI

```python
from openai import AsyncOpenAI

client = AsyncOpenAI(api_key=api_key, base_url=base_url or "https://api.openai.com/v1")

response = await client.chat.completions.create(
    model="gpt-4",
    messages=messages,
    tools=tools,  # OpenAI tool format
    stream=True
)
```

**Tool format**:
```json
{"type": "function", "function": {"name": "shell_exec", "parameters": {...}}}
```

**Streaming**: `async for chunk in response` yields delta tokens.

## Anthropic

```python
from anthropic import AsyncAnthropic

client = AsyncAnthropic(api_key=api_key)

response = await client.messages.create(
    model="claude-3-sonnet",
    messages=messages,
    tools=tools,  # Claude tool format
    stream=True,
    max_tokens=4096  # REQUIRED for Claude
)
```

**Tool format**:
```json
{"name": "shell_exec", "description": "...", "input_schema": {...}}
```

**Key difference**: Claude requires `max_tokens`, uses `input_schema` not `parameters`.

## Google Gemini

```python
import google.generativeai as genai

genai.configure(api_key=api_key)
model = genai.GenerativeModel('gemini-pro')

response = await model.generate_content_async(
    contents,
    tools=tools,
    stream=True
)
```

**Tool format**: FunctionDeclaration protobuf-style.

## DeepSeek

OpenAI-compatible API. Use OpenAI client with base URL:
```python
client = AsyncOpenAI(api_key=api_key, base_url="https://api.deepseek.com")
```

## Ollama

Local HTTP API, OpenAI-compatible format:
```python
client = AsyncOpenAI(api_key="ollama", base_url="http://localhost:11434/v1")
```

**Limitations**: Tool support depends on model (Llama 3 supports, Mistral varies).

## Unified Interface

Odysseus likely implements an abstraction:

```python
class ModelRouter:
    async def stream(self, messages, model_id, tools=None):
        provider = self._get_provider(model_id)  # "openai", "claude", etc.
        adapter = self.adapters[provider]
        normalized_tools = adapter.convert_tools(tools)
        
        async for chunk in adapter.stream(messages, normalized_tools):
            yield adapter.normalize_chunk(chunk)
```

**Critical for Compare**: All providers must yield chunks in identical format.

# Tool Execution & Sandbox

## Tool Registry Pattern

```python
# tools/registry.py
class ToolRegistry:
    def __init__(self):
        self._tools: dict[str, Tool] = {}
    
    def register(self, tool: Tool):
        self._tools[tool.name] = tool
    
    def list_for_user(self, role: str) -> list[Tool]:
        return [t for t in self._tools.values() if t.required_role <= role]
    
    def get_schema(self, name: str) -> dict:
        return self._tools[name].input_schema
```

## Sandboxed Execution

### Subprocess Sandbox
```python
async def execute_shell(command: str, timeout: int = 30, cwd: str = None):
    proc = await asyncio.create_subprocess_shell(
        command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=cwd,
        env={"PATH": "/usr/local/bin:/usr/bin"}  # sanitized env
    )
    try:
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=timeout
        )
        return {"stdout": stdout.decode(), "stderr": stderr.decode()}
    except asyncio.TimeoutError:
        proc.kill()
        return {"error": f"Command timed out after {timeout}s"}
```

### File Access Sandbox
```python
def read_file(path: str, allowed_prefixes: list[str] = None):
    # Resolve to absolute path
    abs_path = os.path.realpath(path)
    
    # Check allowed directories
    if allowed_prefixes:
        if not any(abs_path.startswith(p) for p in allowed_prefixes):
            raise PermissionError(f"Access denied: {path}")
    
    # Prevent path traversal
    if ".." in path:
        raise ValueError("Path traversal not allowed")
    
    with open(abs_path, "r") as f:
        return f.read()
```

## Tool Registration (Decorator Pattern)

```python
# tools/shell.py
from functools import wraps

def tool(name: str, description: str, schema: dict, required_role: str = "user"):
    def decorator(func):
        registry.register(Tool(
            name=name,
            description=description,
            input_schema=schema,
            handler=func,
            required_role=required_role
        ))
        @wraps(func)
        async def wrapper(*args, **kwargs):
            return await func(*args, **kwargs)
        return wrapper
    return decorator

@tool(
    name="shell_exec",
    description="Execute shell command (admin only)",
    schema={"type": "object", "properties": {"command": {"type": "string"}}},
    required_role="admin"
)
async def shell_exec(command: str):
    return await execute_shell(command)
```

## Error Handling

| Error Type | Handling Strategy |
|------------|-------------------|
| Schema Validation | Return 400 with validation error details |
| Tool Execution Fail | Return error in tool_result, let LLM recover |
| Timeout | Kill subprocess, return timeout message |
| Permission Denied | Return 403, do not expose internal paths |
| LLM Rate Limit | Backoff retry with exponential delay |
| Token Limit | Summarize history, drop oldest messages |

- 与 `huggingface-cli` 共享缓存

---

## 6. 阶段四：应用接入层

### 6.1 Python 客户端示例

```python
#!/usr/bin/env python3
"""
llama-server 客户端示例
无需 transformers/torch，纯 HTTP 调用
"""

import os
import json
from urllib.request import Request, urlopen
from urllib.error import HTTPError

class LlamaClient:
    """OpenAI 兼容的 llama-server 客户端"""
    
    def __init__(self, base_url: str = "http://localhost:8080", api_key: str = None):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key or os.environ.get("LLAMA_API_KEY")
    
    def _request(self, endpoint: str, data: dict) -> dict:
        url = f"{self.base_url}{endpoint}"
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        
        req = Request(
            url,
            data=json.dumps(data).encode(),
            headers=headers,
            method="POST"
        )
        
        try:
            with urlopen(req) as resp:
                return json.loads(resp.read())
        except HTTPError as e:
            error_body = e.read().decode()
            raise RuntimeError(f"API 错误 {e.code}: {error_body}")
    
    def chat(self, messages: list[dict], model: str = None, stream: bool = False, **kwargs) -> str:
        """对话补全"""
        data = {
            "model": model or "default",
            "messages": messages,
            "stream": stream,
            **kwargs
        }
        
        if stream:
            return self._stream_chat(data)
        
        resp = self._request("/v1/chat/completions", data)
        return resp["choices"][0]["message"]["content"]
    
    def _stream_chat(self, data: dict):
        """流式对话（SSE）"""
        import urllib.request
        
        url = f"{self.base_url}/v1/chat/completions"
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        
        req = urllib.request.Request(
            url,
            data=json.dumps(data).encode(),
            headers=headers,
            method="POST"
        )
        
        with urllib.request.urlopen(req) as resp:
            for line in resp:
                line = line.decode().strip()
                if line.startswith("data: "):
                    chunk = line[6:]
                    if chunk == "[DONE]":
                        break
                    try:
                        data = json.loads(chunk)
                        delta = data["choices"][0]["delta"].get("content", "")
                        if delta:
                            yield delta
                    except (json.JSONDecodeError, KeyError):
                        pass
    
    def embed(self, texts: list[str], model: str = None) -> list[list[float]]:
        """文本嵌入"""
        data = {
            "model": model or "default",
            "input": texts
        }
        resp = self._request("/v1/embeddings", data)
        return [item["embedding"] for item in resp["data"]]
    
    def rerank(self, query: str, documents: list[str], model: str = None) -> list[dict]:
        """文档重排序"""
        data = {
            "model": model or "default",
            "query": query,
            "documents": documents
        }
        return self._request("/v1/rerank", data)


# ===== 使用示例 =====
if __name__ == "__main__":
    client = LlamaClient("http://localhost:8080")
    
    # 1. 对话
    response = client.chat([
        {"role": "system", "content": "你是一个有帮助的助手。"},
        {"role": "user", "content": "解释量化在 LLM 中的作用。"}
    ], temperature=0.7)
    print("对话响应:", response)
    
    # 2. 流式对话
    print("\n流式响应:")
    for chunk in client.chat([
        {"role": "user", "content": "写一首短诗。"}
    ], stream=True):
        print(chunk, end="", flush=True)
    
    # 3. 嵌入
    embeddings = client.embed(["Hello world", "Quantization is important"])
    print(f"\n嵌入维度: {len(embeddings[0])}")
    
    # 4. 重排序
    docs = ["Python is great", "Java is popular", "Rust is fast"]
    ranked = client.rerank("Which language is best for systems programming?", docs)
    print("重排序结果:", ranked)
```

### 6.2 curl 命令参考

```bash
# === 对话补全 ===
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.1-8b",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is GGUF format?"}
    ],
    "temperature": 0.7,
    "max_tokens": 512
  }' | jq '.choices[0].message.content'

# === 流式对话 (SSE) ===
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.1-8b",
    "messages": [{"role": "user", "content": "Count 1 to 10"}],
    "stream": true,
    "max_tokens": 100
  }'

# === 文本嵌入 ===
curl -s http://localhost:8080/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "bge-embed",
    "input": ["Hello world", "Machine learning"]
  }' | jq '.data[].embedding[:5]'

# === 文档重排序 ===
curl -s http://localhost:8080/v1/rerank \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-reranker",
    "query": "What is the capital of France?",
    "documents": ["Paris is the capital of France.", "Berlin is in Germany.", "Madrid is in Spain."]
  }'

# === 列出模型 ===
curl -s http://localhost:8080/v1/models | jq '.data[].id'

# === 健康检查 ===
curl -s http://localhost:8080/health | jq .

# === Prometheus Metrics ===
curl -s http://localhost:8080/metrics
```

### 6.3 LangChain / OpenAI SDK 兼容

```python
# 使用 OpenAI SDK（零改动切换）
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8080/v1",  # 指向 llama-server
    api_key="no-key-required"  # 或设置实际 API key
)

response = client.chat.completions.create(
    model="llama-3.1-8b",  # models.ini 中定义的模型名
    messages=[
        {"role": "user", "content": "Hello!"}
    ],
    stream=True
)

for chunk in response:
    print(chunk.choices[0].delta.content or "", end="")
```

```python
# LangChain 集成
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    openai_api_base="http://localhost:8080/v1",
    openai_api_key="no-key",
    model_name="llama-3.1-8b",
    temperature=0.7
)

result = llm.invoke("Explain quantum computing in simple terms.")
print(result.content)

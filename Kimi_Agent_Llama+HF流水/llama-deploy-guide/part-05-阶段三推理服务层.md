```

---

## 5. 阶段三：推理服务层

### 5.1 llama-server 核心配置

#### 单模型部署

```bash
#!/bin/bash
# deploy-single-model.sh

MODEL_PATH="${MODEL_PATH:-./models/quantized/llama-3.1-8b-Q4_K_M.gguf}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
GPU_LAYERS="${GPU_LAYERS:-all}"      # all, 0, 或具体层数
CTX_SIZE="${CTX_SIZE:-32768}"
BATCH_SIZE="${BATCH_SIZE:-2048}"
PARALLEL="${PARALLEL:-4}"

# HTTPS/TLS（可选）
SSL_CERT="${SSL_CERT:-}"
SSL_KEY="${SSL_KEY:-}"

echo "========================================"
echo "启动 llama-server"
echo "========================================"
echo "模型: $MODEL_PATH"
echo "监听: $HOST:$PORT"
echo "GPU 层: $GPU_LAYERS"
echo "上下文: $CTX_SIZE"
echo "并行: $PARALLEL"

llama-server \
    --model "$MODEL_PATH" \
    --host "$HOST" \
    --port "$PORT" \
    --n-gpu-layers "$GPU_LAYERS" \
    --ctx-size "$CTX_SIZE" \
    --batch-size "$BATCH_SIZE" \
    --parallel "$PARALLEL" \
    --threads-http 4 \
    --timeout 300 \
    --metrics \
    ${SSL_CERT:+--ssl-cert-file "$SSL_CERT"} \
    ${SSL_KEY:+--ssl-key-file "$SSL_KEY"} \
    --chat-template llama3  # 根据模型调整
```

#### 关键参数说明

| 参数 | 说明 | 推荐值 |
|------|------|--------|
| `--model` | GGUF 模型路径 | 必填 |
| `--host` | 监听地址 | `0.0.0.0` |
| `--port` | 监听端口 | `8080` |
| `--n-gpu-layers` | GPU 卸载层数 | `all` (全 GPU) |
| `--ctx-size` | 最大上下文长度 | `32768` 或 `65536` |
| `--batch-size` | 最大批处理大小 | `2048` |
| `--parallel` | 并发请求数 | `4` |
| `--threads-http` | HTTP 工作线程 | CPU 核心数 |
| `--timeout` | 请求超时(秒) | `300` |
| `--metrics` | 启用 Prometheus metrics | 生产必开 |
| `--chat-template` | 对话模板 | 根据模型指定 |

#### 支持的 Chat Templates

| 模型系列 | `--chat-template` |
|---------|------------------|
| Llama 3.x | `llama3` |
| Qwen 2.x/3 | `qwen2` |
| Mistral | `mistral` |
| Gemma 3 | `gemma3` |
| DeepSeek | `deepseek2` |
| Phi-4 | `phi4` |
| Command R | `command-r` |

### 5.2 多模型路由（models.ini）

单实例服务多个模型，按需加载到 VRAM：

```ini
; models.ini - 多模型配置文件

; 全局默认设置
[*]
n-gpu-layers = all
ctx-size = 32768
batch-size = 2048
parallel = 4

; Llama 3.1 8B - 聊天模型
[llama-3.1-8b]
model = /models/llama-3.1-8b-instruct-Q4_K_M.gguf
chat-template = llama3

; Qwen3 30B A3B - 聊天模型（更大，单独配置上下文）
[qwen3-30b]
model = /models/Qwen3-30B-A3B-Instruct-Q4_K_M.gguf
chat-template = qwen3
ctx-size = 65536

; Qwen3 Reranker - 重排序模型
[qwen3-reranker]
model = /models/Qwen3-Reranker-4B-f16.gguf
pooling = rank

; BGE Embedding - 嵌入模型
[bge-embed]
model = /models/bge-m3-Q4_K_M.gguf
embedding = true
pooling = cls

; 路由器配置
[router]
models-max = 1  ; VRAM 中同时保留的模型数，超出则自动换出
```

```bash
# 使用 models.ini 启动
llama-server --models ./models.ini --port 8080

# API 调用时通过 model 参数选择模型
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.1-8b",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### 5.3 API 端点

llama-server 提供完整的 OpenAI 兼容 API：

| 端点 | 方法 | 说明 |
|------|------|------|
| `/v1/chat/completions` | POST | 对话补全（支持 streaming） |
| `/v1/completions` | POST | 文本补全（legacy） |
| `/v1/embeddings` | POST | 文本嵌入向量 |
| `/v1/rerank` | POST | 文档重排序 |
| `/v1/models` | GET | 列出可用模型 |
| `/health` | GET | 健康检查 |
| `/metrics` | GET | Prometheus metrics |
| `/props` | GET | 服务配置属性 |

### 5.4 从 Hugging Face 直接加载（免下载）

llama-server 支持直接从 Hugging Face Hub 下载并加载 GGUF：

```bash
# 格式: -hf <repo>:<quant>
llama-server \
    -hf unsloth/llama-3.1-8b-instruct-GGUF:Q4_K_M \
    --port 8080 \
    --n-gpu-layers 999

# 或完整 repo
llama-server \
    -hf bartowski/Llama-3.1-8B-Instruct-GGUF \
    --port 8080
```

**优势**：
- 首次运行自动下载并缓存（标准 HF cache 目录）
- 后续直接从缓存加载

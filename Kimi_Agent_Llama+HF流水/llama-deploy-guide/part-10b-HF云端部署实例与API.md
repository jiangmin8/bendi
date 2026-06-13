
HF Inference Endpoints 支持**自定义容器镜像**，这让我们可以将 llama-server 部署到 HF 的托管基础设施上。

#### 步骤 1: 准备 Dockerfile

```dockerfile
# Dockerfile.hf - 用于 Hugging Face Inference Endpoints
FROM nvidia/cuda:12.4-runtime-ubuntu22.04

WORKDIR /app

# 安装运行时依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4 libgomp1 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# 复制 llama-server 二进制（从之前的构建产物）
COPY --from=llama-server:latest /usr/local/bin/llama-server /usr/local/bin/

# 复制 GGUF 模型（或使用 -hf 参数从 Hub 加载）
COPY model.gguf /app/model.gguf

# HF Inference Endpoints 要求监听 80 端口
EXPOSE 80

# 启动 llama-server（HF 自动注入 HTTPS + 认证）
CMD ["llama-server", \
     "--model", "/app/model.gguf", \
     "--host", "0.0.0.0", \
     "--port", "80", \
     "--n-gpu-layers", "all", \
     "--ctx-size", "32768", \
     "--parallel", "4", \
     "--metrics"]
```

#### 步骤 2: 创建 HF Endpoint

```python
#!/usr/bin/env python3
"""通过 Hugging Face API 创建 Inference Endpoint"""

import os
from huggingface_hub import create_inference_endpoint

# 使用 HF Token 认证
endpoint = create_inference_endpoint(
    name="llama-8b-llamacpp",           # Endpoint 名称
    repository="your-org/your-gguf-model",  # 模型仓库（含 Dockerfile）
    framework="custom",                  # 自定义容器
    accelerator="gpu",                   # GPU 加速
    instance_type="nvidia-t4-medium",    # 实例类型
    instance_size="medium",              # 实例规格
    region="us-east-1",                  # 部署区域
    vendor="aws",                        # 云厂商 (aws / gcp / azure)
    namespace="your-username",           # 命名空间
    type="public",                       # 公开/私有
    token=os.environ["HF_TOKEN"]
)

print(f"Endpoint 创建中: {endpoint.name}")
print(f"状态: {endpoint.status}")
```

#### 支持的实例类型

| 实例类型 | GPU | VRAM | 适用模型 |
|---------|-----|------|---------|
| `nvidia-t4-medium` | T4 | 16 GB | 7B Q4_K_M |
| `nvidia-t4-large` | T4 | 16 GB | 7B Q8_0 |
| `nvidia-l4-medium` | L4 | 24 GB | 13B Q4_K_M |
| `nvidia-l4x2-medium` | 2x L4 | 48 GB | 70B Q4_K_M |
| `nvidia-a10g-medium` | A10G | 24 GB | 13B Q8_0 |
| `nvidia-a100-large` | A100 | 80 GB | 70B Q8_0 |

### 9.4 Custom Handler 模式（自定义预处理/后处理）

对于需要**自定义业务逻辑**的场景（如数据预处理、后处理、多模型串联），HF 提供了 `handler.py` 机制。

#### handler.py 结构

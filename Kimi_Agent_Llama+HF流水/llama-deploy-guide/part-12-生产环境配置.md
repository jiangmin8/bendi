| 多区域部署 | HF Endpoints (多 region) + 自托管 | 混合覆盖 |

---

## 10. 生产环境配置

### 10.1 高性能调优参数

```bash
# === NVIDIA GPU 优化 ===
export CUDA_VISIBLE_DEVICES=0              # 指定 GPU
export GGML_CUDA_FORCE_MMQ=1               # 强制使用 MMQ kernel（加速）
export GGML_CUDA_NO_PINNED=1               # 禁用 pinned memory（大模型需要）
export GGML_CUDA_ENABLE_UNIFIED_MEMORY=1   # 启用统一内存（超出 VRAM 时）

# === CPU 优化 ===
export OMP_NUM_THREADS=16                  # OpenMP 线程数
export GGML_BLAS_VENDOR=OpenBLAS           # BLAS 库选择

# === llama-server 启动参数优化 ===
llama-server \
    --model model.gguf \
    --n-gpu-layers 999 \                   # 全部 GPU 卸载
    --ctx-size 65536 \                     # 大上下文（需更多 VRAM）
    --batch-size 4096 \                    # 大 batch（高吞吐）
    --ubatch-size 512 \                    # micro-batch（低延迟）
    --parallel 8 \                         # 8 并发槽位
    --threads-http 8 \                     # 8 HTTP 工作线程
    --threads-batch 8 \                    # batch 处理线程
    --flash-attn \                         # 启用 Flash Attention
    --mlock \                              # 锁定内存防止 swap
    --no-mmap \                            # 禁用内存映射（更稳定）
    --metrics \                            # 启用监控
    --api-key "${API_KEY}"                  # API 认证
```

### 10.2 安全加固

```bash
# === API 密钥认证 ===
llama-server --api-key "sk-your-secret-key-here"

# 请求时携带
curl http://localhost:8080/v1/chat/completions \
  -H "Authorization: Bearer sk-your-secret-key-here" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hi"}]}'

# === HTTPS/TLS ===
# 生成自签名证书（测试用）
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes

# 启动时启用 TLS
llama-server \
    --ssl-cert-file cert.pem \
    --ssl-key-file key.pem \
    --port 8443
```

### 10.3 多 GPU 部署

```bash
# 方式 1: 单实例多 GPU (tensor 并行 - 需要 llama.cpp 支持)
export CUDA_VISIBLE_DEVICES=0,1
llama-server \
    --model large-model.gguf \
    --tensor-split 0.5,0.5        # GPU 0 和 GPU 1 各 50%

# 方式 2: 多实例部署（每个 GPU 一个服务）
# GPU 0 - 聊天模型
llama-server --model chat.gguf --port 8080 --n-gpu-layers 999 \
    --main-gpu 0 --tensor-split 1.0,0.0

# GPU 1 - 嵌入模型
llama-server --model embed.gguf --port 8081 --n-gpu-layers 999 \
    --main-gpu 1 --tensor-split 0.0,1.0

# Nginx 负载均衡
```

### 10.4 模型大小与 VRAM 对照表

| 模型 | 量化 | 模型大小 | 推荐 VRAM | 推荐 GPU |
|------|------|---------|----------|---------|
| Llama 3.1 8B | Q4_K_M | ~4.7 GB | 8 GB | RTX 3070 |
| Llama 3.1 8B | Q8_0 | ~8.5 GB | 12 GB | RTX 4070 |
| Llama 3.3 70B | Q4_K_M | ~40 GB | 48 GB | RTX 4090 (24GB) + 系统内存 |
| Llama 3.3 70B | Q4_K_M | ~40 GB | 48 GB | A6000 48GB |
| Qwen3 30B A3B | Q4_K_M | ~18 GB | 24 GB | RTX 4090 |
| DeepSeek R1 32B | Q4_K_M | ~20 GB | 24 GB | RTX 4090 |

# Llama.cpp + Hugging Face 完整部署流水线方案

> **版本**: v1.0  
> **日期**: 2026-06-10  
> **目标**: 构建一条从 Hugging Face 模型获取 → GGUF 转换/量化 → llama.cpp 编译 → llama-server 服务部署 → 应用接入的完整自动化流水线  
> **核心原则**: 纯 C++ 推理引擎，零 Python 运行时依赖，多硬件后端支持，OpenAI 兼容 API

---

## 目录

1. [架构总览](#1-架构总览)
2. [流水线全景图](#2-流水线全景图)
3. [阶段一：模型管理层](#3-阶段一模型管理层)
4. [阶段二：编译构建层](#4-阶段二编译构建层)
5. [阶段三：推理服务层](#5-阶段三推理服务层)
6. [阶段四：应用接入层](#6-阶段四应用接入层)
7. [阶段五：监控与运维层](#7-阶段五监控与运维层)
8. [CI/CD 自动化流水线](#8-cicd-自动化流水线)
9. [Hugging Face Inference Endpoints 云端部署](#9-hugging-face-inference-endpoints-云端部署)
10. [生产环境配置](#10-生产环境配置)
11. [附录](#11-附录)

---

## 1. 架构总览

### 1.1 五层架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    ⑤ 应用接入层                              │
│  (Web UI / CLI / OpenAI 兼容客户端 / LangChain / etc.)       │
├─────────────────────────────────────────────────────────────┤
│                    ④ 推理服务层                              │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐    │
│  │ llama-server │  │ 模型热加载    │  │ 多模型路由       │    │
│  │  (C++ HTTP)  │  │ (GGUF 动态)  │  │ (models.ini)    │    │
│  └──────┬──────┘  └──────────────┘  └─────────────────┘    │
├─────────┼───────────────────────────────────────────────────┤
│         │          ③ 编译构建层                              │
│         │  ┌──────────────────────────────────────────┐     │
│         └─→│  llama.cpp 编译产物                       │     │
│            │  • llama-server (主服务)                  │     │
│            │  • llama-cli    (调试/压测)               │     │
│            │  • llama-quantize (量化工具)               │     │
│            │  • llama-bench    (基准测试)               │     │
│            └──────────────────────────────────────────┘     │
├─────────────────────────────────────────────────────────────┤
│                    ② 模型管理层                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ Hugging Face  │  │ convert_hf_  │  │ llama-quantize   │  │
│  │   Hub 下载    │→ │ to_gguf.py   │→ │  (Q4_K_M/Q8_0)   │  │
│  │              │  │ 格式转换      │  │ 量化压缩         │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                    ① 基础设施层                              │
│  ┌────────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ NVIDIA GPU │ │Apple M系列 │ │ AMD GPU  │ │  x86_64 CPU  │  │
│  │  (CUDA)    │ │  (Metal)  │ │ (Vulkan) │ │  (AVX2/512)  │  │
│  └────────────┘ └──────────┘ └──────────┘ └──────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 技术选型对比

| 组件 | 用户原方案 | **优化后方案** | 理由 |
|------|-----------|---------------|------|
| 推理引擎 | llama.cpp 二进制 | **llama-server** | 官方 C++ HTTP 服务，内置 OpenAI 兼容 API，无需 Python 封装 |
| API 封装 | FastAPI/Flask | **直接使用 llama-server** | 消除 Python GIL 和跨语言调用开销，延迟降低 30-50% |
| Tokenization | HuggingFace Tokenizer | **llama-server 内嵌** | GGUF 文件自带 tokenizer，无需外部依赖 |
| 模型格式 | 提及 model.bin | **GGUF 格式** | llama.cpp 标准格式，支持量化元数据 |
| 量化工具 | 未明确 | **llama-quantize** | 官方工具，支持 1.5-8 bit 多种量化策略 |
| 多模型管理 | 未明确 | **models.ini 路由** | 单端口多模型，自动热切换 |

### 1.3 核心优势

- **零 Python 运行时依赖**：推理服务纯 C++，不依赖 PyTorch/Transformers
- **单文件部署**：单个 GGUF 文件包含模型权重 + tokenizer + 元数据
- **硬件自适应**：同一 GGUF 可在 CPU/GPU/Metal 上运行，自动选择最佳后端
- **OpenAI API 兼容**：`/v1/chat/completions`, `/v1/embeddings`, `/v1/models` 等端点
- **量化灵活**：Q2_K 到 Q8_0，支持 imatrix 重要性矩阵量化

---

## 2. 流水线全景图

```
┌──────────────────────────────────────────────────────────────────────┐
│                        CI/CD 触发器                                  │
│   (新模型发布 / 代码更新 / 定时任务 / 手动触发)                       │
└─────────────────────────────┬────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  STEP 1: 模型获取                                                     │
│  ┌─────────────────┐    ┌─────────────────┐                          │
│  │ huggingface-cli │ or │ snapshot_download│ 从 Hub 拉取原始模型      │
│  │ download <model>│    │ (Python 脚本)    │  (safetensors/bin)       │
│  └────────┬────────┘    └─────────────────┘                          │
└───────────┼──────────────────────────────────────────────────────────┘
            ▼
┌──────────────────────────────────────────────────────────────────────┐
│  STEP 2: 格式转换 (Python 环境)                                       │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │ python llama.cpp/convert_hf_to_gguf.py                      │     │
│  │   ./downloaded-model/                                       │     │
│  │   --outfile model-f16.gguf                                  │     │
│  │   --outtype f16                                             │     │
│  └─────────────────────────────────────────────────────────────┘     │
└───────────┼──────────────────────────────────────────────────────────┘
            ▼
┌──────────────────────────────────────────────────────────────────────┐
│  STEP 3: 量化压缩                                                     │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │ ./llama-quantize model-f16.gguf model-Q4_K_M.gguf Q4_K_M   │     │
│  │                                                             │     │
│  │ # 或启用 imatrix 高精度量化                                  │     │
│  │ ./llama-imatrix -m model-f16.gguf -f calib.txt -o imatrix.dat│    │
│  │ ./llama-quantize --imatrix imatrix.dat model-f16.gguf       │     │
│  │   model-IQ4_XS.gguf IQ4_XS                                 │     │
│  └─────────────────────────────────────────────────────────────┘     │
└───────────┼──────────────────────────────────────────────────────────┘
            ▼
┌──────────────────────────────────────────────────────────────────────┐
│  STEP 4: 编译 llama.cpp (多后端)                                      │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                  │
│  │ CUDA 后端    │ │ Vulkan 后端  │ │ CPU 后端     │                  │
│  │ -DGGML_CUDA=ON│ │-DGGML_VULKAN=ON│ │ 默认 AVX2   │                  │
│  └──────────────┘ └──────────────┘ └──────────────┘                  │
└───────────┼──────────────────────────────────────────────────────────┘
            ▼
┌──────────────────────────────────────────────────────────────────────┐
│  STEP 5: 部署 llama-server                                            │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │ llama-server                                                │     │
│  │   --model model-Q4_K_M.gguf                                 │     │
│  │   --host 0.0.0.0                                           │     │
│  │   --port 8080                                              │     │
│  │   --n-gpu-layers 999    # 卸载所有层到 GPU                   │     │
│  │   --ctx-size 32768      # 上下文长度                        │     │
│  │   --parallel 4          # 并发批次                           │     │
│  └─────────────────────────────────────────────────────────────┘     │
└───────────┼──────────────────────────────────────────────────────────┘
            ▼
┌──────────────────────────────────────────────────────────────────────┐
│  STEP 6: 健康检查与服务注册                                            │
│  ┌─────────────────┐    ┌─────────────────┐                          │
│  │ curl /health    │ →  │ Prometheus 注册 │                          │
│  │ curl /v1/models │    │ AlertManager    │                          │
│  └─────────────────┘    └─────────────────┘                          │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 3. 阶段一：模型管理层

### 3.1 Hugging Face Hub 模型下载

#### 方式 A：使用 huggingface-cli（推荐）

```bash
# 安装 CLI
pip install huggingface_hub hf_transfer

# 设置加速下载
export HF_HUB_ENABLE_HF_TRANSFER=1

# 下载完整模型仓库（含 safetensors）
huggingface-cli download meta-llama/Llama-3.1-8B-Instruct \
  --local-dir ./models/llama-3.1-8b-hf \
  --local-dir-use-symlinks False

# 对于 gated 模型（需先在 Hub 上接受许可协议）
# 使用 --token 或设置 HF_TOKEN 环境变量
huggingface-cli download meta-llama/Llama-3.1-8B-Instruct \
  --token $HF_TOKEN \
  --local-dir ./models/llama-3.1-8b-hf
```

#### 方式 B：使用 Python 脚本（适合 CI/CD）

```python
#!/usr/bin/env python3
"""模型下载脚本 - 适合集成到 CI/CD 流水线"""

import os
import sys
from huggingface_hub import snapshot_download, hf_hub_download

def download_model(
    repo_id: str,
    local_dir: str,
    allow_patterns: list[str] = None,
    token: str = None
):
    """下载 Hugging Face 模型到本地目录"""
    
    print(f"[INFO] 开始下载模型: {repo_id}")
    print(f"[INFO] 目标目录: {local_dir}")
    
    os.makedirs(local_dir, exist_ok=True)
    
    try:
        snapshot_download(
            repo_id=repo_id,
            local_dir=local_dir,
            local_dir_use_symlinks=False,
            allow_patterns=allow_patterns or ["*.safetensors", "*.json", "*.txt", "*.model"],
            token=token or os.environ.get("HF_TOKEN"),
            resume_download=True,  # 支持断点续传
        )
        print(f"[SUCCESS] 模型下载完成: {local_dir}")
        return local_dir
    except Exception as e:
        print(f"[ERROR] 下载失败: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="下载 Hugging Face 模型")
    parser.add_argument("--repo-id", required=True, help="模型仓库 ID")
    parser.add_argument("--output", required=True, help="输出目录")
    parser.add_argument("--token", default=None, help="Hugging Face Token")
    args = parser.parse_args()
    
    download_model(args.repo_id, args.output, token=args.token)
```

### 3.2 GGUF 格式转换

#### 转换脚本

```bash
#!/bin/bash
# convert-to-gguf.sh - GGUF 格式转换流水线

set -euo pipefail

# 参数
MODEL_DIR="${1:-./models/llama-3.1-8b-hf}"  # 输入：HF 模型目录
OUTPUT_DIR="${2:-./models/gguf}"              # 输出：GGUF 目录
CONVERT_SCRIPT="${3:-./llama.cpp/convert_hf_to_gguf.py}"
OUTTYPE="${4:-f16}"                           # f16, bf16, q8_0

MODEL_NAME=$(basename "$MODEL_DIR")
OUTPUT_FILE="${OUTPUT_DIR}/${MODEL_NAME}-${OUTTYPE}.gguf"

echo "========================================"
echo "GGUF 格式转换"
echo "========================================"
echo "输入目录: $MODEL_DIR"
echo "输出文件: $OUTPUT_FILE"
echo "输出类型: $OUTTYPE"

# 检查依赖
if [ ! -f "$CONVERT_SCRIPT" ]; then
    echo "[ERROR] 转换脚本不存在: $CONVERT_SCRIPT"
    echo "请克隆 llama.cpp 仓库:"
    echo "  git clone https://github.com/ggml-org/llama.cpp.git"
    exit 1
fi

# 安装 Python 依赖（仅需转换阶段）
pip install -q -r requirements.txt 2>/dev/null || true

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 执行转换
echo "[STEP] 执行转换..."
python3 "$CONVERT_SCRIPT" \
    "$MODEL_DIR" \
    --outfile "$OUTPUT_FILE" \
    --outtype "$OUTTYPE" \
    --verbose

echo "[SUCCESS] 转换完成: $OUTPUT_FILE"
ls -lh "$OUTPUT_FILE"
```

#### 支持的转换类型

| `--outtype` | 说明 | 用途 |
|------------|------|------|
| `f32` | 全精度 FP32 | 基准测试 |
| `f16` | 半精度 FP16 | 转换中间态，量化源 |
| `bf16` | Brain Float 16 | 新架构推荐 |
| `q8_0` | 8-bit 量化 | 质量优先 |
| `auto` | 自动检测 | 根据模型自动选择 |

### 3.3 量化压缩

#### 基础量化

```bash
#!/bin/bash
# quantize.sh - 模型量化流水线

set -euo pipefail

INPUT_GGUF="${1}"                    # 输入：F16 GGUF 文件
QUANT_TYPE="${2:-Q4_K_M}"            # 量化类型
OUTPUT_DIR="${3:-./models/quantized}"

MODEL_BASENAME=$(basename "$INPUT_GGUF" .gguf)
OUTPUT_GGUF="${OUTPUT_DIR}/${MODEL_BASENAME}-${QUANT_TYPE}.gguf"

echo "========================================"
echo "模型量化: $QUANT_TYPE"
echo "========================================"

mkdir -p "$OUTPUT_DIR"

# 量化命令
./llama.cpp/build/bin/llama-quantize \
    "$INPUT_GGUF" \
    "$OUTPUT_GGUF" \
    "$QUANT_TYPE"

echo "[SUCCESS] 量化完成: $OUTPUT_GGUF"
ls -lh "$OUTPUT_GGUF"
```

#### 支持的量化类型

| 量化类型 | 每参数位数 | 质量评级 | 适用场景 |
|---------|-----------|---------|---------|
| `Q2_K` | ~2.1 bit | ★★☆☆☆ | 极致压缩，质量损失明显 |
| `Q3_K_S` | ~2.7 bit | ★★★☆☆ | 小模型/低资源环境 |
| `Q4_K_S` | ~3.6 bit | ★★★☆☆ | 平衡偏向速度 |
| `Q4_K_M` | ~3.8 bit | ★★★★☆ | **推荐：质量与速度平衡** |
| `Q5_K_S` | ~4.3 bit | ★★★★☆ | 高质量需求 |
| `Q5_K_M` | ~4.5 bit | ★★★★☆ | 接近原始质量 |
| `Q6_K` | ~5.0 bit | ★★★★☆ | 代码/数学任务 |
| `Q8_0` | ~8.0 bit | ★★★★★ | 最高质量，接近无损 |
| `IQ4_XS` | ~4.0 bit | ★★★★☆ | imatrix 优化，质量媲美 Q5 |

#### 高级：imatrix 重要性矩阵量化

```bash
#!/bin/bash
# imatrix-quantization.sh - 高精度量化

CALIBRATION_FILE="calibration-data.txt"  # 校准数据（模型训练语料样本）
F16_MODEL="model-f16.gguf"

# Step 1: 生成重要性矩阵（约 10-30 分钟）
./llama.cpp/build/bin/llama-imatrix \
    -m "$F16_MODEL" \
    -f "$CALIBRATION_FILE" \
    -o imatrix.dat \
    --chunks 100  # 分析 100 个文本块

# Step 2: 使用 imatrix 进行 IQ 量化
./llama.cpp/build/bin/llama-quantize \
    --imatrix imatrix.dat \
    "$F16_MODEL" \
    "model-IQ4_XS.gguf" \
    IQ4_XS

# 结果：IQ4_XS (约 4.0bpw) 质量 ≈ Q5_K_M，大小 ≈ Q4_K_M
```

#### 校准数据格式

```
calibration-data.txt（每行一个独立文本，长度 512-2048 tokens）
────────────────────────────────────────
The transformer architecture has revolutionized natural language processing...
In 2017, Google researchers introduced the attention mechanism...
Large language models are trained on vast corpora of internet text...
Quantization reduces model precision to decrease memory usage...
（100-500 行即可，内容应与模型训练数据分布一致）
```

### 3.4 模型验证

```bash
#!/bin/bash
# verify-model.sh - 量化后模型验证

MODEL_GGUF="${1}"

echo "[STEP] 模型元数据检查"
./llama.cpp/build/bin/llama-gguf-dump "$MODEL_GGUF" | head -50

echo "[STEP] 推理 smoke test"
./llama.cpp/build/bin/llama-cli \
    -m "$MODEL_GGUF" \
    -p "The capital of France is" \
    -n 10 \
    --temp 0.0

echo "[STEP] 基准测试 (PP512 + TG128)"
./llama.cpp/build/bin/llama-bench \
    -m "$MODEL_GGUF" \
    -p 512 -n 128 \
    --repetitions 3
```

---

## 4. 阶段二：编译构建层

### 4.1 环境准备

```bash
# Ubuntu/Debian 依赖
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    cmake \
    git \
    libcurl4-openssl-dev \
    python3-pip

# CentOS/RHEL/Fedora
sudo dnf install -y gcc gcc-c++ cmake git libcurl-devel python3-pip

# macOS
xcode-select --install
brew install cmake git
```

### 4.2 源码获取

```bash
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
# 可选：切换到稳定版本
git checkout b5353  # 2026-06 最新稳定版
```

### 4.3 多后端编译

#### A. CPU 后端（通用，无 GPU）

```bash
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_CURL=ON \
  -DLLAMA_NATIVE=ON  # 针对当前 CPU 指令集优化

cmake --build build --config Release -j$(nproc)

# 产出：
# ./build/bin/llama-server
# ./build/bin/llama-cli
# ./build/bin/llama-quantize
# ./build/bin/llama-bench
```

#### B. NVIDIA CUDA 后端（推荐，最高性能）

```bash
# 前置：安装 CUDA Toolkit (https://developer.nvidia.com/cuda-downloads)
nvcc --version  # 验证安装

cmake -B build-cuda \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_CURL=ON \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES="native"  # 自动检测 GPU 架构

cmake --build build-cuda --config Release -j$(nproc)
```

#### C. Apple Metal 后端（Apple Silicon）

```bash
cmake -B build-metal \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_CURL=ON \
  -DGGML_METAL=ON \
  -DCMAKE_OSX_ARCHITECTURES="arm64"

cmake --build build-metal --config Release -j$(sysctl -n hw.ncpu)
```

#### D. Vulkan 后端（AMD/Intel GPU）

```bash
# 前置：安装 Vulkan SDK
# Ubuntu: apt-get install -y vulkan-sdk
# 或: apt-get install -y libvulkan-dev

cmake -B build-vulkan \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_CURL=ON \
  -DGGML_VULKAN=ON

cmake --build build-vulkan --config Release -j$(nproc)
```

#### E. 多后端同时编译（运行时自动选择）

```bash
cmake -B build-multi \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_CURL=ON \
  -DGGML_CUDA=ON \
  -DGGML_VULKAN=ON \
  -DGGML_BACKEND_DL=ON  # 动态后端加载

cmake --build build-multi --config Release -j$(nproc)

# 运行时选择后端
./build-multi/bin/llama-server --list-devices
./build-multi/bin/llama-server --device cuda:0
./build-multi/bin/llama-server --device vulkan:0
./build-multi/bin/llama-server --device none  # 纯 CPU
```

#### F. 其他后端

| 后端 | CMake 选项 | 适用硬件 |
|------|-----------|---------|
| AMD ROCm (HIP) | `-DGGML_HIP=ON` | AMD Radeon GPU |
| Intel SYCL | `-DGGML_SYCL=ON` | Intel Arc/Data Center GPU |
| Intel OpenVINO | `-DGGML_OPENVINO=ON` | Intel CPU/GPU/NPU |
| 华为 CANN | `-DGGML_CANN=ON` | Ascend NPU |
| AMD ZenDNN | `-DGGML_ZENDNN=ON` | AMD EPYC CPU |

### 4.4 动态后端加载（生产推荐）

```bash
# 动态加载使同一个二进制可在不同硬件上运行
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_CURL=ON \
  -DGGML_BACKEND_DL=ON \
  -DGGML_CUDA=ON \
  -DGGML_VULKAN=ON

# 运行时自动检测可用后端
./build/bin/llama-server --list-devices
# 输出示例：
# Device 0: NVIDIA GeForce RTX 4090 (CUDA)
# Device 1: Intel Arc A770 (Vulkan)
# Device 2: CPU (AVX2)
```

### 4.5 Docker 编译（可复现构建）

```dockerfile
# Dockerfile.build - 编译环境
FROM nvidia/cuda:12.4-devel-ubuntu22.04 AS builder

WORKDIR /build

# 安装依赖
RUN apt-get update && apt-get install -y \
    git cmake build-essential libcurl4-openssl-dev \
    python3 python3-pip python3-venv

# 克隆源码
ARG LLAMA_VERSION=master
RUN git clone --depth 1 --branch ${LLAMA_VERSION} \
    https://github.com/ggml-org/llama.cpp.git

WORKDIR /build/llama.cpp

# 编译（CUDA + Vulkan 后端）
RUN cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_BUILD_SERVER=ON \
    -DLLAMA_CURL=ON \
    -DGGML_CUDA=ON \
    -DGGML_VULKAN=ON \
    -DGGML_NATIVE=OFF \
    -DCMAKE_CUDA_ARCHITECTURES="75;80;86;89;90"

RUN cmake --build build --config Release -j$(nproc)

# 运行时镜像（最小化）
FROM nvidia/cuda:12.4-runtime-ubuntu22.04

WORKDIR /app

# 仅复制必要文件
COPY --from=builder /build/llama.cpp/build/bin/llama-server /usr/local/bin/
COPY --from=builder /build/llama.cpp/build/bin/llama-quantize /usr/local/bin/
COPY --from=builder /build/llama.cpp/build/bin/llama-bench /usr/local/bin/
COPY --from=builder /build/llama.cpp/build/bin/llama-cli /usr/local/bin/

# 运行时依赖
RUN apt-get update && apt-get install -y \
    libcurl4 libgomp1 vulkan-tools \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 8080
ENTRYPOINT ["llama-server"]
```

```bash
# 构建命令
docker build -f Dockerfile.build -t llama-server:cuda12.4 .

# 验证
docker run --rm --gpus all llama-server:cuda12.4 --version
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
```

---

## 7. 阶段五：监控与运维层

### 7.1 Prometheus Metrics

llama-server 原生暴露 Prometheus 格式的监控指标：

```bash
# 获取 metrics
curl -s http://localhost:8080/metrics

# 输出示例：
# llama:tokens_predicted_total 15234
# llama:tokens_predicted_seconds_total 45.23
# llama:prompt_tokens_total 8921
# llama:prompt_seconds_total 12.34
# llama:n_decode_total 15234
# llama:n_busy_slots 2
# llama:n_idle_slots 2
# http_requests_total{method="POST",path="/v1/chat/completions"} 1234
# http_request_duration_seconds{quantile="0.95"} 0.234
```

### 7.2 Prometheus 配置

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'llama-server'
    static_configs:
      - targets: ['llama-server:8080']
    metrics_path: '/metrics'
    scrape_interval: 10s
```

### 7.3 Grafana Dashboard

推荐监控面板：

| Panel | Query | 说明 |
|-------|-------|------|
| 请求速率 | `rate(http_requests_total[5m])` | QPS |
| P95 延迟 | `histogram_quantile(0.95, http_request_duration_seconds)` | 响应延迟 |
| Token 吞吐 | `rate(llama:tokens_predicted_total[5m])` | tokens/second |
| 并发槽位 | `llama:n_busy_slots` | 当前并发请求数 |
| GPU 利用率 | `nvidia_gpu_utilization_gpu[5m]` | GPU 使用率（需 node-exporter） |
| VRAM 使用 | `nvidia_gpu_memory_used_bytes / nvidia_gpu_memory_total_bytes` | 显存使用率 |

### 7.4 健康检查与自动重启

```bash
#!/bin/bash
# healthcheck.sh - 健康检查脚本

HEALTH_URL="http://localhost:8080/health"
MAX_RETRY=3
RETRY=0

while [ $RETRY -lt $MAX_RETRY ]; do
    if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
        echo "[OK] llama-server 健康"
        exit 0
    fi
    RETRY=$((RETRY + 1))
    echo "[WARN] 健康检查失败 ($RETRY/$MAX_RETRY)，等待重试..."
    sleep 5
done

echo "[ERROR] llama-server 不健康，执行重启..."
# systemd 会自动重启
# 或: docker restart llama-server
```

### 7.5 systemd 服务配置

```ini
# /etc/systemd/system/llama-server.service
[Unit]
Description=Llama.cpp Server
After=network.target

[Service]
Type=simple
User=llama
Group=llama

WorkingDirectory=/opt/llama-server
Environment="CUDA_VISIBLE_DEVICES=0"
Environment="GGML_CUDA_NO_PINNED=1"

ExecStart=/usr/local/bin/llama-server \
    --model /opt/models/llama-3.1-8b-Q4_K_M.gguf \
    --host 0.0.0.0 \
    --port 8080 \
    --n-gpu-layers 999 \
    --ctx-size 32768 \
    --parallel 4 \
    --metrics \
    --threads-http 4

ExecStartPre=/usr/local/bin/healthcheck.sh
Restart=on-failure
RestartSec=10

# 资源限制
LimitNOFILE=65536
MemoryMax=32G

[Install]
WantedBy=multi-user.target
```

```bash
# 启用服务
sudo systemctl daemon-reload
sudo systemctl enable llama-server
sudo systemctl start llama-server
sudo systemctl status llama-server
```

---

## 8. CI/CD 自动化流水线

### 8.1 GitHub Actions 完整流水线

```yaml
# .github/workflows/llama-deploy.yml
name: Llama.cpp 模型部署流水线

on:
  # 手动触发
  workflow_dispatch:
    inputs:
      model_repo:
        description: 'Hugging Face 模型仓库'
        required: true
        default: 'meta-llama/Llama-3.1-8B-Instruct'
      quant_type:
        description: '量化类型'
        required: true
        default: 'Q4_K_M'
        type: choice
        options:
          - Q4_K_M
          - Q5_K_M
          - Q6_K
          - Q8_0
          - IQ4_XS
  # 定时检查更新（每周一凌晨）
  schedule:
    - cron: '0 0 * * 1'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: llama-server

jobs:
  # ===== Stage 1: 模型获取与转换 =====
  convert:
    runs-on: ubuntu-latest
    outputs:
      model_name: ${{ steps.meta.outputs.model_name }}
      quant_type: ${{ steps.meta.outputs.quant_type }}
      cache_key: ${{ steps.meta.outputs.cache_key }}
    steps:
      - name: 检出代码
        uses: actions/checkout@v4

      - name: 设置 Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: 安装依赖
        run: |
          pip install huggingface_hub transformers torch
          git clone --depth 1 https://github.com/ggml-org/llama.cpp.git

      - name: 提取模型信息
        id: meta
        run: |
          MODEL_REPO="${{ github.event.inputs.model_repo || 'meta-llama/Llama-3.1-8B-Instruct' }}"
          QUANT="${{ github.event.inputs.quant_type || 'Q4_K_M' }}"
          MODEL_NAME=$(echo "$MODEL_REPO" | tr '/' '-')
          CACHE_KEY="${MODEL_NAME}-${QUANT}"
          echo "model_name=$MODEL_NAME" >> $GITHUB_OUTPUT
          echo "quant_type=$QUANT" >> $GITHUB_OUTPUT
          echo "cache_key=$CACHE_KEY" >> $GITHUB_OUTPUT

      - name: 下载模型
        env:
          HF_TOKEN: ${{ secrets.HF_TOKEN }}
        run: |
          python scripts/download-model.py \
            --repo-id "${{ github.event.inputs.model_repo }}" \
            --output ./models/hf-model

      - name: 转换为 GGUF
        run: |
          python llama.cpp/convert_hf_to_gguf.py \
            ./models/hf-model \
            --outfile "./models/${{ steps.meta.outputs.model_name }}-f16.gguf" \
            --outtype f16

      - name: 上传 F16 中间产物
        uses: actions/upload-artifact@v4
        with:
          name: model-f16
          path: "./models/${{ steps.meta.outputs.model_name }}-f16.gguf"
          retention-days: 1

  # ===== Stage 2: 量化 =====
  quantize:
    runs-on: ubuntu-latest
    needs: convert
    steps:
      - name: 检出 llama.cpp
        run: git clone --depth 1 https://github.com/ggml-org/llama.cpp.git

      - name: 编译量化工具
        run: |
          cmake -B llama.cpp/build \
            -DCMAKE_BUILD_TYPE=Release \
            -DLLAMA_BUILD_SERVER=OFF
          cmake --build llama.cpp/build --config Release -j$(nproc)

      - name: 下载 F16 产物
        uses: actions/download-artifact@v4
        with:
          name: model-f16
          path: ./models/

      - name: 执行量化
        run: |
          ./llama.cpp/build/bin/llama-quantize \
            "./models/${{ needs.convert.outputs.model_name }}-f16.gguf" \
            "./models/${{ needs.convert.outputs.model_name }}-${{ needs.convert.outputs.quant_type }}.gguf" \
            "${{ needs.convert.outputs.quant_type }}"

      - name: 验证模型
        run: |
          ./llama.cpp/build/bin/llama-bench \
            -m "./models/${{ needs.convert.outputs.model_name }}-${{ needs.convert.outputs.quant_type }}.gguf" \
            -p 512 -n 128

      - name: 上传量化模型
        uses: actions/upload-artifact@v4
        with:
          name: model-quantized
          path: "./models/${{ needs.convert.outputs.model_name }}-${{ needs.convert.outputs.quant_type }}.gguf"
          retention-days: 7

  # ===== Stage 3: 构建 Docker 镜像 =====
  build-image:
    runs-on: ubuntu-latest
    needs: [convert, quantize]
    steps:
      - name: 检出代码
        uses: actions/checkout@v4

      - name: 下载量化模型
        uses: actions/download-artifact@v4
        with:
          name: model-quantized
          path: ./models/

      - name: 设置 Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: 登录容器仓库
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: 构建并推送
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./docker/Dockerfile.server
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:${{ needs.convert.outputs.cache_key }}
            ${{ env.REGISTRY }}/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:latest
          build-args: |
            MODEL_FILE=models/${{ needs.convert.outputs.model_name }}-${{ needs.convert.outputs.quant_type }}.gguf
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # ===== Stage 4: 部署到服务器 =====
  deploy:
    runs-on: ubuntu-latest
    needs: build-image
    if: github.ref == 'refs/heads/main'
    environment: production
    steps:
      - name: 部署到远程服务器
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.DEPLOY_HOST }}
          username: ${{ secrets.DEPLOY_USER }}
          key: ${{ secrets.DEPLOY_KEY }}
          script: |
            cd /opt/llama-server
            docker pull ${{ env.REGISTRY }}/${{ github.repository_owner }}/${{ env.IMAGE_NAME }}:latest
            docker-compose up -d --force-recreate llama-server
            sleep 5
            curl -sf http://localhost:8080/health || exit 1
```

### 8.2 docker-compose 生产编排

```yaml
# docker-compose.yml
version: '3.8'

services:
  llama-server:
    image: ${REGISTRY}/llama-server:${MODEL_TAG:-latest}
    container_name: llama-server
    restart: unless-stopped
    
    # GPU 支持
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    
    # 如果不用 GPU，注释上面 deploy 段，启用下面 runtime
    # runtime: nvidia
    
    environment:
      - CUDA_VISIBLE_DEVICES=0
      - GGML_CUDA_NO_PINNED=1
      - HF_TOKEN=${HF_TOKEN}
    
    volumes:
      - ./models:/models:ro
      - hf-cache:/root/.cache/huggingface
    
    ports:
      - "8080:8080"
    
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    
    command: >
      --models /models/models.ini
      --host 0.0.0.0
      --port 8080
      --n-gpu-layers 999
      --ctx-size 32768
      --parallel 4
      --metrics
      --threads-http 4
    
    logging:
      driver: json-file
      options:
        max-size: "100m"
        max-file: "5"

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-admin}
    volumes:
      - grafana-data:/var/lib/grafana
      - ./monitoring/dashboards:/etc/grafana/provisioning/dashboards:ro
      - ./monitoring/datasources:/etc/grafana/provisioning/datasources:ro
    ports:
      - "3000:3000"
    depends_on:
      - prometheus

  nginx:
    image: nginx:alpine
    container_name: llama-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - llama-server

volumes:
  hf-cache:
  prometheus-data:
  grafana-data:
```

### 8.3 本地一键部署脚本

```bash
#!/bin/bash
# deploy.sh - 本地一键部署脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="llama-infra"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查依赖
check_deps() {
    log_info "检查依赖..."
    command -v docker >/dev/null 2>&1 || { log_error "Docker 未安装"; exit 1; }
    command -v docker-compose >/dev/null 2>&1 || { log_error "docker-compose 未安装"; exit 1; }
    
    # 检查 NVIDIA Docker 支持
    if ! docker info 2>/dev/null | grep -q "nvidia"; then
        log_warn "NVIDIA Docker 运行时未检测到，GPU 加速可能不可用"
        log_warn "如需 GPU 支持，请安装 nvidia-docker2:"
        log_warn "  https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
    fi
}

# 准备目录
setup_dirs() {
    log_info "准备目录结构..."
    mkdir -p "$SCRIPT_DIR"/{models,monitoring,nginx/ssl}
    
    # 下载默认模型（如果没有）
    if [ ! -f "$SCRIPT_DIR/models/models.ini" ]; then
        log_info "创建默认 models.ini..."
        cat > "$SCRIPT_DIR/models/models.ini" << 'EOF'
[*]
n-gpu-layers = all
ctx-size = 32768
parallel = 4

[default]
model = /models/default.gguf
chat-template = llama3
EOF
    fi
}

# 启动服务
start() {
    check_deps
    setup_dirs
    
    log_info "启动服务..."
    export REGISTRY="${REGISTRY:-ghcr.io/your-org}"
    export MODEL_TAG="${MODEL_TAG:-latest}"
    export HF_TOKEN="${HF_TOKEN:-}"
    export GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"
    
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    
    log_info "等待服务启动..."
    sleep 10
    
    # 健康检查
    if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        log_info "llama-server 启动成功!"
        log_info "  API 地址: http://localhost:8080"
        log_info "  Prometheus: http://localhost:9090"
        log_info "  Grafana: http://localhost:3000 (admin/${GRAFANA_PASSWORD})"
    else
        log_error "服务启动失败，查看日志:"
        docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs llama-server
        exit 1
    fi
}

# 停止服务
stop() {
    log_info "停止服务..."
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
}

# 查看日志
logs() {
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs -f "${1:-llama-server}"
}

# 更新模型
update_model() {
    local repo="${1}"
    local quant="${2:-Q4_K_M}"
    
    log_info "更新模型: $repo (quant: $quant)"
    
    # 使用 llama-server 直接从 HF 加载
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" exec llama-server \
        llama-server -hf "${repo}:${quant}" --port 8081 &
    
    log_info "新模型服务在端口 8081（测试用）"
}

# 主入口
case "${1:-start}" in
    start) start ;;
    stop) stop ;;
    restart) stop && start ;;
    logs) logs "${2:-}" ;;
    update) update_model "${2}" "${3:-Q4_K_M}" ;;
    *) echo "用法: $0 {start|stop|restart|logs|update <repo> [quant]}" ;;
esac
```

---

## 9. Hugging Face Inference Endpoints 云端部署

> Hugging Face Inference Endpoints 是 Hugging Face 官方提供的托管推理服务，支持多种推理引擎（包括 llama.cpp），适合快速上线、无需自行维护基础设施的场景。

### 9.1 双轨部署策略

根据你的运维能力和业务需求，可选择以下两种部署模式：

| 维度 | **自托管 (Self-Hosted)** | **HF Inference Endpoints** |
|------|-------------------------|---------------------------|
| **基础设施** | 自行管理 GPU 服务器 | HF 全托管，零运维 |
| **成本模式** | 固定成本（租/购 GPU） | 按秒计费，弹性扩缩容 |
| **适用场景** | 高吞吐、长期运行、数据敏感 | 快速验证、低频调用、MVP |
| **延迟控制** | 完全可控（同机房） | 依赖 HF 网络（通常 <100ms） |
| **数据隐私** | 数据不出内网 | 数据发送到 HF 云端 |
| **GPU 选择** | 任意硬件 | HF 提供 NVIDIA 实例 |
| **自定义程度** | 完全自由 | 受限于 HF 平台配置 |
| **llama.cpp 支持** | 完整功能 | 通过 Custom Container 支持 |

**推荐策略**：
- **开发/测试阶段**：使用 HF Inference Endpoints 快速验证模型效果
- **生产阶段**：自托管获得最佳性价比和数据控制权
- **混合模式**：HF Endpoints 作为自托管的灾备/弹性溢出

### 9.2 HF Inference Endpoints 架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    Hugging Face Hub                              │
│         (模型仓库: meta-llama/Llama-3.1-8B-Instruct)            │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              Hugging Face Inference Endpoints                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  推理引擎选择                             │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │   │
│  │  │ vLLM     │ │ TGI      │ │ TEI      │ │llama.cpp │  │   │
│  │  │ (通用)   │ │ (文本)   │ │ (嵌入)   │ │(GGUF)   │  │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              自定义层 (可选)                               │   │
│  │  ┌──────────────┐  ┌──────────────────────────────┐    │   │
│  │  │Custom Handler│  │ Custom Container (llama.cpp) │    │   │
│  │  │  handler.py  │  │   Dockerfile + GGUF 模型      │    │   │
│  │  └──────────────┘  └──────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              基础设施 (HF 托管)                            │   │
│  │  NVIDIA GPU 实例 · 自动扩缩容 · SSL · 监控 · 日志          │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   REST API      │
                    │  /predict       │
                    │  /health        │
                    └─────────────────┘
```

### 9.3 通过 Custom Container 部署 llama.cpp

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

```python
# handler.py - Hugging Face Inference Endpoints 自定义处理程序
# 适用于: transformers/sentence-transformers/diffusers 模型
# 如需 llama.cpp，请使用 Custom Container 模式

from typing import Dict, List, Any


class EndpointHandler:
    """
    HF Inference Endpoints 自定义处理程序
    
    __init__: 端点启动时调用一次，用于加载模型
    __call__: 每个请求调用，data 包含 inputs 和可选参数
    """
    
    def __init__(self, path: str = ""):
        """
        初始化模型和依赖
        
        Args:
            path: 模型权重路径 (HF 自动传入)
        """
        # 加载模型（示例使用 transformers）
        from transformers import pipeline
        
        self.pipeline = pipeline(
            "text-classification",
            model=path,
            device=0  # GPU
        )
        
        # 可加载其他资源
        # self.tokenizer = AutoTokenizer.from_pretrained(path)
        
    def __call__(self, data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        处理推理请求
        
        Args:
            data: 请求体字典，至少包含 "inputs" 键
                  可包含自定义字段用于业务逻辑
        
        Returns:
            推理结果列表或字典
        """
        # 提取输入
        inputs = data.pop("inputs", data)
        
        # === 自定义预处理 ===
        # 示例: 检查输入长度
        if isinstance(inputs, str) and len(inputs) > 4096:
            inputs = inputs[:4096]  # 截断
        
        # === 推理 ===
        results = self.pipeline(inputs)
        
        # === 自定义后处理 ===
        # 示例: 添加置信度阈值过滤
        filtered = [
            r for r in results 
            if r.get("score", 0) > 0.5
        ]
        
        return filtered if filtered else results
```

#### 完整业务示例：带日期判断的情感分析

```python
# handler.py - 带节日判断的自定义情感分析
from typing import Dict, List, Any
from transformers import pipeline
import holidays


class EndpointHandler:
    def __init__(self, path: str = ""):
        self.pipeline = pipeline("text-classification", model=path)
        self.holidays = holidays.US()  # 美国节假日数据
    
    def __call__(self, data: Dict[str, Any]) -> List[Dict[str, Any]]:
        inputs = data.pop("inputs", data)
        date = data.pop("date", None)  # 自定义字段
        
        # 业务规则: 节假日自动返回 "happy"
        if date is not None and date in self.holidays:
            return [{"label": "happy", "score": 1.0}]
        
        # 正常推理
        return self.pipeline(inputs)
```

```python
# requirements.txt（与 handler.py 同目录）
transformers>=4.35.0
holidays>=0.45
```

#### 测试 handler.py 本地开发

```python
#!/usr/bin/env python3
"""本地测试 handler.py"""

# 模拟 HF Endpoint 的加载方式
from handler import EndpointHandler

# 初始化（path 指向本地模型目录）
handler = EndpointHandler(path="./distilbert-base-uncased-emotion")

# 测试非节假日
result_normal = handler({
    "inputs": "I am quite excited about this!",
    "date": "2024-03-15"  # 普通日期
})
print("普通日期:", result_normal)
# 输出: [{'label': 'joy', 'score': 0.998}]

# 测试节假日（美国独立日）
result_holiday = handler({
    "inputs": "Today is a tough day",  # 即使是负面文本
    "date": "2024-07-04"  # 节假日
})
print("节假日:", result_holiday)
# 输出: [{'label': 'happy', 'score': 1.0}]
```

### 9.5 自托管与 HF 云端混合架构

```
                    ┌─────────────────────────┐
                    │      客户端请求           │
                    │   (OpenAI SDK / curl)    │
                    └───────────┬─────────────┘
                                │
                    ┌───────────▼───────────┐
                    │      API Gateway       │
                    │   (Nginx / Kong)       │
                    └───────┬───────┬───────┘
                            │       │
              健康/低负载时   │       │  过载/故障时
                            │       │
                ┌───────────▼───┐   ▼───────────────┐
                │  自托管集群     │   │  HF Endpoint   │
                │  (llama-server)│   │  (溢出/灾备)    │
                │               │   │                │
                │ 主推理节点 × N │   │ Custom Container│
                │               │   │  (llama.cpp)   │
                └───────────────┘   └────────────────┘
                    固定成本          按调用付费
                    低延迟            弹性扩容
```

**溢出策略实现**：

```python
# overflow-router.py - 混合路由示例
import random
import requests

SELF_HOSTED_URL = "http://localhost:8080/v1/chat/completions"
HF_ENDPOINT_URL = "https://api-inference.huggingface.co/models/your-model"
HF_TOKEN = "hf_xxx"


def route_request(payload: dict) -> dict:
    """
    智能路由: 优先自托管，溢出到 HF Endpoint
    """
    # 策略 1: 随机分流 10% 到 HF（用于对比测试）
    if random.random() < 0.1:
        return call_hf_endpoint(payload)
    
    # 策略 2: 优先自托管，失败时 fallback
    try:
        return call_self_hosted(payload, timeout=5)
    except (requests.Timeout, requests.ConnectionError):
        log_warn("自托管超时，切换到 HF Endpoint")
        return call_hf_endpoint(payload)


def call_self_hosted(payload: dict, timeout: int = 30) -> dict:
    """调用自托管 llama-server"""
    resp = requests.post(
        SELF_HOSTED_URL,
        json=payload,
        timeout=timeout
    )
    resp.raise_for_status()
    return resp.json()


def call_hf_endpoint(payload: dict) -> dict:
    """调用 HF Inference Endpoint"""
    resp = requests.post(
        HF_ENDPOINT_URL,
        headers={"Authorization": f"Bearer {HF_TOKEN}"},
        json={"inputs": payload["messages"][-1]["content"]},
        timeout=60
    )
    resp.raise_for_status()
    return resp.json()
```

### 9.6 何时选择哪种方案

| 场景 | 推荐方案 | 理由 |
|------|---------|------|
| 个人开发/原型验证 | HF Inference Endpoints | 5 分钟上线，按调用付费 |
| 企业内部部署（数据敏感） | 自托管 llama-server | 数据不出内网 |
| 高吞吐生产服务 (>100 QPS) | 自托管集群 | 成本可控，延迟低 |
| 低频调用 (<1000次/天) | HF Inference Endpoints | 避免 GPU 闲置成本 |
| 需要自定义 CUDA kernel | 自托管 | 完全控制编译选项 |
| 需要 transformers 生态 | HF Custom Handler | 原生集成 pipeline |
| 需要 GGUF 量化模型 | 自托管 或 HF Custom Container | llama.cpp 原生支持 |
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
| Gemma 4 27B | Q4_K_M | ~16 GB | 24 GB | RTX 3090/4090 |

---

## 11. 附录

### A. 目录结构规范

```
llama-infra/
├── docker-compose.yml           # 服务编排
├── Dockerfile                   # 自定义构建
├── deploy.sh                    # 一键部署脚本
├── models/
│   ├── models.ini               # 多模型路由配置
│   ├── llama-3.1-8b-Q4_K_M.gguf
│   └── bge-m3-Q4_K_M.gguf
├── monitoring/
│   ├── prometheus.yml           # Prometheus 配置
│   ├── alert-rules.yml          # 告警规则
│   ├── datasources/             # Grafana 数据源
│   │   └── prometheus.yml
│   └── dashboards/              # Grafana 仪表盘
│       └── llama-server.json
├── nginx/
│   ├── nginx.conf               # 反向代理配置
│   └── ssl/                     # TLS 证书
├── scripts/
│   ├── download-model.py        # 模型下载
│   ├── convert-to-gguf.sh       # 格式转换
│   ├── quantize.sh              # 量化脚本
│   └── benchmark.py             # 性能测试
└── .github/
    └── workflows/
        └── llama-deploy.yml     # CI/CD 流水线
```

### B. 常见问题排查

```bash
# Q1: CUDA out of memory
# 解决: 减少 GPU 层数或量化级别
llama-server --model model.gguf --n-gpu-layers 20  # 只卸载 20 层到 GPU

# Q2: 模型加载缓慢
# 解决: 使用 NVMe SSD，启用 mmap
llama-server --model model.gguf --mmap

# Q3: 并发请求超时
# 解决: 增加 parallel 槽位和超时时间
llama-server --parallel 8 --timeout 600

# Q4: 上下文太长导致 OOM
# 解决: 减小 ctx-size 或 batch-size
llama-server --ctx-size 8192 --batch-size 1024

# Q5: CPU 使用率过高
# 解决: 限制线程数
llama-server --threads 8 --threads-batch 4

# Q6: 不同后端如何选择
# CUDA > Metal > Vulkan > CPU
# 运行时查看可用设备
llama-server --list-devices
```

### C. 参考资源

| 资源 | 链接 | 说明 |
|------|------|------|
| llama.cpp 官方仓库 | https://github.com/ggml-org/llama.cpp | 源码与文档 |
| 构建文档 | https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md | 多后端编译指南 |
| Server API 文档 | https://github.com/ggml-org/llama.cpp/tree/master/examples/server | API 端点参考 |
| Hugging Face GGUF | https://huggingface.co/models?library=gguf | GGUF 模型搜索 |
| GGUF-my-repo | https://huggingface.co/spaces/ggml-org/gguf-my-repo | 在线量化工具 |
| Unsloth GGUF | https://huggingface.co/unsloth | 高质量量化模型 |

---

> **总结**: 本方案构建了一条完整的自动化流水线，从 Hugging Face 模型获取到 llama-server 生产部署，全程基于纯 C++ 推理引擎，无需 Python 运行时。通过 GGUF 格式统一、多后端编译、OpenAI 兼容 API，实现了高效、轻量、易扩展的本地大模型服务架构。

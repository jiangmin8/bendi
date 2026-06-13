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


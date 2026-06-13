# AI 本地部署完整手册

> 适用环境：Ubuntu 24.04 / RTX 3060 12GB / CUDA 12.4
> 原则：全绝对路径，零软链接，零 .bashrc 环境变量污染

---

## 一、系统环境确认

```bash
# 检查系统版本
cat /etc/os-release

# 检查硬件
nvidia-smi
lspci | grep -i nvidia
```

**要求：**
- Ubuntu 24.04（默认 gcc 13.2, cmake 3.28, Python 3.12）
- NVIDIA 显卡驱动已安装（nvidia-smi 有输出）
- 至少 32GB 系统内存
- 磁盘空间 >= 100GB

---

## 二、基础编译依赖安装

```bash
sudo apt update
sudo apt install -y build-essential git cmake wget unzip subversion
```

**验证：**
```bash
gcc --version      # 13.2+
cmake --version    # 3.28+
git --version      # 任意版本
```

---

## 三、Python 虚拟环境（by-env）

```bash
# 创建虚拟环境（python3 自带 venv 模块，无需 apt 安装）
python3 -m venv /media/lz/baba/by-env

# 激活（仅当前终端有效，不污染系统）
source /media/lz/baba/by-env/bin/activate

# 升级基础工具
/media/lz/baba/by-env/bin/python -m pip install --upgrade pip setuptools wheel
```

---

## 四、CUDA Toolkit 12.4 安装

```bash
# 下载 runfile 安装包
wget https://developer.download.nvidia.com/compute/cuda/12.4.1/local_installers/cuda_12.4.1_550.54.15_linux.run \
  -P /media/lz/baba/

# 静默安装到指定目录
sudo sh /media/lz/baba/cuda_12.4.1_550.54.15_linux.run \
  --silent \
  --toolkit \
  --toolkitpath=/usr/local/cuda-12.4 \
  --no-opengl-libs \
  --no-drm \
  --no-man-page

# 创建统一软链接（这是唯一一次系统级链接，后续编译全用绝对路径）
sudo ln -sf /usr/local/cuda-12.4 /usr/local/cuda
```

**验证：**
```bash
/usr/local/cuda/bin/nvcc --version
```

**输出示例：**
```
nvcc: NVIDIA (R) Cuda compiler driver
Copyright (c) 2005-2024 NVIDIA Corporation
Built on Thu_Mar_28_02:18:24_PDT_2024
Cuda compilation tools, release 12.4, V12.4.131
```

---

## 五、目录结构规范（重要）

```
/media/lz/baba/
├── llama.cpp/              # 大语言模型推理引擎（源码+编译产物）
├── whisper.cpp/            # 语音转文字引擎
├── stable-diffusion.cpp/   # AI 画图引擎
├── by-env/                 # Python 虚拟环境
├── cuda-12.4/              # CUDA Toolkit
├── model/                  # 所有模型文件集中存放
│   ├── whisper/            # 语音模型
│   ├── sd/                 # 图像模型
│   └── *.gguf              # 大语言模型
└── bf/                     # 备份盘（可选）
```

---

## 六、llama.cpp 编译（大语言模型推理）

### 6.1 拉取源码

```bash
git clone https://github.com/ggml-org/llama.cpp.git /media/lz/baba/llama.cpp
```

### 6.2 编译 CUDA 版

```bash
mkdir -p /media/lz/baba/llama.cpp/build
cd /media/lz/baba/llama.cpp/build

cmake .. \
  -DGGML_CUDA=ON \
  -DGGML_VULKAN=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc

cmake --build . --config Release -j$(nproc)
```

### 6.3 验证编译产物

```bash
ls -la /media/lz/baba/llama.cpp/build/bin/llama-server
ls -la /media/lz/baba/llama.cpp/build/bin/llama-cli
ldd /media/lz/baba/llama.cpp/build/bin/llama-server | grep cuda
```

### 6.4 启动模型（18B Q4）

```bash
/media/lz/baba/llama.cpp/build/bin/llama-server \
  -m /media/lz/baba/model/qwen3.5-18b-a3b-reap-coding-heretic-v0.Q4_K_M.gguf \
  -ngl 999 \
  -c 8192 \
  --flash-attn on \
  -t 10 \
  --mlock \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --host 0.0.0.0 \
  --port 8081
```

**参数说明：**
| 参数 | 值 | 说明 |
|------|-----|------|
| -m | 模型绝对路径 | 指定 GGUF 模型文件 |
| -ngl | 999 | 自动将尽可能多的层卸载到 GPU |
| -c | 8192 | 上下文长度（tokens） |
| --flash-attn | on | Flash Attention 加速，省显存 |
| -t | 10 | CPU 线程数 |
| --mlock | - | 锁定内存，防止 swap |
| --cache-type-k/v | q8_0 | KV cache 量化，减半显存占用 |
| --host | 0.0.0.0 | 监听所有网卡 |
| --port | 8081 | 服务端口 |

**显存策略：** RTX 3060 12GB 跑 18B Q4，-ngl 999 自动分层，通常能卸 30~40 层到 GPU。

**API 端点：** `http://127.0.0.1:8081/v1/chat/completions`（OpenAI 兼容）

---

## 七、whisper.cpp 编译（语音转文字）

### 7.1 拉取源码

```bash
git clone https://github.com/ggerganov/whisper.cpp.git /media/lz/baba/whisper.cpp
```

### 7.2 编译 CUDA 版

```bash
mkdir -p /media/lz/baba/whisper.cpp/build
cd /media/lz/baba/whisper.cpp/build

cmake .. \
  -DGGML_CUDA=ON \
  -DGGML_VULKAN=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc

cmake --build . --config Release -j$(nproc)
```

### 7.3 模型目录

```bash
mkdir -p /media/lz/baba/model/whisper
```

### 7.4 启动（纯 CPU 模式，不跟 LLM 抢显存）

```bash
/media/lz/baba/whisper.cpp/build/bin/whisper-cli \
  -ng \
  -m /media/lz/baba/model/whisper/ggml-base.bin \
  -f /media/lz/baba/音频文件.wav \
  -l zh
```

**参数说明：**
| 参数 | 值 | 说明 |
|------|-----|------|
| -ng | - | 禁用 GPU，纯 CPU 运行 |
| -m | 模型路径 | whisper 模型 |
| -f | 音频文件 | 支持 wav/mp3/flac/ogg |
| -l | zh | 语言：中文 |

---

## 八、stable-diffusion.cpp 编译（AI 画图）

### 8.1 拉取源码（--recursive 必须加，拉 ggml 子模块）

```bash
git clone --recursive https://github.com/leejet/stable-diffusion.cpp.git /media/lz/baba/stable-diffusion.cpp
```

### 8.2 编译 CUDA 版

```bash
mkdir -p /media/lz/baba/stable-diffusion.cpp/build
cd /media/lz/baba/stable-diffusion.cpp/build

cmake .. \
  -DSD_CUDA=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc

cmake --build . --config Release -j$(nproc)
```

### 8.3 模型目录

```bash
mkdir -p /media/lz/baba/model/sd
```

### 8.4 启动（需先停 llama-server 释放显存）

```bash
# 1. 停 llama-server
pkill -f llama-server

# 2. 跑图
/media/lz/baba/stable-diffusion.cpp/build/bin/sd \
  -m /media/lz/baba/model/sd/sd_xl_turbo_1.0_fp16.safetensors \
  -p "a beautiful sunset over mountains, digital art" \
  -o /media/lz/baba/stable-diffusion.cpp/build/output.png \
  --steps 1 \
  -H 512 -W 512

# 3. 跑完再启 llama-server
/media/lz/baba/llama.cpp/build/bin/llama-server \
  -m /media/lz/baba/model/qwen3.5-18b-a3b-reap-coding-heretic-v0.Q4_K_M.gguf \
  -ngl 999 -c 8192 --flash-attn on -t 10 \
  --mlock --cache-type-k q8_0 --cache-type-v q8_0 \
  --host 0.0.0.0 --port 8081
```

**显存策略：** 12GB 显存同时跑 18B LLM + SD 会爆，必须二选一。

---

## 九、llama-cpp-python 安装（Python 绑定）

```bash
# 激活虚拟环境
source /media/lz/baba/by-env/bin/activate

# 安装 llama-cpp-python（硬编码 CUDA，零环境变量）
/media/lz/baba/by-env/bin/python -m pip install llama-cpp-python --no-cache-dir \
  --config-settings=cmake.define.GGML_CUDA=ON \
  --config-settings=cmake.define.GGML_VULKAN=OFF \
  --config-settings=cmake.define.CMAKE_BUILD_TYPE=Release

# 验证
/media/lz/baba/by-env/bin/python -c "from llama_cpp import Llama; print('OK')"
```

---

## 十、常用操作速查

### 启动 llama-server
```bash
/media/lz/baba/llama.cpp/build/bin/llama-server \
  -m /media/lz/baba/model/模型名.gguf \
  -ngl 999 -c 8192 --flash-attn on -t 10 \
  --mlock --cache-type-k q8_0 --cache-type-v q8_0 \
  --host 0.0.0.0 --port 8081
```

### 停止服务
```bash
pkill -f llama-server
```

### 检查显存
```bash
nvidia-smi
```

### 检查依赖完整性
```bash
ldd /media/lz/baba/llama.cpp/build/bin/llama-server | grep "not found"
```

### 重启后恢复 llama-server
```bash
# 1. 确认 CUDA 路径
ls /usr/local/cuda/bin/nvcc

# 2. 直接启动（编译产物持久化，无需重新编译）
/media/lz/baba/llama.cpp/build/bin/llama-server \
  -m /media/lz/baba/model/qwen3.5-18b-a3b-reap-coding-heretic-v0.Q4_K_M.gguf \
  -ngl 999 -c 8192 --flash-attn on -t 10 \
  --mlock --cache-type-k q8_0 --cache-type-v q8_0 \
  --host 0.0.0.0 --port 8081
```

---

## 十一、故障排查

| 现象 | 原因 | 解决 |
|------|------|------|
| `cudaMalloc failed: out of memory` | 显存不足 | 降 `-c` 到 4096/2048，或加 `--cache-type-k q4_0` |
| `nvcc: command not found` | CUDA 路径不对 | 用 `/usr/local/cuda/bin/nvcc` 绝对路径 |
| `failed to fit params to free device memory` | -ngl 设太高 | 用 `-ngl 999` 让程序自动适配 |
| `File Not Found` (API 404) | 新版 llama-server 无内置前端 | 使用 API 客户端或外部 WebUI |
| 编译很慢 | make -j 数太多 | 改用 `-j4` 或 `-j6` |
| 模型加载后 token/s 很低 | GPU 层太少 | 增大 `-ngl`，或减小 `-c` 省显存 |

---

## 十二、模型来源（HuggingFace）

| 模型 | 用途 | 大小 |
|------|------|------|
| qwen3.5-18b-a3b-reap-coding-heretic-v0.Q4_K_M.gguf | 代码辅助 | ~10GB |
| Huihui-Qwen3-Coder-30B-A3B-Instruct-abliterated.i1-Q4_K_M.gguf | 代码（30B） | ~17GB |
| Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ3_M.gguf | 通用（35B） | ~13GB |
| ggml-base.bin (whisper) | 语音转文字 | 74MB |
| sd_xl_turbo_1.0_fp16.safetensors | 文生图 | 6.9GB |

---

*文档生成日期：2026-06-11*
*适用硬件：NVIDIA RTX 3060 12GB / 32GB RAM / 1TB NVMe*

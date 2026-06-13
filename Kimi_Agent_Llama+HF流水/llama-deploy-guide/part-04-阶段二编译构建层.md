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

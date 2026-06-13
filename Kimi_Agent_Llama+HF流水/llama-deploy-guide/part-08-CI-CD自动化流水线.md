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

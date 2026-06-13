
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


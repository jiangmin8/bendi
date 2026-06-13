#!/bin/bash
# ============================================================
# deploy.sh - Llama.cpp 推理服务一键部署脚本
# 用法: ./deploy.sh {start|stop|restart|status|logs|update|build}
#
# 环境变量 (.env 文件):
#   HF_TOKEN           - Hugging Face Token (下载 gated 模型需要)
#   CUDA_VISIBLE_DEVICES - 指定 GPU (默认: 0)
#   LLAMA_PORT         - 服务端口 (默认: 8080)
#   GPU_LAYERS         - GPU 卸载层数 (默认: 999)
#   CTX_SIZE           - 上下文长度 (默认: 32768)
#   PARALLEL           - 并发槽位 (默认: 4)
#   API_KEY            - API 认证密钥 (可选)
#   GRAFANA_PASSWORD   - Grafana 密码 (默认: admin)
# ============================================================

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="llama-infra"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/.env"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

# --------------------------------------------------
# 依赖检查
# --------------------------------------------------
check_deps() {
    log_step "检查依赖..."
    
    command -v docker >/dev/null 2>&1 || {
        log_error "Docker 未安装"
        log_info "安装指南: https://docs.docker.com/engine/install/"
        exit 1
    }
    
    command -v docker-compose >/dev/null 2>&1 || {
        log_error "docker-compose 未安装"
        log_info "安装: pip install docker-compose"
        exit 1
    }
    
    # 检查 Docker 服务
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker 服务未运行"
        log_info "请启动 Docker: sudo systemctl start docker"
        exit 1
    fi
    
    # 检查 NVIDIA Docker 支持
    if docker info 2>/dev/null | grep -q "nvidia"; then
        log_info "NVIDIA Docker 运行时已启用 ✓"
    else
        log_warn "NVIDIA Docker 运行时未检测到"
        log_warn "GPU 加速可能不可用，将回退到 CPU 模式"
        log_warn "如需 GPU 支持，请安装 nvidia-docker2:"
        log_warn "  https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
    fi
    
    # 检查 curl
    command -v curl >/dev/null 2>&1 || {
        log_warn "curl 未安装，健康检查可能不可用"
    }
}

# --------------------------------------------------
# 环境配置
# --------------------------------------------------
setup_env() {
    # 加载 .env 文件
    if [ -f "$ENV_FILE" ]; then
        log_info "加载环境变量: $ENV_FILE"
        set -a
        source "$ENV_FILE"
        set +a
    else
        log_warn ".env 文件不存在，使用默认配置"
        log_info "提示: 复制 .env.example 到 .env 并修改配置"
    fi
    
    # 设置默认值
    export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
    export LLAMA_PORT="${LLAMA_PORT:-8080}"
    export GPU_LAYERS="${GPU_LAYERS:-999}"
    export CTX_SIZE="${CTX_SIZE:-32768}"
    export BATCH_SIZE="${BATCH_SIZE:-2048}"
    export UBATCH_SIZE="${UBATCH_SIZE:-512}"
    export PARALLEL="${PARALLEL:-4}"
    export HTTP_THREADS="${HTTP_THREADS:-4}"
    export BATCH_THREADS="${BATCH_THREADS:-4}"
    export TIMEOUT="${TIMEOUT:-300}"
    export GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"
    export GRAFANA_USER="${GRAFANA_USER:-admin}"
    export PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
    export GRAFANA_PORT="${GRAFANA_PORT:-3000}"
}

# --------------------------------------------------
# 目录准备
# --------------------------------------------------
setup_dirs() {
    log_step "准备目录结构..."
    
    mkdir -p "$SCRIPT_DIR"/{models,logs,monitoring,nginx/ssl}
    
    # 创建默认 models.ini（如果不存在）
    if [ ! -f "$SCRIPT_DIR/models/models.ini" ]; then
        log_info "创建默认 models.ini..."
        cat > "$SCRIPT_DIR/models/models.ini" << 'EOF'
; ========================================
; 多模型路由配置
; 格式: [模型名称] = API 调用时的 model 参数
; ========================================

[*]
n-gpu-layers = 999
ctx-size = 32768
batch-size = 2048
parallel = 4

; 默认模型（必须有一个 default）
[default]
model = /models/default.gguf
chat-template = llama3

; 嵌入模型示例 (取消注释使用)
; [bge-embed]
; model = /models/bge-m3-Q4_K_M.gguf
; embedding = true
; pooling = cls
EOF
    fi
    
    # 创建占位模型文件（提示用户替换）
    if [ ! -f "$SCRIPT_DIR/models/default.gguf" ]; then
        log_warn "模型文件不存在: models/default.gguf"
        log_info "请放置你的 GGUF 模型文件到 models/ 目录"
        log_info "或修改 models/models.ini 指向正确的模型路径"
        
        # 创建一个空的占位文件，避免 Docker 挂载错误
        touch "$SCRIPT_DIR/models/default.gguf"
    fi
}

# --------------------------------------------------
# 启动服务
# --------------------------------------------------
cmd_start() {
    check_deps
    setup_env
    setup_dirs
    
    log_step "启动服务..."
    log_info "项目: $PROJECT_NAME"
    log_info "Compose: $COMPOSE_FILE"
    
    # 构建镜像（首次或 Dockerfile 变更时）
    log_info "构建/更新镜像..."
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" build llama-server
    
    # 启动服务
    log_info "启动容器..."
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    
    # 等待服务就绪
    log_info "等待服务就绪..."
    local retries=30
    local wait_time=2
    local success=false
    
    for i in $(seq 1 $retries); do
        if curl -sf http://localhost:${LLAMA_PORT}/health >/dev/null 2>&1; then
            success=true
            break
        fi
        echo -n "."
        sleep $wait_time
    done
    
    echo ""
    
    if [ "$success" = true ]; then
        log_info "========================================"
        log_info "服务启动成功!"
        log_info "========================================"
        log_info "llama-server API: http://localhost:${LLAMA_PORT}"
        log_info "Prometheus:       http://localhost:${PROMETHEUS_PORT}"
        log_info "Grafana:          http://localhost:${GRAFANA_PORT}"
        log_info "  用户名: ${GRAFANA_USER}"
        log_info "  密码:   ${GRAFANA_PASSWORD}"
        log_info "========================================"
        log_info "快速测试:"
        log_info "  curl http://localhost:${LLAMA_PORT}/v1/models"
        log_info "  curl http://localhost:${LLAMA_PORT}/health"
    else
        log_error "服务启动超时，查看日志:"
        log_info "  ./deploy.sh logs llama-server"
        docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs --tail=50 llama-server
        exit 1
    fi
}

# --------------------------------------------------
# 停止服务
# --------------------------------------------------
cmd_stop() {
    log_step "停止服务..."
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
    log_info "服务已停止"
}

# --------------------------------------------------
# 重启服务
# --------------------------------------------------
cmd_restart() {
    log_step "重启服务..."
    cmd_stop
    sleep 2
    cmd_start
}

# --------------------------------------------------
# 查看状态
# --------------------------------------------------
cmd_status() {
    log_step "服务状态"
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" ps
    
    echo ""
    log_info "资源使用:"
    docker stats --no-stream --format \
        "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" \
        $(docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" ps -q) 2>/dev/null || true
    
    echo ""
    log_info "健康检查:"
    if curl -sf http://localhost:${LLAMA_PORT:-8080}/health >/dev/null 2>&1; then
        log_info "llama-server: 健康 ✓"
        curl -s http://localhost:${LLAMA_PORT:-8080}/health | python3 -m json.tool 2>/dev/null || true
    else
        log_error "llama-server: 不健康 ✗"
    fi
}

# --------------------------------------------------
# 查看日志
# --------------------------------------------------
cmd_logs() {
    local service="${1:-llama-server}"
    local follow="${2:-}"
    
    if [ "$follow" = "-f" ] || [ "$follow" = "follow" ]; then
        docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs -f "$service"
    else
        docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs --tail=100 "$service"
    fi
}

# --------------------------------------------------
# 更新模型（从 Hugging Face 直接加载）
# --------------------------------------------------
cmd_update() {
    local repo="${1:-}"
    local quant="${2:-Q4_K_M}"
    
    if [ -z "$repo" ]; then
        log_error "请指定模型仓库 ID"
        log_info "用法: ./deploy.sh update <repo-id> [quant-type]"
        log_info "示例: ./deploy.sh update meta-llama/Llama-3.1-8B-Instruct Q4_K_M"
        exit 1
    fi
    
    log_step "更新模型: $repo (quant: $quant)"
    
    # 通过临时容器下载并转换
    docker run --rm \
        -e HF_TOKEN="${HF_TOKEN:-}" \
        -v "$SCRIPT_DIR/models:/models" \
        -v hf-cache:/root/.cache/huggingface \
        llama-server:latest \
        bash -c "
            # 直接从 HF 下载 GGUF（如果可用）
            pip install huggingface_hub
            huggingface-cli download $repo --local-dir /models/new-model --include '*.gguf'
        " || {
        log_error "模型更新失败"
        exit 1
    }
    
    log_info "模型更新完成，请更新 models.ini 并重启服务"
}

# --------------------------------------------------
# 重新构建镜像
# --------------------------------------------------
cmd_build() {
    log_step "重新构建镜像..."
    docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" build --no-cache llama-server
    log_info "镜像构建完成"
}

# --------------------------------------------------
# 性能测试
# --------------------------------------------------
cmd_benchmark() {
    local model="${1:-/models/default.gguf}"
    
    log_step "运行性能基准测试..."
    
    # 检查服务是否运行
    if ! curl -sf http://localhost:${LLAMA_PORT:-8080}/health >/dev/null 2>&1; then
        log_error "llama-server 未运行，请先启动服务"
        exit 1
    fi
    
    log_info "测试 prompt processing 速度..."
    curl -s http://localhost:${LLAMA_PORT:-8080}/v1/completions \
        -H "Content-Type: application/json" \
        -d '{
            "prompt": "The capital of France is Paris. The capital of Germany is Berlin. The capital of Italy is Rome.",
            "max_tokens": 1,
            "temperature": 0
        }' | python3 -m json.tool
    
    log_info "测试 token generation 速度..."
    curl -s http://localhost:${LLAMA_PORT:-8080}/v1/completions \
        -H "Content-Type: application/json" \
        -d '{
            "prompt": "Once upon a time",
            "max_tokens": 128,
            "temperature": 0.7,
            "stream": false
        }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
usage = r.get('usage', {})
print(f\"Prompt tokens: {usage.get('prompt_tokens', 'N/A')}\")
print(f\"Completion tokens: {usage.get('completion_tokens', 'N/A')}\")
print(f\"Total tokens: {usage.get('total_tokens', 'N/A')}\")
"
}

# --------------------------------------------------
# API 快速测试
# --------------------------------------------------
cmd_test() {
    local port="${LLAMA_PORT:-8080}"
    
    log_step "API 快速测试"
    
    echo ""
    log_info "1. 健康检查 /health"
    curl -s http://localhost:$port/health | python3 -m json.tool 2>/dev/null || curl -s http://localhost:$port/health
    
    echo ""
    log_info "2. 模型列表 /v1/models"
    curl -s http://localhost:$port/v1/models | python3 -m json.tool 2>/dev/null || echo "(可能需要 API Key)"
    
    echo ""
    log_info "3. Metrics /metrics (前10行)"
    curl -s http://localhost:$port/metrics | head -10
    
    echo ""
    log_info "4. 对话补全 /v1/chat/completions"
    local auth_header=""
    if [ -n "${API_KEY:-}" ]; then
        auth_header="-H \"Authorization: Bearer $API_KEY\""
    fi
    
    curl -s http://localhost:$port/v1/chat/completions \
        -H "Content-Type: application/json" \
        $auth_header \
        -d '{
            "model": "default",
            "messages": [{"role": "user", "content": "Say hello in one word."}],
            "max_tokens": 10,
            "temperature": 0
        }' | python3 -m json.tool
}

# --------------------------------------------------
# 清理资源
# --------------------------------------------------
cmd_clean() {
    log_step "清理资源..."
    read -p "确定要删除所有容器、卷和镜像吗? [y/N] " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        docker-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --rmi all
        docker volume rm -f llama-infra_hf-cache llama-infra_prometheus-data llama-infra_grafana-data 2>/dev/null || true
        log_info "清理完成"
    else
        log_info "取消清理"
    fi
}

# --------------------------------------------------
# 显示帮助
# --------------------------------------------------
show_help() {
    cat << 'EOF'
============================================================
  Llama.cpp 推理服务部署脚本
============================================================

用法: ./deploy.sh <命令> [选项]

命令:
  start           启动所有服务（构建镜像 + 启动容器）
  stop            停止所有服务
  restart         重启所有服务
  status          查看服务状态和资源使用
  logs [服务]     查看服务日志（默认: llama-server）
  logs -f         实时跟踪日志
  test            API 快速测试
  benchmark       性能基准测试
  update <repo>   从 Hugging Face 更新模型
  build           重新构建 Docker 镜像
  clean           清理所有容器、卷和镜像（危险！）
  help            显示此帮助信息

环境变量 (可在 .env 文件中设置):
  HF_TOKEN              Hugging Face Token
  CUDA_VISIBLE_DEVICES  GPU 设备号 (默认: 0)
  LLAMA_PORT            服务端口 (默认: 8080)
  GPU_LAYERS            GPU 卸载层数 (默认: 999)
  CTX_SIZE              上下文长度 (默认: 32768)
  PARALLEL              并发槽位 (默认: 4)
  API_KEY               API 认证密钥
  GRAFANA_PASSWORD      Grafana 密码 (默认: admin)

示例:
  # 首次部署
  cp .env.example .env
  # 编辑 .env 文件设置 HF_TOKEN
  ./deploy.sh start

  # 查看日志
  ./deploy.sh logs
  ./deploy.sh logs -f

  # API 测试
  ./deploy.sh test

  # 性能测试
  ./deploy.sh benchmark

  # 从 Hugging Face 加载新模型
  ./deploy.sh update unsloth/Llama-3.2-1B-Instruct-GGUF Q4_K_M

============================================================
EOF
}

# --------------------------------------------------
# 主入口
# --------------------------------------------------
main() {
    case "${1:-help}" in
        start)      cmd_start ;;
        stop)       cmd_stop ;;
        restart)    cmd_restart ;;
        status)     setup_env && cmd_status ;;
        logs)       cmd_logs "${2:-llama-server}" "${3:-}" ;;
        test)       setup_env && cmd_test ;;
        benchmark)  setup_env && cmd_benchmark "${2:-}" ;;
        update)     cmd_update "${2:-}" "${3:-Q4_K_M}" ;;
        build)      cmd_build ;;
        clean)      cmd_clean ;;
        help|--help|-h) show_help ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"

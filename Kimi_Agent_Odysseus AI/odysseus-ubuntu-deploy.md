# Odysseus Ubuntu 完美部署指南

> 基于项目源码级分析编写，覆盖所有已知陷阱与依赖细节。

---

## 一、环境要求

| 项目 | 最低要求 | 推荐 |
|------|---------|------|
| Ubuntu | 20.04 LTS | 22.04/24.04 LTS |
| Python | 3.11 | 3.12 |
| Docker | 20.10+ | 最新版 |
| Docker Compose | v2+ | 最新版 |
| CPU | 任意 | 4核+ |
| RAM | 4GB（仅Web功能） | 16GB+（本地模型） |
| 存储 | 10GB | 50GB+（含模型） |
| GPU | 无（CPU 可用） | NVIDIA/AMD（本地模型加速） |

---

## 二、部署前准备

### 2.1 系统依赖安装

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装基础工具链
sudo apt install -y \
    git \
    curl \
    wget \
    tmux \
    build-essential \
    cmake \
    nodejs \
    npm \
    openssh-client

# tmux 是 Cookbook 模块的硬性依赖（后台下载/部署模型用）
# nodejs/npm 用于浏览器 MCP 服务器（可选但建议安装）
```

### 2.2 Docker 安装（如未安装）

```bash
# 移除旧版本
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y $pkg 2>/dev/null
done

# 安装 Docker 官方源
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 验证
sudo docker run hello-world
sudo docker compose version  # 应显示 v2.x.x
```

### 2.3 用户权限配置

```bash
# 将当前用户加入 docker 组（免 sudo 运行 docker）
sudo usermod -aG docker $USER

# 获取当前用户的 UID/GID（docker-compose.yml 中 PUID/PGID 会用到）
id -u  # 记下此值，默认 1000
id -g  # 记下此值，默认 1000

# 重新登录使权限生效
newgrp docker
```

---

## 三、方案 A：Docker Compose 部署（推荐）

> 最稳定、最完整。自动包含 ChromaDB + SearXNG + ntfy，一键启动所有服务。

### 3.1 拉取代码

```bash
cd ~  # 或你想要的安装目录
git clone https://github.com/pewdiepie-archdaemon/odysseus.git
cd odysseus
```

### 3.2 环境配置

```bash
# 复制环境模板
cp .env.example .env
```

编辑 `.env` 文件，至少配置以下项：

```bash
# === 必改项 ===

# 如果你有 OpenAI API Key（可选，用于 GPT 模型）
OPENAI_API_KEY=sk-your-key-here

# 如果你有 Ollama 在宿主机运行（可选，用于本地模型）
# 先确保 Ollama 监听所有接口：OLLAMA_HOST=0.0.0.0:11434 ollama serve
OLLAMA_BASE_URL=http://host.docker.internal:11434/v1

# 绑定地址 — 保持 127.0.0.1 仅本机访问；改为 0.0.0.0 开放局域网
APP_BIND=127.0.0.1
APP_PORT=7000

# 管理员账户（首次启动时会自动创建）
ODYSSEUS_ADMIN_USER=admin
ODYSSEUS_ADMIN_PASSWORD=你的强密码

# PUID/PGID — 必须与宿主机用户一致，否则数据目录权限会崩
PUID=1000
PGID=1000

# === 可选项 ===

# 启用 HTTPS cookies（如果走反向代理）
SECURE_COOKIES=false

# 上传大小限制（单位：字节，10MB = 10485760）
ODYSSEUS_CHAT_UPLOAD_MAX_BYTES=10485760

# 嵌入模型配置（默认 fastembed ONNX，首次运行自动下载约 50MB）
EMBEDDING_URL=
EMBEDDING_MODEL=
FASTEMBED_MODEL=sentence-transformers/all-MiniLM-L6-v2
```

### 3.3 启动服务

```bash
# 构建并启动所有服务（-d 后台运行）
docker compose up -d --build

# 如需安装可选依赖（PyMuPDF PDF 查看、Office 文档提取等，AGPL 协议）
# docker compose build --build-arg INSTALL_OPTIONAL=true
# docker compose up -d
```

### 3.4 验证启动

```bash
# 查看所有容器状态
docker compose ps

# 应有 4 个容器运行：
# - odysseus    (Web UI)
# - chromadb    (向量数据库)
# - searxng     (搜索引擎)
# - ntfy        (通知服务)

# 查看 Odysseus 日志（关键：找管理员临时密码）
docker compose logs --tail=50 odysseus

# 看是否有类似输出：
# [ok] Admin user 'admin' created with temporary password: xxxxxxxx

# 检查 SearXNG 健康状态（这是已知故障点）
docker compose logs searxng | tail -20
```

### 3.5 访问

```
浏览器打开：http://localhost:7000
账号：admin（或你在 ODYSSEUS_ADMIN_USER 中设置的）
密码：你在 ODYSSEUS_ADMIN_PASSWORD 中设置的（或日志中的临时密码）
```

### 3.6 Docker 常用操作

```bash
# 停止
docker compose down

# 停止并删除数据卷（清空所有数据，谨慎使用）
docker compose down -v

# 重启
docker compose restart

# 查看实时日志
docker compose logs -f odysseus

# 更新（拉取最新代码后重建）
git pull
docker compose down
docker compose up -d --build
```

---

## 四、方案 B：原生 Python 部署（轻量级）

> 适合不想用 Docker 的用户。需要手动安装 ChromaDB，无 SearXNG 搜索。

### 4.1 系统依赖

```bash
sudo apt update
sudo apt install -y \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    git \
    tmux \
    build-essential \
    cmake \
    nodejs \
    npm

# 验证 Python 版本
python3.12 --version  # 必须 >= 3.11
```

### 4.2 虚拟环境

```bash
cd ~
git clone https://github.com/pewdiepie-archdaemon/odysseus.git
cd odysseus

python3.12 -m venv venv
source venv/bin/activate

# 确认在虚拟环境中
which python  # 应显示 .../odysseus/venv/bin/python
```

### 4.3 安装 Python 依赖

```bash
# 核心依赖
pip install --no-cache-dir -r requirements.txt

# 可选依赖（推荐安装）
pip install --no-cache-dir -r requirements-optional.txt
```

### 4.4 ⚠️ 关键陷阱：ChromaDB 包冲突

```bash
# 致命陷阱：不能同时安装 chromadb-client 和 chromadb
# 如果你之前安装过 chromadb-client（requirements.txt 默认安装了它），
# 需要卸载它并安装完整版 chromadb：

pip uninstall chromadb-client -y
pip install --force-reinstall chromadb

# 验证：确保没有 chromadb-client
pip list | grep chroma  # 应该只显示 chromadb，没有 chromadb-client
```

### 4.5 安装 ChromaDB 服务

```bash
# 方式 1：Docker 运行 ChromaDB（推荐，最省心）
docker run -d \
    --name chromadb \
    -p 127.0.0.1:8100:8000 \
    -v chromadb-data:/chroma/chroma \
    -e ANONYMIZED_TELEMETRY=FALSE \
    --restart unless-stopped \
    chromadb/chroma:latest

# 方式 2：pip 安装并手动运行（不推荐，容易出环境冲突）
# pip install chromadb
# chroma run --path ./data/chroma --port 8100
```

### 4.6 环境配置

```bash
cp .env.example .env
```

编辑 `.env`：

```bash
# 指向 Docker 运行的 ChromaDB
CHROMADB_HOST=localhost
CHROMADB_PORT=8100

# SearXNG — 如果没有部署 SearXNG，保持默认但搜索功能不可用
SEARXNG_INSTANCE=http://localhost:8080

# 管理员密码
ODYSSEUS_ADMIN_PASSWORD=你的强密码

# 绑定 — 127.0.0.1 仅本机，0.0.0.0 开放局域网（注意安全）
APP_BIND=127.0.0.1
APP_PORT=7000
```

### 4.7 运行初始化

```bash
python setup.py
# 输出应显示：
#   [ok] data/
#   [ok] Database initialized
#   [ok] Admin user 'admin' created
```

### 4.8 启动服务

```bash
python -m uvicorn app:app --host 127.0.0.1 --port 7000

# 或使用 tmux 后台运行
tmux new-session -d -s odysseus "python -m uvicorn app:app --host 127.0.0.1 --port 7000"

# 查看
tmux attach -t odysseus
```

---

## 五、方案 C：systemd 服务部署（生产推荐）

> 适合长期运行，开机自启，自动重启。

基于方案 B（原生 Python），添加 systemd 管理：

```bash
# 创建 systemd 服务文件
sudo tee /etc/systemd/system/odysseus.service > /dev/null << 'EOF'
[Unit]
Description=Odysseus AI Workspace
After=network.target

[Service]
Type=simple
User=ubuntu                    # 改为你的用户名
Group=ubuntu                   # 改为你的用户组
WorkingDirectory=/home/ubuntu/odysseus  # 改为你的安装路径
Environment=PATH=/home/ubuntu/odysseus/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=DATABASE_URL=sqlite:////home/ubuntu/odysseus/data/app.db
Environment=CHROMADB_HOST=localhost
Environment=CHROMADB_PORT=8100
Environment=SEARXNG_INSTANCE=http://localhost:8080
Environment=AUTH_ENABLED=true
Environment=ODYSSEUS_ADMIN_USER=admin
Environment=PYTHONUNBUFFERED=1
ExecStart=/home/ubuntu/odysseus/venv/bin/uvicorn app:app --host 127.0.0.1 --port 7000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 重载、启用、启动
sudo systemctl daemon-reload
sudo systemctl enable odysseus
sudo systemctl start odysseus

# 查看状态
sudo systemctl status odysseus

# 查看日志
sudo journalctl -u odysseus -f
```

---

## 六、GPU 支持配置（NVIDIA）

### 6.1 宿主机安装 NVIDIA Container Toolkit

```bash
# 安装工具包
sudo apt install -y nvidia-container-toolkit

# 配置 Docker 使用 nvidia 运行时
sudo nvidia-ctk runtime configure --runtime=docker

# 重启 Docker
sudo systemctl restart docker

# 验证 GPU 是否可用
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

### 6.2 Odysseus Docker GPU 启用

```bash
cd ~/odysseus

# 使用项目提供的诊断脚本
./scripts/check-docker-gpu.sh

# 或手动启用：编辑 .env，添加
COMPOSE_FILE=docker-compose.yml:docker/gpu.nvidia.yml

# 重建并启动
docker compose down
docker compose up -d --build

# 验证 GPU 是否传入容器
docker compose exec odysseus nvidia-smi -L
```

### 6.3 在 Cookbook 中安装 GPU 推理后端

启动 Odysseus 后，在 Web UI 中：

1. 进入 **Cookbook** → **Dependencies**
2. 安装 llama-cpp-python（CUDA 版本）或 vLLM
3. 在 **Cookbook** → **Settings** → **Servers** 中配置 GPU 参数

---

## 七、常见问题与陷阱（必读）

### 7.1 chromadb-client 冲突（★★★★★ 最致命）

**现象**：应用启动正常，但 Memory/Skills 功能报错或沉默失败。

**根因**：`chromadb-client`（轻量 HTTP 客户端）和 `chromadb`（完整版）不能共存。

**修复**：
```bash
pip uninstall chromadb-client -y
pip install --force-reinstall chromadb
```

### 7.2 SearXNG 版本锁定（Docker 方案）

**现象**：docker compose 启动时 searxng 容器反复重启。

**根因**：上游 `searxng:latest` 标签有 `KeyError: 'default_doi_resolver'` bug。

**项目已修复**：docker-compose.yml 中已锁定到稳定版本 `searxng:2026.5.31-7159b8aed`，**不要手动改为 latest**。

### 7.3 权限问题（data/ 目录）

**现象**：文件上传失败、设置无法保存、技能提取报错 `EPERM`。

**修复**：
```bash
# Docker 方案：确保 PUID/PGID 与宿主机一致
docker compose down
sudo chown -R $(id -u):$(id -g) ./data ./logs
docker compose up -d

# 原生方案：
chmod 755 data/
```

### 7.4 端口冲突

| 端口 | 用途 |
|------|------|
| 7000 | Odysseus Web UI |
| 8080 | SearXNG |
| 8091 | ntfy |
| 8100 | ChromaDB |
| 11434 | Ollama（如安装） |

**修改**：在 `.env` 中调整 `APP_PORT`、`SEARXNG_INSTANCE` 等。

### 7.5 浏览器 MCP 服务器初始化

**现象**：浏览器 MCP 功能不可用。

**修复**：
```bash
# 在宿主机上预安装 Playwright 和 MCP 包
npx -y @playwright/mcp@latest --version
# 约 300MB，安装完成后重启 Odysseus
```

### 7.6 Ollama 连接（Docker → 宿主机 Ollama）

**现象**：Odysseus 中 Ollama 模型显示离线。

**修复**：
```bash
# Ollama 必须以 0.0.0.0 启动
OLLAMA_HOST=0.0.0.0:11434 ollama serve

# Odysseus .env 中配置
OLLAMA_BASE_URL=http://host.docker.internal:11434/v1
```

### 7.7 Email（Outlook/Office 365）

**已知限制**：当前使用 IMAP/SMTP 密码认证，**不支持 OAuth**。Outlook 和 Microsoft 365 需要 OAuth，因此无法直接使用。建议先用其他邮件提供商（如 Gmail 开启 IMAP）。

### 7.8 Agent 上下文过长（小模型）

**现象**：Agent 模式在 4K/8K 上下文模型上运行缓慢或失败。

**优化**：在 Settings 中减少 Agent 可用工具数量、关闭不必要的记忆注入、使用更大的上下文模型。

---

## 八、配置 LLM 模型

首次登录后，进入 **Settings** 配置模型：

### 方式 1：OpenAI API（最简单）
1. Settings → Providers → Add OpenAI
2. 填入 API Key
3. 测试连接 → 保存

### 方式 2：Ollama（本地免费）
1. 宿主机安装 Ollama：`curl -fsSL https://ollama.com/install.sh | sh`
2. 拉取模型：`ollama pull llama3.2`（或 qwen2.5 等）
3. Odysseus Settings → Providers → Add Ollama
4. URL: `http://localhost:11434/v1`（原生）或 `http://host.docker.internal:11434/v1`（Docker）

### 方式 3：Cookbook 自动管理（推荐）
1. 进入 **Cookbook**
2. 点击 **Scan Hardware** — 自动检测 GPU/VRAM
3. 浏览推荐模型列表，按 VRAM 适配排序
4. 点击 Download → Serve，一键完成

---

## 九、安全加固

```bash
# 1. 确认 AUTH_ENABLED=true（默认已启用）

# 2. 禁用开放注册
cat data/auth.json | python3 -m json.tool
# 确保 "open_signup": false

# 3. 如果使用反向代理，启用 SECURE_COOKIES
SECURE_COOKIES=true

# 4. 定期备份
crontab -e
# 添加：
# 0 3 * * * tar -czf ~/backups/odysseus-$(date +\%Y\%m\%d).tar.gz ~/odysseus/data/

# 5. 防火墙（如开放 7000 到局域网）
sudo ufw allow from 192.168.1.0/24 to any port 7000
```

---

## 十、快速诊断命令

```bash
# === 所有方案通用 ===

# 完整健康检查
curl http://localhost:7000/health 2>/dev/null || echo "服务未响应"

# 检查数据库
cat data/app.db | sqlite3 - "SELECT COUNT(*) FROM users;"

# 检查磁盘空间
df -h ~/odysseus/data

# 检查内存
free -h

# === Docker 方案专用 ===

# 容器状态
docker compose ps

# 资源占用
docker stats --no-stream

# 进入容器调试
docker compose exec odysseus /bin/sh

# 查看容器内日志
docker compose exec odysseus cat logs/odysseus.log

# === 原生方案专用 ===

# 进程状态
ps aux | grep uvicorn

# 端口监听
ss -tlnp | grep 7000

# 日志
tail -f logs/odysseus.log
```

---

## 附录：目录结构

```
odysseus/
├── data/                    # 所有用户数据（gitignore）
│   ├── app.db              # SQLite 数据库
│   ├── auth.json           # 认证配置
│   ├── chroma/             # ChromaDB 数据
│   ├── uploads/            # 上传文件
│   ├── personal_docs/      # 个人文档
│   ├── huggingface/        # 模型缓存
│   ├── local/              # Cookbook 安装的 CLI
│   └── ssh/                # SSH 密钥
├── logs/                    # 应用日志
├── .env                     # 环境配置（gitignore）
├── docker-compose.yml       # Docker 编排
├── Dockerfile               # 构建定义
├── requirements.txt         # Python 核心依赖
├── requirements-optional.txt # 可选依赖
├── setup.py                 # 初始化脚本
└── app.py                   # FastAPI 入口
```

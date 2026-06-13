# Odysseus 完整部署指南

> Ubuntu 原生 venv 部署，从零到完美落地。

---

## 一、环境准备

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装系统依赖
sudo apt install -y \
    git curl wget tmux \
    build-essential cmake \
    nodejs npm \
    openssh-client \
    python3.12 python3.12-venv python3.12-dev

# 验证 Python 版本
python3.12 --version   # >= 3.11
```

---

## 二、克隆项目

```bash
cd /media/lz/baba   # 或你的目标目录
git clone https://github.com/pewdiepie-archdaemon/odysseus.git
cd odysseus

# 验证文件
ls app.py requirements.txt setup.py
```

---

## 三、创建虚拟环境

```bash
python3.12 -m venv /media/lz/baba/od_env
source /media/lz/baba/od_env/bin/activate

# 验证（必须在 venv 中）
which python   # /media/lz/baba/od_env/bin/python
```

---

## 四、安装 Python 依赖

### 4.1 核心依赖

```bash
pip install --no-cache-dir -r requirements.txt
```

### 4.2 修复 chromadb 冲突（关键步骤）

```bash
pip uninstall chromadb-client -y
pip install --force-reinstall chromadb

# 验证：只能有 chromadb，不能有 chromadb-client
pip list | grep chroma
```

### 4.3 可选依赖

```bash
pip install --no-cache-dir -r requirements-optional.txt
```

---

## 五、环境配置

```bash
cp .env.example .env

# 设置 admin 密码（替换为你自己的）
sed -i 's/# ODYSSEUS_ADMIN_PASSWORD=/ODYSSEUS_ADMIN_PASSWORD=你的强密码/' .env

# 验证
 grep ODYSSEUS_ADMIN_PASSWORD .env
```

---

## 六、初始化数据库

```bash
python setup.py

# 输出应为：
#   [ok] data/
#   [ok] Database initialized
#   [ok] Admin user 'admin' created with temporary password: xxxxxx
# 或交互式输入用户名密码
```

---

## 七、启动服务

### 方式 1：前台运行（调试用）

```bash
cd /media/lz/baba/odysseus && \
source /media/lz/baba/od_env/bin/activate && \
python -m uvicorn app:app --host 127.0.0.1 --port 7000
```

### 方式 2：tmux 后台运行

```bash
tmux new-session -d -s odysseus \
'cd /media/lz/baba/odysseus && source /media/lz/baba/od_env/bin/activate && \
python -m uvicorn app:app --host 127.0.0.1 --port 7000'

# 查看日志
tmux attach -t odysseus
# 退出 tmux（不停止服务）：Ctrl+B 然后 D
```

### 访问

浏览器打开 `http://localhost:7000`

用户名：`admin`（或 setup.py 时自定义的）
密码：setup.py 时设置的

---

## 八、配置 API Provider

### 8.1 OpenRouter（推荐，模型最多）

1. Settings → Endpoints → Add Provider
2. 选 **OpenRouter**
3. API Key：你的 `sk-or-v1-...`
4. Base URL：自动填充 `https://openrouter.ai/api/v1`
5. 点 **Test** → 绿色 ✓ → **Save**
6. 点 **Reload** 加载模型列表

### 8.2 GitHub Copilot（免费额度）

1. Settings → Endpoints → Add Provider
2. 选 **GitHub Copilot**
3. 走 Device Flow 授权（浏览器打开链接，输入设备码）
4. 授权完成 → **Save**

### 8.3 其他 Provider

| Provider | 需要 |
|----------|------|
| OpenAI | API Key (sk-xxx) |
| Anthropic | API Key |
| DeepSeek | API Key |
| Groq | API Key |
| Gemini | API Key |
| xAI | API Key |

---

## 九、配置搜索

Settings → Search → 选择 **SearXNG**（Docker 部署已自带）

如果用 venv 原生部署没有 SearXNG，可选：
- DuckDuckGo（需 `pip install duckduckgo-search`）

---

## 十、导入 Skills

### 方式 1：手动在 UI 创建

1. Skills → **New**
2. 填 Name、Trigger Words、Content
3. Save

### 方式 2：批量导入（文件方式）

```bash
# 1. 创建 skills 目录结构
mkdir -p /media/lz/baba/odysseus/data/skills/coding-assistant
mkdir -p /media/lz/baba/odysseus/data/skills/concise-mode
mkdir -p /media/lz/baba/odysseus/data/skills/deep-research

# 2. 写入 SKILL.md 文件（示例：coding-assistant）
cat > /media/lz/baba/odysseus/data/skills/coding-assistant/SKILL.md << 'EOF'
---
name: coding-assistant
description: Professional coding assistant. Trigger on code writing, bug fixing, refactoring, code review, or any programming task.
---

# Coding Assistant

## Rules

1. **Simplicity First** - Minimum code that solves the problem
2. **Surgical Changes** - Touch only what you must
3. **Think Before Coding** - State assumptions, ask if uncertain
4. **Goal-Driven** - Define success criteria before coding

## Communication

- Be direct and to the point
- Use markdown code blocks
- Include brief comments for non-obvious logic
EOF

# 3. 重启 Odysseus 生效
# 或刷新 Skills 页面
```

---

## 十一、常用操作

### 停止服务

```bash
pkill -f uvicorn
# 或
tmux kill-session -t odysseus
```

### 重启服务

```bash
tmux kill-session -t odysseus 2>/dev/null
tmux new-session -d -s odysseus \
'cd /media/lz/baba/odysseus && source /media/lz/baba/od_env/bin/activate && \
python -m uvicorn app:app --host 127.0.0.1 --port 7000'
```

### 查看状态

```bash
# 进程
ps aux | grep uvicorn

# 端口
ss -tlnp | grep 7000

# 数据目录
ls -la /media/lz/baba/odysseus/data/
```

### 备份数据

```bash
cd /media/lz/baba/odysseus
tar -czf ~/odysseus-backup-$(date +%Y%m%d).tar.gz data/
```

---

## 十二、常见问题

### Q: chromadb 冲突怎么修？

```bash
pip uninstall chromadb-client -y
pip install --force-reinstall chromadb
```

### Q: 模型显示离线？

- 检查 API Key 是否有效
- Settings → Endpoints → 点 **Test**
- 检查网络连通性

### Q: Agent 不执行工具？

- Settings → Agent → 确认工具已开启
- 检查 Token Budget 是否够用
- 换个更强的模型

### Q: 搜索不能用？

- venv 部署没有自带 SearXNG
- 安装 `duckduckgo-search`：
  ```bash
  pip install duckduckgo-search
  ```
- Settings → Search → 勾选 DuckDuckGo

### Q: 快照盘 baba1 怎么处理？

```bash
sudo umount /media/lz/baba1
sudo lvremove /dev/ubuntu--vg-1/baba-snap
# 输入 y 确认
```

### Q: 日志在哪里？

venv 方式日志输出在终端。如需写文件：

```bash
python -m uvicorn app:app --host 127.0.0.1 --port 7000 > logs/odysseus.log 2>&1
```

---

## 十三、项目结构速查

```
odysseus/
├── data/                    # 用户数据（备份这个）
│   ├── app.db              # 数据库
│   ├── auth.json           # 认证配置
│   ├── skills/             # Skill 文件
│   ├── uploads/            # 上传文件
│   └── ...
├── logs/                    # 日志
├── venv/                    # Python 虚拟环境
├── .env                     # 环境配置
├── requirements.txt         # 核心依赖
├── requirements-optional.txt # 可选依赖
├── setup.py                 # 初始化脚本
└── app.py                   # FastAPI 入口
```

---

## 十四、安全清单

```bash
# 1. 确认认证开启
grep AUTH_ENABLED .env   # true

# 2. 确认本地绕过关闭
grep LOCALHOST_BYPASS .env   # false

# 3. 检查开放注册
cat data/auth.json | python3 -m json.tool | grep open_signup   # false

# 4. 不要暴露 7000 到公网
# APP_BIND=127.0.0.1

# 5. 定期备份 data/ 目录
```

---

**部署完成，访问 http://localhost:7000 开始使用。**

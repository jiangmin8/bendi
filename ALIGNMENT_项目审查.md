# ALIGNMENT - 项目审查

## 一、项目上下文分析

### 1.1 lz-agent 项目

| 属性 | 描述 |
|------|------|
| **位置** | `/media/lz/baba/lz-agent` |
| **技术栈** | Python 3.12 |
| **框架** | 无外部框架，纯后端工程 |
| **核心模块** | agent, tools, memory, rag, mcp, config |
| **配置方式** | `.env` 文件 + `ConfigRegistry` 类 |
| **测试框架** | pytest |
| **代码质量** | flake8, mypy |

**架构特点：**
- 纯后端工程，无内置 Web UI
- 面向对象设计 + 构造函数依赖注入
- 支持 CLI 和 MCP/HTTP API 两种交互方式
- 模块化设计：工具系统、记忆系统、LLM 后端、RAG、治理层

**目录结构：**
```
lz-agent/
├── src/              # 核心源代码
│   ├── agent/       # Agent 核心逻辑
│   ├── tools/       # 工具系统
│   ├── memory/      # 记忆系统
│   ├── rag/         # RAG 模块
│   ├── mcp/         # MCP 协议
│   └── app.py       # 应用工厂
├── entry/           # 入口层
├── tests/           # 单元测试
├── scripts/         # 脚本（启动、质量检查等）
└── docs/            # 文档
```

### 1.2 openhuman 项目

| 属性 | 描述 |
|------|------|
| **位置** | `/media/lz/baba/openhuman/source` |
| **技术栈** | Rust (core) + TypeScript/React (frontend) |
| **版本** | 0.61.2 |
| **核心模块** | api, core, openhuman, rpc |
| **配置方式** | `.env` 文件 + `config.toml` |
| **测试框架** | Rust `cargo test` + Vitest |
| **代码质量** | rustfmt, clippy |

**架构特点：**
- Rust 核心 + Tauri 桌面应用框架
- 多模态 AI Agent 平台（记忆树、工作流、多通道）
- 模块化设计：agent, memory, tools, cost, cron, flows 等
- 支持本地 AI 和远程 API 双模式

**目录结构：**
```
openhuman/source/
├── src/              # Rust 核心代码
│   ├── api/         # API 层
│   ├── core/        # 核心系统服务
│   ├── openhuman/   # 业务域逻辑
│   └── rpc/         # RPC 层
├── app/             # React 前端
│   └── src/         # TypeScript 源代码
├── vendor/          # 第三方依赖（tinyagents, tinycortex 等）
├── scripts/         # 脚本（启动、构建等）
└── tests/           # 集成测试
```

### 1.3 模型配置

| 属性 | 路径/值 |
|------|---------|
| **模型存储位置** | `/media/lz/bf/model/` |
| **Chat 模型** | `qwen2.5-1.5b-instruct-q4_k_m.gguf` |
| **Embedding 模型** | `bge-small-en-v1.5-q8_0.gguf` |
| **推理服务器** | `/media/lz/bf/llama.cpp/build/bin/llama-server` |
| **Chat 端口** | 8080 |
| **Embedding 端口** | 8081 |
| **OpenHuman 端口** | 7788 |
| **lz-agent MCP 端口** | 8766 |

### 1.4 启动脚本汇总

**模型启动命令：**
```bash
# Chat 模型
/media/lz/bf/llama.cpp/build/bin/llama-server \
  -m /media/lz/bf/model/qwen2.5-1.5b-instruct-q4_k_m.gguf \
  --host 0.0.0.0 --port 8080 \
  --ctx-size 8192 --threads 8 --n-gpu-layers 0 --no-mmap

# Embedding 模型
/media/lz/bf/llama.cpp/build/bin/llama-server \
  -m /media/lz/bf/model/bge-small-en-v1.5-q8_0.gguf \
  --host 0.0.0.0 --port 8081 \
  --embedding --pooling mean --embd-normalize 2 \
  --ctx-size 8192 --threads 8 --n-gpu-layers 0 --no-mmap
```

**服务启动命令：**
```bash
# lz-agent CLI
cd /media/lz/baba/lz-agent && python3 -m entry.cli

# lz-agent MCP Server
cd /media/lz/baba/lz-agent && MCP_HOST=127.0.0.1 MCP_PORT=8766 python3 -m entry.mcp_server

# OpenHuman Core
cd /media/lz/baba/openhuman/source && ./target/debug/openhuman-core serve
```

## 二、需求理解确认

### 2.1 原始需求

> 在工作区做一个项目审查主要项目 lz-agent 和 openhuman，模型在其他磁盘。需要用到模型启动命令或者其他审查需要可以提前统计好告诉我准备。

### 2.2 边界确认

| 审查范围 | 包含 | 排除 |
|----------|------|------|
| lz-agent 项目 | 架构设计、代码质量、测试覆盖、安全规范 | sglang 子目录（第三方库） |
| openhuman 项目 | 架构设计、代码质量、测试覆盖、安全规范 | vendor 目录（第三方依赖） |
| 模型服务 | 配置文件、启动脚本 | 模型文件本身 |

### 2.3 需求理解

1. **项目审查目标**：对 lz-agent 和 openhuman 两个项目进行全面审查
2. **审查维度**：架构设计、代码质量、测试覆盖、安全规范、配置管理、文档完整性
3. **模型依赖**：两个项目都依赖本地 llama.cpp 模型服务，需要确认启动状态
4. **审查产出**：结构化审查报告，包含问题清单和改进建议

### 2.4 疑问澄清

| 序号 | 问题 | 状态 |
|------|------|------|
| 1 | 是否需要运行测试用例验证功能正确性？ | 需要确认 |
| 2 | 是否需要检查模型服务的实际可用性？ | 需要确认 |
| 3 | 审查重点是代码质量、架构设计还是安全漏洞？ | 全部关注 |
| 4 | 是否需要生成修复建议和改进方案？ | 需要生成 |
| 5 | 是否需要检查两个项目之间的集成点？ | 需要检查 |

## 三、智能决策策略

### 3.1 已识别的不确定性

1. **模型服务状态**：审查时需要确认模型服务是否运行
2. **测试执行范围**：是否需要运行所有测试还是仅关键测试
3. **代码审查深度**：是否需要逐文件审查还是抽样审查

### 3.2 决策优先级

1. **高优先级**：安全漏洞、架构缺陷、配置问题
2. **中优先级**：代码质量、测试覆盖、文档完整性
3. **低优先级**：代码风格、命名规范、代码组织

### 3.3 基于现有信息的决策

1. **审查范围**：全面审查两个项目的核心模块，抽样检查辅助模块
2. **测试策略**：运行单元测试验证核心功能，集成测试视情况执行
3. **安全检查**：重点检查配置文件、API 密钥管理、权限控制
4. **架构评估**：基于现有代码和文档进行静态分析

## 四、关键决策点

### 4.1 需要人工确认的决策

| 决策点 | 选项 |
|--------|------|
| 是否运行模型服务进行集成测试？ | 是 / 否 |
| 审查结果是否需要包含具体修复代码？ | 是 / 否 |
| 是否需要对代码进行性能分析？ | 是 / 否 |

### 4.2 已确定的决策

| 决策点 | 决策 | 依据 |
|--------|------|------|
| 审查框架 | 6A工作流 | 项目规则要求 |
| 审查维度 | 架构、质量、安全、测试、文档 | 标准项目审查框架 |
| 产出物 | 结构化审查报告 | 用户需求 |
| 代码规范检查 | 使用项目自带工具 | 项目已有 check_quality.sh 等脚本 |

---

**文档版本**: v1.0  
**创建时间**: 2026-07-17  
**适用项目**: lz-agent, openhuman
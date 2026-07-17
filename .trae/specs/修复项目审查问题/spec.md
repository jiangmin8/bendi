# 修复项目审查问题 Spec

## Why

依据 `ACCEPTANCE_项目审查.md`、`ALIGNMENT_项目审查.md`、`CONSENSUS_项目审查.md`、`DESIGN_项目审查.md`、`FINAL_项目审查.md`、`TASK_项目审查.md` 六份审查文档的结论，lz-agent 与 openhuman 两个项目共发现 46 个问题（lz-agent 38 个 / openhuman 8 个）。当前问题清单分散、未按修复紧急度排序、缺乏可执行的修复方案。需要统一梳理并按 P1-Px 优先级给出明确的修复建议与方案，便于后续按序落地。

## What Changes

- 汇总两个项目的所有待修复问题，统一编号
- 按 P1（紧急）/ P2（高）/ P3（中）/ P4（低）四级重新排序
- 为每个问题给出具体修复建议与实施方案
- 区分 lz-agent（可立即修复，源码位于 `/media/lz/baba/lz-agent`）与 openhuman（需先安装 Rust 工具链才能验证）
- 标注阻塞性依赖（如 openhuman 测试验证依赖 Rust 环境安装）

## Impact

- Affected specs: 项目审查六件套（ALIGNMENT/CONSENSUS/DESIGN/TASK/ACCEPTANCE/FINAL）
- Affected code:
  - lz-agent: `src/config.py`、`src/tools/tools.py`、`src/agent/local_agent.py`、`src/agent/llm_backend.py`、`src/rag/vector_store.py`、`src/governance.py`、`src/agent/protocol.py`、`tests/test_governance.py`、`tests/test_integration.py`
  - openhuman: `Cargo.toml`、`src/openhuman/socket/`、全项目（Rust 环境验证）
- 不修改任何源代码，仅产出修复计划与方案文档

## 项目情况分析

### lz-agent（评级 B+）
- **优势**：151 个单元测试全部通过；模块化分层清晰；构造函数依赖注入；命令白名单 + 路径安全检查基本到位
- **核心风险**：
  1. 安全层面：命令执行工具仍有边缘风险（shell 拼接、超时过长）
  2. 类型层面：mypy 报告 23 个类型错误，集中在 `config.py`、`tools.py`、`rag/vector_store.py`
  3. 代码质量：装饰器函数与类方法重复定义造成冗余；硬编码中文提示词；多处未使用导入

### openhuman（评级 A-）
- **优势**：领域驱动设计、可嵌入运行时、完善的 RPC 令牌认证（含常量时间比较、文件权限 0o600、公共绑定保护）
- **核心风险**：
  1. 验证盲区：Rust 工具链未安装，无法执行 `cargo check / clippy / test`，测试覆盖处于未验证状态
  2. 安全细节：WebSocket 连接缺少 origin 检查与速率限制
  3. 工程效率：依赖管理复杂、构建时间较长

## ADDED Requirements

### Requirement: 统一优先级分类标准

项目审查问题 SHALL 按 P1-P4 四级分类，映射关系如下：

| 优先级 | 定义 | 对应原 CONSENSUS 严重程度 | 修复时限 |
|--------|------|---------------------------|----------|
| **P1 紧急** | 安全漏洞、阻塞 CI/构建的类型错误、会导致功能异常的配置问题 | Critical / High（安全或阻塞型） | 立即 |
| **P2 高** | 严重的代码质量问题、影响可维护性的架构缺陷、次要安全加固 | High（质量型） | 短期 |
| **P3 中** | 类型注解错误、异常处理改进、硬编码、依赖管理 | Medium | 中期 |
| **P4 低** | 代码风格、未使用导入、行过长、构建优化、i18n、文档优化 | Low | 长期 |

#### Scenario: 优先级判定
- **WHEN** 审查问题属于安全漏洞或阻塞 mypy/cargo check 的错误
- **THEN** 标记为 P1，必须最先修复
- **WHEN** 问题属于代码质量但不会阻塞构建
- **THEN** 标记为 P2 或 P3，按影响范围排序

### Requirement: 修复方案可执行性

每个 P1-P3 问题 SHALL 在 tasks.md 中给出：
1. 具体文件路径与行号范围
2. 修复策略（一句话描述）
3. 验证方式（命令或测试）
4. 依赖项（如有）

## 修复优先级清单（P1-Px）

### P1 - 紧急修复（立即执行）

| 序号 | ID | 项目 | 问题 | 文件 | 修复方案 |
|------|-----|------|------|------|----------|
| P1-1 | LZ-S-001 | lz-agent | 命令执行工具存在潜在安全风险 | `src/tools/tools.py` | 改用 `subprocess.run` 的 `capture_output=True` 替代手动拼接；对 `shlex.split` 结果做白名单二次校验；限制单次执行时长 |
| P1-2 | LZ-C-001 | lz-agent | `ConfigRegistry.__init__` 的 `rag`/`governance` 参数默认值为 None 但类型非可选，导致 mypy 失败 | `src/config.py:84-85` | 将参数类型改为 `Optional[RAGConfig]` / `Optional[GovernanceConfig]`，并在方法内做 None 兜底 |
| P1-3 | LZ-Q-001a | lz-agent | `tools.py` 中 9 个工具方法缺失返回语句（mypy 报错） | `src/tools/tools.py:398-557` | 为每个分支补充显式 `return` 或统一返回 `ToolError` 字符串 |

### P2 - 高优先级修复（短期）

| 序号 | ID | 项目 | 问题 | 文件 | 修复方案 |
|------|-----|------|------|------|----------|
| P2-1 | LZ-Q-001 | lz-agent | 装饰器函数（如 `_read_file_decorated`）仅 `pass`，与 `ToolManager` 类方法重复定义 | `src/tools/tools.py` | 删除装饰器占位函数，统一通过 `ToolManager` 方法注册；更新对应的注册调用 |
| P2-2 | OH-S-001 | openhuman | WebSocket 连接缺少 origin 检查与速率限制 | `src/openhuman/socket/` | 在握手阶段校验 Origin 白名单；引入 token bucket 限流（如 10 req/s/ip） |
| P2-3 | LZ-Q-003 | lz-agent | `LocalAgent._execute_tool` 将所有异常转为字符串，丢失原始异常类型 | `src/agent/local_agent.py` | 区分 `ToolError` 子类，日志保留 traceback，对外仍返回用户友好消息 |

### P3 - 中优先级修复（中期）

| 序号 | ID | 项目 | 问题 | 文件 | 修复方案 |
|------|-----|------|------|------|----------|
| P3-1 | LZ-Q-002 | lz-agent | RAG 模块 10 个类型错误（参数类型不兼容、Optional 不可索引） | `src/rag/vector_store.py:57-84` | 按 Chroma API 实际签名修正类型注解；Optional 集合在使用前做 None 检查后再索引 |
| P3-2 | LZ-Q-004 | lz-agent | `LocalAgent._build_system_prompt` 硬编码中文提示词 | `src/agent/local_agent.py` | 抽取到 `src/agent/prompts/` 资源文件，支持通过配置切换语言 |
| P3-3 | OH-Q-001 | openhuman | 依赖管理复杂，单 Cargo.toml 承载过多功能 | `Cargo.toml` | 将 cost / cron / flows 拆分为独立 workspace crate，feature gate 控制 |
| P3-4 | LZ-Q-007 | lz-agent | `urllib.request.urlopen` 超时 300 秒过长 | `src/agent/llm_backend.py` | 引入 `socket.setdefaulttimeout` 或显式 `timeout=30`，并支持配置覆盖 |

### P4 - 低优先级修复（长期）

| 序号 | ID | 项目 | 问题 | 文件 | 修复方案 |
|------|-----|------|------|------|----------|
| P4-1 | LZ-Q-005 | lz-agent | 多文件未使用导入（F401） | `src/agent/protocol.py`、`src/governance.py`、`src/rag/vector_store.py`、`tests/test_governance.py` | 运行 `autoflake --remove-all-unused-imports` 或手动删除 |
| P4-2 | LZ-Q-006 | lz-agent | `tests/test_integration.py:72` 行过长（136>120） | `tests/test_integration.py` | 拆分为多行字符串或换行 |
| P4-3 | LZ-Q-008 | lz-agent | 缺少国际化支持 | 多个文件 | 引入 `gettext` 或 i18n 库，与 P3-2 协同 |
| P4-4 | OH-Q-002 | openhuman | 测试覆盖未验证（Rust 环境未安装） | 全项目 | 安装 Rust 1.93.0 后执行 `cargo test`，补充失败用例 |
| P4-5 | OH-Q-003 | openhuman | 构建时间较长 | `Cargo.toml` | 引入 `sccache`、`cargo nextest`，开启增量编译 |

## 修复路径建议

### 阶段一（P1，立即）
1. 修复 lz-agent 安全与阻塞性类型错误
2. 验证：`flake8 src/ tests/` + `mypy src/` + `pytest` 全绿

### 阶段二（P2，短期）
1. 重构 lz-agent 工具注册机制
2. 加固 openhuman WebSocket 安全
3. 改进 lz-agent 异常处理

### 阶段三（P3，中期）
1. 修复 lz-agent RAG 类型错误
2. 抽取提示词到资源文件
3. 拆分 openhuman Cargo workspace
4. 收紧网络超时

### 阶段四（P4，长期）
1. 清理未使用导入与代码风格
2. 安装 Rust 环境验证 openhuman
3. 引入构建缓存与 i18n

## 关键约束

1. **源码位置**：lz-agent 源码在 `/media/lz/baba/lz-agent`，openhuman 源码在 `/media/lz/baba/openhuman/source`，均不在当前 `/workspace` 内，本 spec 仅产出修复计划，不直接修改源码
2. **环境依赖**：openhuman 修复验证需要 Rust 1.93.0 + Node.js 24+ + pnpm 10.10.0
3. **回滚保护**：仓库中可能存在用户已有的未提交改动，修复实施时不得回滚这些改动

# Tasks

## 阶段一：P1 紧急修复

- [ ] Task 1: 修复 lz-agent 命令执行工具安全风险（LZ-S-001）
  - [ ] SubTask 1.1: 审查 `src/tools/tools.py` 中 `run_command` 实现，定位 `shlex.split` 与手动拼接位置
  - [ ] SubTask 1.2: 改用 `subprocess.run(..., capture_output=True, timeout=N)`，移除手动 stdout/stderr 拼接
  - [ ] SubTask 1.3: 对 `shlex.split` 结果做白名单二次校验，拒绝未授权命令
  - [ ] SubTask 1.4: 添加超时与异常分支测试，验证 `pytest tests/test_tools.py` 通过

- [ ] Task 2: 修复 lz-agent 配置类型错误（LZ-C-001）
  - [ ] SubTask 2.1: 修改 `src/config.py:84-85`，将 `rag`/`governance` 参数类型改为 `Optional[RAGConfig]` / `Optional[GovernanceConfig]`
  - [ ] SubTask 2.2: 在 `ConfigRegistry.__init__` 内对 None 值做兜底处理或显式延迟初始化
  - [ ] SubTask 2.3: 运行 `mypy src/config.py` 验证无错误

- [ ] Task 3: 修复 lz-agent tools.py 缺失返回语句（LZ-Q-001a）
  - [ ] SubTask 3.1: 定位 `src/tools/tools.py:398, 421, 439, 452, 465, 483, 510, 533, 557` 共 9 处
  - [ ] SubTask 3.2: 为每个分支补充显式 `return` 语句或统一返回 `ToolError` 字符串
  - [ ] SubTask 3.3: 运行 `mypy src/tools/tools.py` 验证 9 个错误全部消除

## 阶段二：P2 高优先级修复

- [ ] Task 4: 重构 lz-agent 工具注册机制（LZ-Q-001）
  - [ ] SubTask 4.1: 删除 `src/tools/tools.py` 中仅 `pass` 的装饰器占位函数（如 `_read_file_decorated`）
  - [ ] SubTask 4.2: 统一通过 `ToolManager` 类方法注册工具，更新调用方
  - [ ] SubTask 4.3: 运行 `pytest` 确保 151 个测试仍全部通过

- [ ] Task 5: 加固 openhuman WebSocket 安全（OH-S-001）
  - [ ] SubTask 5.1: 在 `src/openhuman/socket/` 握手阶段添加 Origin 白名单校验
  - [ ] SubTask 5.2: 引入 token bucket 限流（建议 10 req/s/ip）
  - [ ] SubTask 5.3: 补充对应单元测试（需 Rust 环境就绪后验证）

- [ ] Task 6: 改进 lz-agent 异常处理（LZ-Q-003）
  - [ ] SubTask 6.1: 修改 `src/agent/local_agent.py` 的 `_execute_tool`，区分 `ToolError` 子类
  - [ ] SubTask 6.2: 日志保留完整 traceback，对外返回用户友好消息
  - [ ] SubTask 6.3: 补充异常类型断言测试

## 阶段三：P3 中优先级修复

- [ ] Task 7: 修复 lz-agent RAG 模块类型错误（LZ-Q-002）
  - [ ] SubTask 7.1: 对照 Chroma API 修正 `src/rag/vector_store.py:57-84` 参数类型注解
  - [ ] SubTask 7.2: 对 `list[...] | None` 类型在使用前做 None 检查后再索引
  - [ ] SubTask 7.3: 运行 `mypy src/rag/vector_store.py` 验证 10 个错误消除

- [ ] Task 8: 抽取 lz-agent 硬编码提示词（LZ-Q-004）
  - [ ] SubTask 8.1: 新建 `src/agent/prompts/` 目录，按语言分文件存放提示词
  - [ ] SubTask 8.2: `LocalAgent._build_system_prompt` 改为从资源文件读取
  - [ ] SubTask 8.3: 通过配置项切换语言

- [ ] Task 9: 拆分 openhuman Cargo workspace（OH-Q-001）
  - [ ] SubTask 9.1: 将 `cost`、`cron`、`flows` 拆分为独立 crate
  - [ ] SubTask 9.2: 通过 feature gate 控制启用
  - [ ] SubTask 9.3: 验证 `cargo check` 与 `cargo test` 通过（需 Rust 环境）

- [ ] Task 10: 收紧 lz-agent 网络超时（LZ-Q-007）
  - [ ] SubTask 10.1: `src/agent/llm_backend.py` 中 `urllib.request.urlopen` 显式设置 `timeout=30`
  - [ ] SubTask 10.2: 支持通过环境变量 `LLM_TIMEOUT` 覆盖
  - [ ] SubTask 10.3: 补充超时异常测试

## 阶段四：P4 低优先级修复

- [ ] Task 11: 清理 lz-agent 未使用导入（LZ-Q-005）
  - [ ] SubTask 11.1: 运行 `flake8 --select=F401 src/ tests/` 列出全部未使用导入
  - [ ] SubTask 11.2: 手动或使用 `autoflake --remove-all-unused-imports -i` 清理
  - [ ] SubTask 11.3: 重新运行 `flake8` 确认 F401 全部消除

- [ ] Task 12: 修复 lz-agent 行过长（LZ-Q-006）
  - [ ] SubTask 12.1: 拆分 `tests/test_integration.py:72` 过长行
  - [ ] SubTask 12.2: 运行 `flake8` 确认 E501 消除

- [ ] Task 13: 添加 lz-agent i18n 支持（LZ-Q-008）
  - [ ] SubTask 13.1: 引入 `gettext` 或轻量 i18n 库
  - [ ] SubTask 13.2: 与 Task 8 协同，将所有面向用户字符串纳入 i18n

- [ ] Task 14: 安装 Rust 环境并验证 openhuman 测试（OH-Q-002）
  - [ ] SubTask 14.1: 安装 Rust 1.93.0 工具链
  - [ ] SubTask 14.2: 执行 `cargo check`、`cargo clippy`、`cargo test`
  - [ ] SubTask 14.3: 记录失败用例并补充修复任务

- [ ] Task 15: 优化 openhuman 构建时间（OH-Q-003）
  - [ ] SubTask 15.1: 安装并配置 `sccache`
  - [ ] SubTask 15.2: 引入 `cargo nextest` 加速测试
  - [ ] SubTask 15.3: 开启增量编译与 `CARGO_INCREMENTAL=1`

# Task Dependencies

- Task 2 → Task 3（类型修复需先统一 config 类型基线）
- Task 4 → Task 1（重构工具注册后再加固命令执行更安全）
- Task 7 依赖 Task 2（RAG 类型修复需 config 类型已修正）
- Task 8 与 Task 13 可并行（i18n 与提示词抽取互相独立但需协调）
- Task 5、Task 9、Task 14、Task 15 均依赖 Rust 环境就绪
- Task 11、Task 12 可与任何 P1-P3 任务并行（纯风格清理）

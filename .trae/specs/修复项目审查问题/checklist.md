# Checklist

## P1 紧急修复验证

- [ ] LZ-S-001: `src/tools/tools.py` 的 `run_command` 已改用 `capture_output=True`，不再手动拼接 stdout/stderr
- [ ] LZ-S-001: `shlex.split` 结果经过白名单二次校验
- [ ] LZ-S-001: 已添加单次执行超时限制与对应测试
- [ ] LZ-C-001: `src/config.py:84-85` 的 `rag`/`governance` 参数已改为 `Optional[...]` 类型
- [ ] LZ-C-001: `mypy src/config.py` 无错误
- [ ] LZ-Q-001a: `src/tools/tools.py` 中 9 处缺失返回语句（398/421/439/452/465/483/510/533/557）已补全
- [ ] LZ-Q-001a: `mypy src/tools/tools.py` 无错误
- [ ] P1 整体验证: `flake8 src/ tests/` + `mypy src/` + `pytest` 全部通过

## P2 高优先级修复验证

- [ ] LZ-Q-001: `src/tools/tools.py` 中仅 `pass` 的装饰器占位函数已删除
- [ ] LZ-Q-001: 工具注册统一通过 `ToolManager` 类方法完成
- [ ] LZ-Q-001: `pytest` 151 个测试仍全部通过
- [ ] OH-S-001: `src/openhuman/socket/` 握手阶段已添加 Origin 白名单校验
- [ ] OH-S-001: 已引入 token bucket 限流（约 10 req/s/ip）
- [ ] OH-S-001: 对应单元测试已补充（Rust 环境就绪后验证）
- [ ] LZ-Q-003: `src/agent/local_agent.py` 的 `_execute_tool` 已区分 `ToolError` 子类
- [ ] LZ-Q-003: 日志保留完整 traceback，对外返回用户友好消息

## P3 中优先级修复验证

- [ ] LZ-Q-002: `src/rag/vector_store.py:57-84` 类型注解已按 Chroma API 修正
- [ ] LZ-Q-002: `Optional[list]` 在索引前已做 None 检查
- [ ] LZ-Q-002: `mypy src/rag/vector_store.py` 无错误
- [ ] LZ-Q-004: 提示词已抽取到 `src/agent/prompts/` 资源文件
- [ ] LZ-Q-004: `LocalAgent._build_system_prompt` 从资源文件读取
- [ ] LZ-Q-004: 支持通过配置切换语言
- [ ] OH-Q-001: `cost`/`cron`/`flows` 已拆分为独立 workspace crate
- [ ] OH-Q-001: feature gate 控制启用正常
- [ ] OH-Q-001: `cargo check` 与 `cargo test` 通过（需 Rust 环境）
- [ ] LZ-Q-007: `src/agent/llm_backend.py` 的 `urlopen` 已设置 `timeout=30`
- [ ] LZ-Q-007: 支持通过 `LLM_TIMEOUT` 环境变量覆盖
- [ ] LZ-Q-007: 超时异常测试已补充

## P4 低优先级修复验证

- [ ] LZ-Q-005: `flake8 --select=F401 src/ tests/` 无输出
- [ ] LZ-Q-006: `tests/test_integration.py:72` 行长已 ≤ 120
- [ ] LZ-Q-006: `flake8 --select=E501` 无输出
- [ ] LZ-Q-008: 已引入 i18n 机制（`gettext` 或等效库）
- [ ] LZ-Q-008: 面向用户字符串已纳入 i18n
- [ ] OH-Q-002: Rust 1.93.0 工具链已安装
- [ ] OH-Q-002: `cargo check`、`cargo clippy`、`cargo test` 已执行并记录结果
- [ ] OH-Q-002: 失败用例已补充修复任务
- [ ] OH-Q-003: `sccache` 已安装并配置
- [ ] OH-Q-003: `cargo nextest` 已引入
- [ ] OH-Q-003: 增量编译已开启

## 文档与流程验证

- [ ] 修复完成后 FINAL_项目审查.md 中的问题状态已更新
- [ ] ACCEPTANCE_项目审查.md 中的验收检查清单已重新核对
- [ ] lz-agent 与 openhuman 修复均未回滚用户已有改动
- [ ] 所有 P1 任务完成后立即触发一次完整 `pytest` + `mypy` + `flake8` 回归

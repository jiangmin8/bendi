| Gemma 4 27B | Q4_K_M | ~16 GB | 24 GB | RTX 3090/4090 |

---

## 11. 附录

### A. 目录结构规范

```
llama-infra/
├── docker-compose.yml           # 服务编排
├── Dockerfile                   # 自定义构建
├── deploy.sh                    # 一键部署脚本
├── models/
│   ├── models.ini               # 多模型路由配置
│   ├── llama-3.1-8b-Q4_K_M.gguf
│   └── bge-m3-Q4_K_M.gguf
├── monitoring/
│   ├── prometheus.yml           # Prometheus 配置
│   ├── alert-rules.yml          # 告警规则
│   ├── datasources/             # Grafana 数据源
│   │   └── prometheus.yml
│   └── dashboards/              # Grafana 仪表盘
│       └── llama-server.json
├── nginx/
│   ├── nginx.conf               # 反向代理配置
│   └── ssl/                     # TLS 证书
├── scripts/
│   ├── download-model.py        # 模型下载
│   ├── convert-to-gguf.sh       # 格式转换
│   ├── quantize.sh              # 量化脚本
│   └── benchmark.py             # 性能测试
└── .github/
    └── workflows/
        └── llama-deploy.yml     # CI/CD 流水线
```

### B. 常见问题排查

```bash
# Q1: CUDA out of memory
# 解决: 减少 GPU 层数或量化级别
llama-server --model model.gguf --n-gpu-layers 20  # 只卸载 20 层到 GPU

# Q2: 模型加载缓慢
# 解决: 使用 NVMe SSD，启用 mmap
llama-server --model model.gguf --mmap

# Q3: 并发请求超时
# 解决: 增加 parallel 槽位和超时时间
llama-server --parallel 8 --timeout 600

# Q4: 上下文太长导致 OOM
# 解决: 减小 ctx-size 或 batch-size
llama-server --ctx-size 8192 --batch-size 1024

# Q5: CPU 使用率过高
# 解决: 限制线程数
llama-server --threads 8 --threads-batch 4

# Q6: 不同后端如何选择
# CUDA > Metal > Vulkan > CPU
# 运行时查看可用设备
llama-server --list-devices
```

### C. 参考资源

| 资源 | 链接 | 说明 |
|------|------|------|
| llama.cpp 官方仓库 | https://github.com/ggml-org/llama.cpp | 源码与文档 |
| 构建文档 | https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md | 多后端编译指南 |
| Server API 文档 | https://github.com/ggml-org/llama.cpp/tree/master/examples/server | API 端点参考 |
| Hugging Face GGUF | https://huggingface.co/models?library=gguf | GGUF 模型搜索 |
| GGUF-my-repo | https://huggingface.co/spaces/ggml-org/gguf-my-repo | 在线量化工具 |
| Unsloth GGUF | https://huggingface.co/unsloth | 高质量量化模型 |

---

> **总结**: 本方案构建了一条完整的自动化流水线，从 Hugging Face 模型获取到 llama-server 生产部署，全程基于纯 C++ 推理引擎，无需 Python 运行时。通过 GGUF 格式统一、多后端编译、OpenAI 兼容 API，实现了高效、轻量、易扩展的本地大模型服务架构。

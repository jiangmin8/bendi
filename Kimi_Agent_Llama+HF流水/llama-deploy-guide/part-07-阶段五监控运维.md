```

---

## 7. 阶段五：监控与运维层

### 7.1 Prometheus Metrics

llama-server 原生暴露 Prometheus 格式的监控指标：

```bash
# 获取 metrics
curl -s http://localhost:8080/metrics

# 输出示例：
# llama:tokens_predicted_total 15234
# llama:tokens_predicted_seconds_total 45.23
# llama:prompt_tokens_total 8921
# llama:prompt_seconds_total 12.34
# llama:n_decode_total 15234
# llama:n_busy_slots 2
# llama:n_idle_slots 2
# http_requests_total{method="POST",path="/v1/chat/completions"} 1234
# http_request_duration_seconds{quantile="0.95"} 0.234
```

### 7.2 Prometheus 配置

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'llama-server'
    static_configs:
      - targets: ['llama-server:8080']
    metrics_path: '/metrics'
    scrape_interval: 10s
```

### 7.3 Grafana Dashboard

推荐监控面板：

| Panel | Query | 说明 |
|-------|-------|------|
| 请求速率 | `rate(http_requests_total[5m])` | QPS |
| P95 延迟 | `histogram_quantile(0.95, http_request_duration_seconds)` | 响应延迟 |
| Token 吞吐 | `rate(llama:tokens_predicted_total[5m])` | tokens/second |
| 并发槽位 | `llama:n_busy_slots` | 当前并发请求数 |
| GPU 利用率 | `nvidia_gpu_utilization_gpu[5m]` | GPU 使用率（需 node-exporter） |
| VRAM 使用 | `nvidia_gpu_memory_used_bytes / nvidia_gpu_memory_total_bytes` | 显存使用率 |

### 7.4 健康检查与自动重启

```bash
#!/bin/bash
# healthcheck.sh - 健康检查脚本

HEALTH_URL="http://localhost:8080/health"
MAX_RETRY=3
RETRY=0

while [ $RETRY -lt $MAX_RETRY ]; do
    if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
        echo "[OK] llama-server 健康"
        exit 0
    fi
    RETRY=$((RETRY + 1))
    echo "[WARN] 健康检查失败 ($RETRY/$MAX_RETRY)，等待重试..."
    sleep 5
done

echo "[ERROR] llama-server 不健康，执行重启..."
# systemd 会自动重启
# 或: docker restart llama-server
```

### 7.5 systemd 服务配置

```ini
# /etc/systemd/system/llama-server.service
[Unit]
Description=Llama.cpp Server
After=network.target

[Service]
Type=simple
User=llama
Group=llama

WorkingDirectory=/opt/llama-server
Environment="CUDA_VISIBLE_DEVICES=0"
Environment="GGML_CUDA_NO_PINNED=1"

ExecStart=/usr/local/bin/llama-server \
    --model /opt/models/llama-3.1-8b-Q4_K_M.gguf \
    --host 0.0.0.0 \
    --port 8080 \
    --n-gpu-layers 999 \
    --ctx-size 32768 \
    --parallel 4 \
    --metrics \
    --threads-http 4

ExecStartPre=/usr/local/bin/healthcheck.sh
Restart=on-failure
RestartSec=10

# 资源限制
LimitNOFILE=65536
MemoryMax=32G

[Install]
WantedBy=multi-user.target
```

```bash
# 启用服务
sudo systemctl daemon-reload
sudo systemctl enable llama-server
sudo systemctl start llama-server
sudo systemctl status llama-server

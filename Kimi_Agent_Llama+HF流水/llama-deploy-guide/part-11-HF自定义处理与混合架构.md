
```python
# handler.py - Hugging Face Inference Endpoints 自定义处理程序
# 适用于: transformers/sentence-transformers/diffusers 模型
# 如需 llama.cpp，请使用 Custom Container 模式

from typing import Dict, List, Any


class EndpointHandler:
    """
    HF Inference Endpoints 自定义处理程序
    
    __init__: 端点启动时调用一次，用于加载模型
    __call__: 每个请求调用，data 包含 inputs 和可选参数
    """
    
    def __init__(self, path: str = ""):
        """
        初始化模型和依赖
        
        Args:
            path: 模型权重路径 (HF 自动传入)
        """
        # 加载模型（示例使用 transformers）
        from transformers import pipeline
        
        self.pipeline = pipeline(
            "text-classification",
            model=path,
            device=0  # GPU
        )
        
        # 可加载其他资源
        # self.tokenizer = AutoTokenizer.from_pretrained(path)
        
    def __call__(self, data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        处理推理请求
        
        Args:
            data: 请求体字典，至少包含 "inputs" 键
                  可包含自定义字段用于业务逻辑
        
        Returns:
            推理结果列表或字典
        """
        # 提取输入
        inputs = data.pop("inputs", data)
        
        # === 自定义预处理 ===
        # 示例: 检查输入长度
        if isinstance(inputs, str) and len(inputs) > 4096:
            inputs = inputs[:4096]  # 截断
        
        # === 推理 ===
        results = self.pipeline(inputs)
        
        # === 自定义后处理 ===
        # 示例: 添加置信度阈值过滤
        filtered = [
            r for r in results 
            if r.get("score", 0) > 0.5
        ]
        
        return filtered if filtered else results
```

#### 完整业务示例：带日期判断的情感分析

```python
# handler.py - 带节日判断的自定义情感分析
from typing import Dict, List, Any
from transformers import pipeline
import holidays


class EndpointHandler:
    def __init__(self, path: str = ""):
        self.pipeline = pipeline("text-classification", model=path)
        self.holidays = holidays.US()  # 美国节假日数据
    
    def __call__(self, data: Dict[str, Any]) -> List[Dict[str, Any]]:
        inputs = data.pop("inputs", data)
        date = data.pop("date", None)  # 自定义字段
        
        # 业务规则: 节假日自动返回 "happy"
        if date is not None and date in self.holidays:
            return [{"label": "happy", "score": 1.0}]
        
        # 正常推理
        return self.pipeline(inputs)
```

```python
# requirements.txt（与 handler.py 同目录）
transformers>=4.35.0
holidays>=0.45
```

#### 测试 handler.py 本地开发

```python
#!/usr/bin/env python3
"""本地测试 handler.py"""

# 模拟 HF Endpoint 的加载方式
from handler import EndpointHandler

# 初始化（path 指向本地模型目录）
handler = EndpointHandler(path="./distilbert-base-uncased-emotion")

# 测试非节假日
result_normal = handler({
    "inputs": "I am quite excited about this!",
    "date": "2024-03-15"  # 普通日期
})
print("普通日期:", result_normal)
# 输出: [{'label': 'joy', 'score': 0.998}]

# 测试节假日（美国独立日）
result_holiday = handler({
    "inputs": "Today is a tough day",  # 即使是负面文本
    "date": "2024-07-04"  # 节假日
})
print("节假日:", result_holiday)
# 输出: [{'label': 'happy', 'score': 1.0}]
```

### 9.5 自托管与 HF 云端混合架构

```
                    ┌─────────────────────────┐
                    │      客户端请求           │
                    │   (OpenAI SDK / curl)    │
                    └───────────┬─────────────┘
                                │
                    ┌───────────▼───────────┐
                    │      API Gateway       │
                    │   (Nginx / Kong)       │
                    └───────┬───────┬───────┘
                            │       │
              健康/低负载时   │       │  过载/故障时
                            │       │
                ┌───────────▼───┐   ▼───────────────┐
                │  自托管集群     │   │  HF Endpoint   │
                │  (llama-server)│   │  (溢出/灾备)    │
                │               │   │                │
                │ 主推理节点 × N │   │ Custom Container│
                │               │   │  (llama.cpp)   │
                └───────────────┘   └────────────────┘
                    固定成本          按调用付费
                    低延迟            弹性扩容
```

**溢出策略实现**：

```python
# overflow-router.py - 混合路由示例
import random
import requests

SELF_HOSTED_URL = "http://localhost:8080/v1/chat/completions"
HF_ENDPOINT_URL = "https://api-inference.huggingface.co/models/your-model"
HF_TOKEN = "hf_xxx"


def route_request(payload: dict) -> dict:
    """
    智能路由: 优先自托管，溢出到 HF Endpoint
    """
    # 策略 1: 随机分流 10% 到 HF（用于对比测试）
    if random.random() < 0.1:
        return call_hf_endpoint(payload)
    
    # 策略 2: 优先自托管，失败时 fallback
    try:
        return call_self_hosted(payload, timeout=5)
    except (requests.Timeout, requests.ConnectionError):
        log_warn("自托管超时，切换到 HF Endpoint")
        return call_hf_endpoint(payload)


def call_self_hosted(payload: dict, timeout: int = 30) -> dict:
    """调用自托管 llama-server"""
    resp = requests.post(
        SELF_HOSTED_URL,
        json=payload,
        timeout=timeout
    )
    resp.raise_for_status()
    return resp.json()


def call_hf_endpoint(payload: dict) -> dict:
    """调用 HF Inference Endpoint"""
    resp = requests.post(
        HF_ENDPOINT_URL,
        headers={"Authorization": f"Bearer {HF_TOKEN}"},
        json={"inputs": payload["messages"][-1]["content"]},
        timeout=60
    )
    resp.raise_for_status()
    return resp.json()
```

### 9.6 何时选择哪种方案

| 场景 | 推荐方案 | 理由 |
|------|---------|------|
| 个人开发/原型验证 | HF Inference Endpoints | 5 分钟上线，按调用付费 |
| 企业内部部署（数据敏感） | 自托管 llama-server | 数据不出内网 |
| 高吞吐生产服务 (>100 QPS) | 自托管集群 | 成本可控，延迟低 |
| 低频调用 (<1000次/天) | HF Inference Endpoints | 避免 GPU 闲置成本 |
| 需要自定义 CUDA kernel | 自托管 | 完全控制编译选项 |
| 需要 transformers 生态 | HF Custom Handler | 原生集成 pipeline |
| 需要 GGUF 量化模型 | 自托管 或 HF Custom Container | llama.cpp 原生支持 |

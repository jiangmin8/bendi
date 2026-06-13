#!/bin/bash
# 测试 llama.cpp 不同 ctx-size 的启动脚本

BASE="/media/lz/baba/llama.cpp/build/bin/llama-server \
  -m /media/lz/baba/model/Huihui-Qwen3-Coder-30B-A3B-Instruct-abliterated.i1-Q4_K_M.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  -ngl 25 \
  --threads 8 \
  --chat-template qwen2 \
  --alias qwen-coder"

echo "======== 测试 1: 12K 上下文 ========"
$BASE --ctx-size 12288

# 如果上面的启动成功（没报错），Ctrl+C 停掉，然后把下面的 # 去掉继续测

echo "======== 测试 2: 16K 上下文 ========"
$BASE --ctx-size 16384

echo "======== 测试 3: 20K 上下文 ========"
$BASE --ctx-size 20480

echo "======== 测试 4: 24K 上下文 ========"
$BASE --ctx-size 24576

echo "======== 测试 5: 32K 上下文 ========"
$BASE --ctx-size 32768

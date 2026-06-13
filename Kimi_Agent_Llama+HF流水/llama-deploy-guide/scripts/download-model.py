#!/usr/bin/env python3
"""
模型下载脚本 - 从 Hugging Face Hub 下载模型
适用于 CI/CD 流水线自动化

用法:
    python download-model.py --repo-id meta-llama/Llama-3.1-8B-Instruct --output ./models/hf-model
    HF_TOKEN=xxx python download-model.py --repo-id meta-llama/Llama-3.1-8B-Instruct --output ./models
"""

import os
import sys
import argparse
import time
from pathlib import Path
from huggingface_hub import snapshot_download, hf_hub_download, login
from huggingface_hub.utils import RepositoryNotFoundError, GatedRepoError


def check_hf_auth(token: str | None = None) -> bool:
    """检查 Hugging Face 认证状态"""
    if token:
        try:
            login(token=token)
            print("[INFO] 已使用提供的 Token 登录")
            return True
        except Exception as e:
            print(f"[WARN] Token 登录失败: {e}")
            return False
    
    # 检查环境变量
    env_token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    if env_token:
        try:
            login(token=env_token)
            print("[INFO] 已使用环境变量 HF_TOKEN 登录")
            return True
        except Exception:
            pass
    
    # 检查本地缓存的 token
    try:
        from huggingface_hub import HfApi
        api = HfApi()
        api.whoami()
        print("[INFO] 使用本地缓存的认证信息")
        return True
    except Exception:
        print("[WARN] 未检测到 Hugging Face 认证")
        print("      如需下载 gated 模型，请设置 HF_TOKEN 环境变量")
        return False


def download_model(
    repo_id: str,
    output_dir: str,
    allow_patterns: list[str] | None = None,
    ignore_patterns: list[str] | None = None,
    token: str | None = None,
    resume: bool = True,
) -> str:
    """
    从 Hugging Face Hub 下载模型
    
    Args:
        repo_id: 模型仓库 ID，如 "meta-llama/Llama-3.1-8B-Instruct"
        output_dir: 本地输出目录
        allow_patterns: 允许下载的文件模式
        ignore_patterns: 忽略的文件模式
        token: Hugging Face 访问令牌
        resume: 是否断点续传
    
    Returns:
        下载完成的本地目录路径
    """
    
    print("=" * 60)
    print(f"模型下载: {repo_id}")
    print("=" * 60)
    
    # 认证
    is_authed = check_hf_auth(token)
    
    # 默认下载模式：safetensors 权重 + 配置文件
    if allow_patterns is None:
        allow_patterns = [
            "*.safetensors",
            "*.json",
            "*.txt",
            "*.model",
            "*.py",
            "tokenizer.*",
            "config.*",
            "generation_config.*",
            "preprocessor_config.*",
            "README*",
            "LICENSE*",
        ]
    
    # 默认忽略：大文件
    if ignore_patterns is None:
        ignore_patterns = [
            "*.msgpack",
            "*.h5",
            "*.ot",
            "*.bin",  # 优先 safetensors
        ]
    
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    print(f"[INFO] 输出目录: {output_path.absolute()}")
    print(f"[INFO] 允许模式: {allow_patterns}")
    print(f"[INFO] 忽略模式: {ignore_patterns}")
    
    start_time = time.time()
    
    try:
        downloaded_path = snapshot_download(
            repo_id=repo_id,
            local_dir=str(output_path),
            local_dir_use_symlinks=False,
            allow_patterns=allow_patterns,
            ignore_patterns=ignore_patterns,
            resume_download=resume,
        )
        
        elapsed = time.time() - start_time
        print(f"\n[SUCCESS] 下载完成: {downloaded_path}")
        print(f"[INFO] 耗时: {elapsed:.1f} 秒")
        
        # 显示下载内容摘要
        files = list(output_path.rglob("*"))
        total_size = sum(f.stat().st_size for f in files if f.is_file())
        print(f"[INFO] 文件数: {len([f for f in files if f.is_file()])}")
        print(f"[INFO] 总大小: {total_size / 1024 / 1024 / 1024:.2f} GB")
        
        return downloaded_path
        
    except GatedRepoError:
        print(f"\n[ERROR] 模型 {repo_id} 需要授权访问", file=sys.stderr)
        print("       请执行以下操作:", file=sys.stderr)
        print(f"       1. 访问 https://huggingface.co/{repo_id}", file=sys.stderr)
        print("       2. 点击 'Access repository' 并接受许可", file=sys.stderr)
        print("       3. 设置 HF_TOKEN 环境变量后重试", file=sys.stderr)
        sys.exit(1)
        
    except RepositoryNotFoundError:
        print(f"\n[ERROR] 模型仓库不存在: {repo_id}", file=sys.stderr)
        sys.exit(1)
        
    except Exception as e:
        print(f"\n[ERROR] 下载失败: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="从 Hugging Face Hub 下载模型",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 下载公开模型
  %(prog)s --repo-id google/gemma-2b --output ./models/gemma-2b

  # 下载 gated 模型（需 Token）
  HF_TOKEN=xxx %(prog)s --repo-id meta-llama/Llama-3.1-8B-Instruct --output ./models/llama

  # 仅下载配置文件（不含权重）
  %(prog)s --repo-id meta-llama/Llama-3.1-8B-Instruct --output ./models --no-weights

  # 包含所有文件
  %(prog)s --repo-id stabilityai/stable-diffusion-xl --output ./models/sdxl --allow-all
        """
    )
    
    parser.add_argument("--repo-id", required=True, help="Hugging Face 模型仓库 ID")
    parser.add_argument("--output", required=True, help="本地输出目录")
    parser.add_argument("--token", default=None, help="Hugging Face 访问令牌")
    parser.add_argument("--no-weights", action="store_true", help="不下载权重文件（仅配置）")
    parser.add_argument("--allow-all", action="store_true", help="下载所有文件（不限制模式）")
    parser.add_argument("--no-resume", action="store_true", help="禁用断点续传")
    
    args = parser.parse_args()
    
    # 构建文件模式
    allow_patterns = None
    if args.no_weights:
        allow_patterns = ["*.json", "*.txt", "*.model", "*.py", "README*", "LICENSE*"]
    elif not args.allow_all:
        allow_patterns = None  # 使用默认值
    
    download_model(
        repo_id=args.repo_id,
        output_dir=args.output,
        allow_patterns=allow_patterns,
        token=args.token,
        resume=not args.no_resume,
    )


if __name__ == "__main__":
    main()

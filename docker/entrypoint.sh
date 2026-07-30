#!/bin/bash
# MaxMetagenome Docker Container Entrypoint
# 容器启动时自动激活环境并检查挂载

set -e

echo "=================================================="
echo "MaxMetagenome Platform v1.1.0"
echo "Complete Metagenomics Analysis (Bacteria/Virome/Fungi)"
echo "=================================================="
echo ""

# 激活 Maxmetagenome 环境
echo "⏳ 激活 Conda 环境..."
if [ -f "/home/mgxuser/Maxmetagenome/scripts/activate.sh" ]; then
  source /home/mgxuser/Maxmetagenome/scripts/activate.sh
  echo "✅ 环境已激活: $CONDA_DEFAULT_ENV"
else
  echo "❌ 错误: activate.sh 不存在"
  exit 1
fi

echo ""

# 检查必需挂载
echo "🔍 检查挂载状态..."

DB_MOUNTED=false
PROJECT_MOUNTED=false

# 检查 db/ 目录
if [ ! -d "/home/mgxuser/Maxmetagenome/db" ]; then
  echo "❌ db/ 目录不存在"
elif [ -z "$(ls -A /home/mgxuser/Maxmetagenome/db 2>/dev/null)" ]; then
  echo "⚠️  WARNING: db/ 目录为空或未挂载"
  echo "    数据库是必需的 (1.1 TB)，请使用 -v 挂载:"
  echo "    docker run -v /host/path/to/db:/home/mgxuser/Maxmetagenome/db ..."
else
  DB_MOUNTED=true
  echo "✅ db/ 已挂载"
  # 快速检查关键数据库
  if [ -d "/home/mgxuser/Maxmetagenome/db/metaphlan" ]; then
    echo "   - MetaPhlAn 数据库: ✓"
  fi
  if [ -d "/home/mgxuser/Maxmetagenome/db/humann" ]; then
    echo "   - HUMAnN 数据库: ✓"
  fi
fi

# 检查 Project/ 目录
if [ ! -d "/home/mgxuser/Maxmetagenome/Project" ]; then
  echo "⚠️  WARNING: Project/ 目录不存在或未挂载"
  echo "    项目工作目录建议挂载:"
  echo "    docker run -v /host/path/to/Project:/home/mgxuser/Maxmetagenome/Project ..."
else
  PROJECT_MOUNTED=true
  echo "✅ Project/ 已挂载"
  # 统计项目数量
  project_count=$(find /home/mgxuser/Maxmetagenome/Project -maxdepth 1 -type d | wc -l)
  project_count=$((project_count - 1))  # 减去 Project/ 自身
  if [ $project_count -gt 0 ]; then
    echo "   - 已有项目数: $project_count"
  fi
fi

echo ""

# 显示系统信息
echo "📊 系统信息:"
echo "   - 工作目录: $(pwd)"
echo "   - 用户: $(whoami)"
echo "   - Shell: $SHELL"
echo "   - CPU 核心: $(nproc)"
echo "   - 内存: $(free -h | awk '/^Mem:/ {print $2}')"

echo ""

# 提示下一步
if [ "$DB_MOUNTED" = true ] && [ "$PROJECT_MOUNTED" = true ]; then
  echo "🚀 环境就绪，可以开始分析！"
  echo ""
  echo "📖 快速启动:"
  echo "   1. 编辑配置: vim pipeline/config/config.yaml"
  echo "   2. 启动流程: snakemake -s pipeline/Snakefile --profile profiles/auto"
  echo "   3. 查看文档: cat docs/QUICK_START.md"
elif [ "$DB_MOUNTED" = false ]; then
  echo "⚠️  数据库未挂载，无法运行分析"
  echo "   请使用 -v 挂载数据库后重新启动容器"
else
  echo "⚠️  Project/ 未挂载，结果将保存在容器内（不推荐）"
  echo "   建议挂载宿主机目录以持久化结果"
fi

echo ""
echo "=================================================="
echo ""

# 执行用户命令
exec "$@"

#!/usr/bin/env bash
# 生成/更新 TRACKER.md：克隆状态取自磁盘实际状态，审计状态保留 TRACKER.md 中已有记录
# 用法：bash scripts/gen-tracker.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$ROOT/scripts/repos.list"
TRACKER="$ROOT/TRACKER.md"

# 读取旧 TRACKER 中已登记的审计状态（键：org/repo）
# 表行格式：| [`slug`](url) | path | clone | audit | doc |
declare -A OLD_AUDIT OLD_DOC
if [ -f "$TRACKER" ]; then
  while IFS='|' read -r _ c2 _ _ audit doc _; do
    slug=$(echo "$c2" | sed -n 's/.*`\([^`]*\)`.*/\1/p')
    audit=$(echo "$audit" | xargs); doc=$(echo "$doc" | xargs)
    if [ -n "$slug" ] && [[ "$slug" == */* ]]; then
      OLD_AUDIT["$slug"]="$audit"; OLD_DOC["$slug"]="$doc"
    fi
  done < <(grep '^|' "$TRACKER" | grep 'github.com/')
fi

gen_section() { # $1=标题 $2=类别
  local title="$1" category="$2"
  echo "## $title"; echo
  echo "| 仓库 | 本地路径 | 克隆 | 审计 | 审计文档 |"
  echo "|------|---------|:----:|:----:|---------|"
  while IFS='|' read -r c slug; do
    [ "$c" = "$category" ] || continue
    name="${slug##*/}"
    dest="$ROOT/repos/$category/$name"
    if [ -d "$dest/.git" ]; then clone_st="✅"; path="\`repos/$category/$name\`"
    elif [ -d "$dest" ]; then clone_st="⚠️ 不完整"; path="\`repos/$category/$name\`"
    else clone_st="❌"; path="—"; fi
    audit="${OLD_AUDIT[$slug]:-未开始}"
    doc="${OLD_DOC[$slug]:-}"
    echo "| [\`$slug\`](https://github.com/$slug) | $path | $clone_st | $audit | $doc |"
  done < "$LIST"
  echo
}

{
  echo "# 进度跟踪总表（TRACKER）"
  echo
  echo "> 由 \`bash scripts/gen-tracker.sh\` 生成：**克隆列**始终反映磁盘实际状态；"
  echo "> **审计列/审计文档列**为手工维护（生成脚本不会覆盖已有进度，但请勿改动表格结构）。"
  echo "> 审计状态建议值：\`未开始\` / \`进行中\` / \`已完成\`。"
  echo
  gen_section "一、开源 Agent 主列表（agents，56）" "agents"
  gen_section "二、DARPA AIxCC 2025 决赛 CRS（aixcc）" "aixcc"
  gen_section "三、Skill 库（skills）" "skills"
  gen_section "四、MCP Server（mcp）" "mcp"
  gen_section "五、Benchmark（benchmarks）" "benchmarks"
  gen_section "六、研究代码（research）" "research"
  gen_section "七、Awesome 清单（awesome-lists）" "awesome-lists"
  gen_section "八、模型配套代码（models-code）" "models-code"
  gen_section "九、索引源（landscape）" "landscape"
} > "$TRACKER"

total=$(grep -cE '^[a-z-]+\|' "$LIST")
done_n=$(find "$ROOT/repos" -mindepth 3 -maxdepth 3 -name ".git" | wc -l)
echo "TRACKER.md 已生成：本地仓库 $done_n / 清单 $total"

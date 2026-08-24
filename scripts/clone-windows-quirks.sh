#!/usr/bin/env bash
# 处理 Windows 文件系统限制导致无法 checkout 的仓库
# 方案（已验证）：完整克隆对象到 .git（--no-checkout），然后
#   git -c core.protectNTFS=false archive HEAD | tar -x
# 关闭 NTFS 保护后 git archive 能输出非法路径，tar 解包时自动跳过 NTFS 真正无法创建的文件
# 用法：bash scripts/clone-windows-quirks.sh 类别|org/repo [类别|org/repo2 ...]
set -u
export GIT_TERMINAL_PROMPT=0
export GIT_LFS_SKIP_SMUDGE=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAX_RETRY=3

for arg in "$@"; do
  category="${arg%%|*}"; slug="${arg#*|}"
  name="${slug##*/}"
  dest="$ROOT/repos/$category/$name"
  if [ -d "$dest/.git" ] && [ -n "$(find "$dest" -maxdepth 1 -mindepth 1 -not -name .git -print -quit 2>/dev/null)" ]; then
    echo "[SKIP] $slug 已有工作区文件"; continue
  fi

  echo "[QUIRK] $slug：克隆对象（longpaths）"
  rm -rf "$dest"
  attempt=1; cloned=0
  while [ $attempt -le $MAX_RETRY ]; do
    if timeout 900 git clone -c core.longpaths=true --depth 1 --single-branch --no-checkout \
         "https://github.com/$slug.git" "$dest" > /tmp/quirk_clone_out.txt 2>&1; then
      cloned=1; break
    fi
    grep -vE "Updating|Filtering|Receiving|Resolving|Compressing|Cloning into" /tmp/quirk_clone_out.txt | head -3
    attempt=$((attempt+1)); rm -rf "$dest"; sleep 10
  done
  [ $cloned -eq 1 ] || { echo "[FAIL] $slug 对象克隆失败（网络）"; continue; }

  cd "$dest" || continue
  # --no-checkout 克隆的 HEAD 未落地为本地分支：先建立分支引用
  defbranch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  [ -z "$defbranch" ] && defbranch=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin | head -1 | sed 's|^origin/||')
  git update-ref "refs/heads/$defbranch" "$(git rev-parse refs/remotes/origin/$defbranch)" 2>/dev/null
  git symbolic-ref HEAD "refs/heads/$defbranch"

  git -c core.protectNTFS=false archive HEAD 2>/tmp/quirk_arch_err.txt | tar -x 2>/tmp/quirk_tar_err.txt
  files=$(find . -type f -not -path './.git/*' | wc -l)
  skipped=$(grep -c "Cannot open\|Invalid argument\|File name too long" /tmp/quirk_tar_err.txt 2>/dev/null || echo 0)
  echo "[OK] $slug：解出 $files 个文件（跳过 NTFS 非法名 $skipped 个）"
  cd "$ROOT"
done
echo "完成。"

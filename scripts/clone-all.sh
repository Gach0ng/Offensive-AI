#!/usr/bin/env bash
# 批量克隆 scripts/repos.list 中的仓库（浅克隆，幂等：已存在则跳过）
# 特性：单仓库最多重试 3 次；连续 5 个仓库失败视为网络故障，自动等待 GitHub 恢复可达后继续
# 用法：bash scripts/clone-all.sh
set -u
export GIT_TERMINAL_PROMPT=0
# 代码审计只需要源码：跳过 Git LFS 大文件下载（只留指针文件）
export GIT_LFS_SKIP_SMUDGE=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$ROOT/scripts/repos.list"
LOGDIR="$ROOT/logs"
mkdir -p "$LOGDIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGDIR/clone-$STAMP.log"
STATUS="$LOGDIR/clone-status.tsv"

: > "$STATUS"

# 单仓库克隆超时保护（Git Bash 无 timeout 时自动退化）
TL=""
command -v timeout >/dev/null 2>&1 && TL="timeout 900"

MAX_RETRY=3          # 单仓库重试次数
CONSEC_LIMIT=5       # 连续失败多少个仓库判定为网络故障
WAIT_INTERVAL=30     # 断网时探测间隔（秒）
WAIT_MAX_PROBES=60   # 最多探测次数（60*30s = 30 分钟），超过则放弃退出

probe_net() {
  curl -sI -m 10 https://github.com -o /dev/null 2>/dev/null
}

wait_for_network() {
  local n=0
  while [ $n -lt $WAIT_MAX_PROBES ]; do
    if probe_net; then
      echo "[NET] GitHub 已恢复可达，继续克隆" | tee -a "$LOG"
      return 0
    fi
    n=$((n+1))
    echo "[NET] GitHub 不可达，${WAIT_INTERVAL}s 后重试（$n/$WAIT_MAX_PROBES）" >> "$LOG"
    sleep "$WAIT_INTERVAL"
  done
  echo "[NET] 等待超时，GitHub 持续不可达，退出。稍后重跑本脚本即可续传（幂等）" | tee -a "$LOG"
  return 1
}

clone_one() { # $1=category $2=slug -> 成功返回0
  local category="$1" slug="$2"
  local name="${slug##*/}"
  local dest="$ROOT/repos/$category/$name"
  local attempt=1
  while [ $attempt -le $MAX_RETRY ]; do
    echo "[CLONE] ($attempt/$MAX_RETRY) $slug -> repos/$category/$name" >> "$LOG"
    if $TL git clone --depth 1 --single-branch "https://github.com/$slug.git" "$dest" >> "$LOG" 2>&1; then
      return 0
    fi
    rm -rf "$dest"
    attempt=$((attempt+1))
    sleep 10
  done
  return 1
}

ok=0; skip=0; fail=0; consec=0
while IFS='|' read -r category slug; do
  case "$category" in ''|'#'*) continue ;; esac
  name="${slug##*/}"
  dest="$ROOT/repos/$category/$name"

  if [ -d "$dest/.git" ]; then
    echo -e "SKIP\t$category\t$slug" >> "$STATUS"
    skip=$((skip+1))
    continue
  fi

  if clone_one "$category" "$slug"; then
    echo -e "OK\t$category\t$slug" >> "$STATUS"
    ok=$((ok+1)); consec=0
    echo "[OK] $slug"
  else
    echo -e "FAIL\t$category\t$slug" >> "$STATUS"
    fail=$((fail+1)); consec=$((consec+1))
    echo "[FAIL] $slug（详见 $LOG）"
    if [ $consec -ge $CONSEC_LIMIT ]; then
      consec=0
      echo "[NET] 连续 $CONSEC_LIMIT 个仓库失败，疑似网络故障，开始等待恢复…" | tee -a "$LOG"
      if ! wait_for_network; then
        echo "中断统计：本次成功 $ok / 跳过 $skip / 失败 $fail。日志：$LOG"
        exit 1
      fi
    fi
  fi
done < "$LIST"

echo "" >> "$LOG"
echo "完成：成功 $ok / 跳过 $skip / 失败 $fail。日志：$LOG" | tee -a "$LOG"
echo "状态文件：$STATUS"

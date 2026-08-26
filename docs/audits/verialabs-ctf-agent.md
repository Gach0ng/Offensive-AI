# verialabs/ctf-agent 逐行代码审计

> 审计对象：Veria Labs CTF Agent —— "周末写出，BSidesSF 2026 CTF **52/52 全解冠军（1st, $1,500）**"：Coordinator LLM 管赛事、**每题一个 solver 蜂群（5 模型同跑竞速，先得旗者胜）**、Docker 沙箱隔离、CTFd 全自动闭环（poller 5 秒拉题→解出即提交）。~5.1k 行的冠军级极简。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/verialabs/ctf-agent |
| 本地路径 | `repos/agents/ctf-agent/` |
| 审计基线 commit | `3366d56`（Switch Codex serviceTier to flex） |
| 语言 / 规模 | Python ~5,120 行（backend/ + pull_challenges + sandbox Dockerfile） |
| Landscape 定位 | 类型：渗透 Agent / Stars：中高 / 一句话：多模型竞速蜂群 CTF 冠军系统（52/52 BSidesSF 2026） |
| License | 见仓库 |
| 关联论文 | 无（作者：Veria Labs——CTFTime 2024/25 美国 #1 战队 .;,;.（smiley）成员创立） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：整场 CTF 赛事的完全自主参赛：CTFd 轮询新题→Coordinator 分派→每题蜂群（Opus medium/max + GPT-5.4/5.4-mini/5.3-codex 五模型并行）各自在隔离 Docker 沙箱解题→首个正确旗即全群停。
- **AI 真伪核查**：真 AI（Claude SDK/Codex 双提供商 + Pydantic AI 三类求解器形态）。
- **差异化定位**："**竞速**"作为第一架构原则（pentest-copilot 的 racer 是可选项，这里是默认形态且赢了真实赛事）；作者背景（顶战队成员）体现在提示词与工具选择的实战密度。

## 2. 架构总览

```
CTFd 平台 ←→ Poller(5s) ←→ Coordinator LLM（Claude/Codex 双实现，coordinator_loop 共享事件循环）
   工具：fetch_challenges/get_solve_status/spawn_swarm/check_status/submit_flag/kill_swarm/
        bump_agent(注入 insights)/read_solver_trace(last_n=20)/broadcast
   ▼ 每题
ChallengeSwarm（swarm.py ★ 348）：5 模型 solver 并行
   ├─ 提交闸：try_submit_flag（全局旗去重+ALREADY SOLVED 短路+**逐模型递增冷却 [0,30,120,300,600]s**）
   ├─ 兄弟洞察：_gather_sibling_insights（把其他模型的 findings 注入 bump）
   └─ 配额回退（QUOTA_FALLBACK 表）
Solver（codex_solver 557/claude_solver 385/pydantic solver）：各自沙箱内 bash+view_image+webhook+submit_flag
LoopDetector（loop_detect.py ★ 59）：12 窗口签名去重，3 次 warn/5 次 break+改道建议消息
Sandbox：Docker 隔离（pwntools/r2/gdb/angr/pyghidra 预装；host.docker.internal 连接重写）
```

## 3. 核心模块精读（审计主体）

### 3.1 提示词（prompts.py 181 行全文亲读）——程序化拼装的单题系统提示

- **FIRST ACTION 强制**（有连接信息时）："你的第一个工具调用**必须**连接服务——不要先探索沙箱文件系统，flag 在服务上不在容器里"+ **nc 的 heredoc/pwntools 教学**（"每次 bash 是新进程，多行交互用 heredoc 或写 socket/pwntools 脚本"——与 pentest-copilot 同款实战教学）。
- **连接信息本地重写**：`localhost/127.0.0.1 → host.docker.internal`（桥接网络的透明适配——模型无需知道网络拓扑）。
- **附件类型感知提示**：图片附件在"有命名工具"形态标"**立即调 view_image**（损坏先修 magic bytes）"、bash-only 形态标 exiftool/steghide/zsteg 路线——**同一提示词按求解器形态分支**（Pydantic AI 有离散工具/Claude SDK 仅 bash/Codex 动态工具）。
- **pyghidra 代码模板内联**（RE/pwn/misc 类或含二进制附件时）：三行 open_program 示例直接可跑；"Also available: r2/gdb/angr/capstone"。
- 指令收尾："**Use tools immediately. Do not describe — execute**"；占位旗黑名单；"Do not guess. Do not ask. Cover maximum surface area."；Pwn 的 `stty raw -echo` 前置；XSS/SSRF 用 webhook（形态分支：webhook_create 工具 vs curl webhook.site）。

### 3.2 蜂群与提交闸（swarm.py 关键段亲读）

- **递增冷却的提交闸**：错误提交按模型计数，冷却阶梯 [0, 30s, 2min, 5min, 10min]——冷却消息明说"**用这段时间做更深入的分析并验证你的旗**"（把惩罚转化为引导）；全局 `_submitted_flags` 集合跨模型去重（五模型不许重复交同一错旗）；**ALREADY SOLVED 短路**（别群模型后到者立即停止）。
- **兄弟洞察注入**（bump_agent 工具）：Coordinator 可读某 solver 的 trace（last_n=20）并广播 insights 到其他模型——**蜂群间的单向信息流**（先发现者的线索成为后进者的起点）。
- QUOTA_FALLBACK（配额耗尽自动换模型）；五模型规格含努力层级（Opus medium/max 两档）。

### 3.3 循环检测（loop_detect.py 59 行全文亲读）

- 12 窗口工具调用**签名**（tool+args 前 500 字符 JSON）计数：同签名 ≥3 warn/≥5 break——**warn/break 双阈值**；break 消息是改道建议而非纯警告："如果刚才在 grep，改写 Python 脚本；如果在分析文件的一个方面，换一个方面——**还有哪些角度没探索？**"（与 Guardian 哲学同款：纠偏要给方向）。

### 3.4 Coordinator（coordinator_core/loop 结构亲读）

- 九个编排工具（拉题/状态/spawn/查/提交/杀群/**bump 注洞察**/读 trace/广播）；Claude SDK 与 Codex 双实现共享事件循环（5s 轮询+60s 状态汇报）；成本追踪贯穿。

## 4. 值得借鉴的设计与技巧

1. **递增冷却的提交闸**（错误提交→0/30/120/300/600s，冷却期消息引导深度验证+跨模型旗去重+先到短路）——"防瞎猜"与"引导验证"的合体，CTF/赏金提交节流的直接可抄实现。
2. **多模型竞速+兄弟洞察**：默认五模型并行、先得者胜、Coordinator 主动把一模型的发现 bump 给 others——竞速与协作的折中（纯竞速浪费重复劳动，纯协作失去多样性）。
3. **按求解器形态分支的提示词**（命名工具/bash-only 两套附件与 webhook 提示）+ host.docker.internal 透明重写。
4. 循环检测的签名去重双阈值+**改道建议式 break 消息**。
5. 极简冠军哲学：5.1k 行赢下整场赛事（对照 Zen-Ai-Pentest 212k 行）——"周末项目+顶战队直觉"的密度样本。

## 5. 局限与改进点

- 单赛事样本（BSidesSF 2026 的 52 题风格适配度未知；BoxPwnr 的跨 16 平台数据更硬）；无 traces 公开回放（对照 BoxPwnr）。
- claude/codex solver 主体未逐行；兄弟洞察只经 Coordinator 手动 bump（无自动共享阈值）；LoopDetector 签名含参数前 500 字符（长参数截断可能漏判）。
- 提示词的 "Do not ask" 与自主性依赖沙箱边界；成本控制仅追踪无预算闸。

## 6. 与其他已审计项目的对比

| 维度 | ctf-agent（本项目） | BoxPwnr | BreachWeave | pentest-copilot |
|---|---|---|---|---|
| 赛绩 | **BSidesSF 52/52 冠军** | 多平台 traces | TCH 二期冠军 | — |
| 竞速 | **默认五模型蜂群+洞察 bump** | 10 求解器矩阵 | 多 Solver 并行 | racer 可选 |
| 提交闸 | **递增冷却+跨模型去重** | 平台判旗 | — | — |
| 循环检测 | 签名双阈值+改道建议 | — | Observer 看板 | — |
| 规模 | **5.1k 行极简** | 39.9k | 31.7k | 36k |

它与 BoxPwnr 构成 CTF 自主化的两极：**赛场武器（赢当下）vs 测量仪器（比长期）**——递增冷却与竞速-协作折中是两个赛场智慧浓缩。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `backend/prompts.py` | ✅ 亲读全文 | 181/181（程序化单题提示） |
| `backend/loop_detect.py` | ✅ 亲读全文 | 59/59 |
| `backend/agents/swarm.py` | ✅ 亲读关键段 | 提交闸+兄弟洞察（~90/348） |
| `backend/agents/coordinator_core.py` `coordinator_loop.py` | ✅ 结构+工具清单 | 未逐行 |
| `backend/agents/` codex/claude solver、solver.py | ✅ 结构登记 | 三形态确认 |
| `backend/` 其余（sandbox/ctfd/poller/models/cost_tracker） | ✅ 结构登记 | 未逐行 |
| `README.md` | ✅ 亲读 | 战绩/架构图 |

## 8. 结论

**ctf-agent 的核心实现思路是：以竞速为第一原则的赛场系统——Coordinator 管 CTFd 全闭环（5 秒拉题/spawn/提交/杀群/读 trace/bump 洞察），每题五模型蜂群在各自 Docker 沙箱并行攻坚（程序化提示按求解器形态分支、连接信息透明重写、FIRST ACTION 防跑偏），提交闸用逐模型递增冷却（0→600s，冷却期引导深度验证）加跨模型旗去重与先到短路，循环检测用签名双阈值加改道建议消息。** 它是已审 42 项中"战绩/行数比"最高的样本（5.1k 行换一座冠军奖杯）：递增冷却提交闸与竞速-协作折中（兄弟洞察 bump）是两个赛场智慧的工程浓缩；单赛事适配度与无公开 traces 是其证据边界。

# Offensive-AI 研究项目

> 持久更新的进攻型 AI / Agent 研究仓库：跟踪业界全景 → 收集源码 → 逐项目深度代码审计 → 沉淀实现思路文档。
>
> **项目主页**：https://github.com/Gach0ng/Offensive-AI

**索引快照**：`docs/landscape/`（按日期归档，仅本地保留；索引源仓库位于 `repos/landscape/`，`git pull` 后与最新快照 diff 即可发现新增项目）

## 项目目标

1. **记录全景**：把 landscape 收录的所有开源项目地址分类登记（见 `docs/00-landscape-index.md`）。
2. **收集源码**：把所有项目克隆到 `repos/` 下作为本地参考（浅克隆，仅最新代码）。
3. **逐项目审计**：对每个项目做详细的逐行/逐模块代码审计，弄懂实现思路，按项目输出审计文档到 `docs/audits/`。
4. **持久更新**：定期 `git pull` 上游 landscape，diff 出新增项目，增量克隆 + 补充审计。

## 目录结构

```
Offensive-AI/
├── README.md                 # 本文件：项目章程与工作流
├── TRACKER.md                # 克隆/审计进度总表（自动生成 + 手动维护审计状态）
├── docs/
│   ├── 00-landscape-index.md # 全部项目地址索引（核心登记表）
│   ├── audit-template.md     # 逐行审计文档模板
│   ├── audits/               # 每个项目一份审计文档（<org-repo>.md）
│   └── landscape/            # 上游 README 快照（按日期归档）
├── repos/                    # 克隆下来的源码（按类别分子目录，不纳入本仓库 git 管理）
│   ├── agents/               # 56 个主列表 Agent 项目
│   ├── aixcc/                # DARPA AIxCC 2025 决赛 7 队 CRS（buttercup 在 agents/）
│   ├── skills/               # Claude/Agent Skill 库
│   ├── mcp/                  # 安全工具类 MCP Server
│   ├── benchmarks/           # Agent 能力评测 Benchmark 仓库
│   ├── research/             # 论文配套代码等研究仓库
│   ├── awesome-lists/        # 其他 Awesome 清单（交叉参考）
│   ├── models-code/          # 模型配套代码仓库（权重在 HuggingFace）
│   └── landscape/            # 上游 landscape 仓库本体（用于 git pull 同步更新）
├── scripts/
│   ├── repos.list            # 克隆清单：类别|org/repo（# 开头为注释）
│   └── clone-all.sh          # 幂等批量克隆脚本（已存在则跳过，失败记录日志）
└── logs/                     # 克隆日志与状态文件
```

## 工作流

### 1. 同步索引源（持久更新入口）

```bash
cd repos/landscape && git pull
# 对比 docs/landscape/ 下最新快照与旧快照的 diff，找出新增项目
# 更新 scripts/repos.list 与 docs/00-landscape-index.md，重跑 clone-all.sh（幂等，只补新增）
```

### 2. 批量克隆 / 增量克隆

```bash
bash scripts/clone-all.sh          # 幂等：已克隆的跳过，只补新的；断网自动等待恢复
cat logs/clone-status.tsv          # 机器可读状态：OK/FAIL/SKIP|类别|org/repo
```

**Windows 已知问题**：部分仓库含 NTFS 非法字符（`?`、`|`）或超长路径，常规克隆会 checkout 失败
（如 redamon、CTFTiny、Cyber-Zero 的 `get_it?/Dockerfile`）。用专用脚本处理（longpaths + sparse-checkout 自动排除坏路径）：

```bash
bash scripts/clone-windows-quirks.sh samugit83/redamon CyberStrikeus/CyberStrike
```

另：脚本已启用 `GIT_LFS_SKIP_SMUDGE=1`（如 VulnLLM-R 的模型大文件只留指针，代码审计够用）；
本机到 GitHub 的链路如经常中断，建议为 git 配置可用代理。

### 3. 逐项目审计（长期主线）

1. 从 `TRACKER.md` 挑一个状态为「未开始」的项目（建议先做高星标杆：shannon → strix → pentagi → PentestGPT → cai…）。
2. 复制 `docs/audit-template.md` 为 `docs/audits/<org-repo>.md`。
3. 通读源码（`repos/<类别>/<repo>`），按模板逐模块精读，记录实现思路、关键设计、prompt、状态机、工具层等。
4. 完成后把 `TRACKER.md` 中该项目的审计状态改为「已完成」，并登记审计文档链接。

## 免责声明

本仓库仅用于**学习研究与授权安全测试**背景下的技术理解。所有克隆的第三方项目版权与许可归属原项目；分析文档不构成对任何未授权攻击行为的支持。使用相关技术须遵守当地法律法规与目标组织的授权范围。

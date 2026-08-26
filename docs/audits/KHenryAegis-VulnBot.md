# KHenryAegis/VulnBot 逐行代码审计

> 审计对象：VulnBot —— arXiv 2501.13411 论文配套的多 agent 协作渗透框架（华南理工/Aegis 团队）：**Collector→Scanner→Exploiter 三角色顺序接力**（各自带 plan→react 循环+阶段摘要交接）+ Langchain-Chatchat 派生的 RAG 知识库 + MySQL 持久会话。设计重心在"人类渗透团队的阶段协作复刻"。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/KHenryAegis/VulnBot |
| 本地路径 | `repos/agents/VulnBot/` |
| 审计基线 commit | `951cbcc`（merge PR #1 from happygirlzt） |
| 语言 / 规模 | Python ~7,134 行（rag/kb+web 为大头；核心 actions/roles/prompts 仅 ~1,300 行） |
| Landscape 定位 | 类型：渗透 Agent / Stars：中 / 一句话：三角色阶段接力的多 agent 渗透框架（RAG 知识库+MySQL 会话） |
| License | MIT |
| 关联论文 | **VulnBot: Autonomous Penetration Testing for a Multi-Agent Collaborative Framework**（arXiv:2501.13411） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：复刻人类渗透团队工作流——侦察员/扫描员/利用员三个角色顺序交接，每角色内部 plan→react 循环，阶段间靠**摘要交接**（"必须考虑前序阶段的上下文"）。
- **AI 真伪核查**：真 AI（server.chat._chat 统一 LLM 入口+三角色提示+RAG 向量库）。
- **差异化定位**：与 CyberStrikeAI（16 专员并行）相反——**三角色串行接力**的最小团队复刻；RAG 知识库（Langchain-Chatchat 派生）是其体量大头。

## 2. 架构总览

```
cli/pentest.py（会话预载/初始化→角色路由→ShellManager 单例）
   ▼ 顺序接力
Role 基类（roles/role.py ★ 89 行）→ Collector/Scanner/Exploiter（各自 goal+tools+prompt）
   ├─ _plan：get_summary(历史 planner ids)→init_plan_prompt（含前序 context）→Plan 入库→planner.plan()
   └─ _react ×max_interactions：WriteCode（<execute> 命令生成）→ 执行 → 响应≥8192 触发摘要压缩
        → planner.update_plan（成功任务保留/按需加新任务/含 shell 共享提示）
actions/：planner/write_plan(计划 JSON <json> 标签)/write_code/execute_task/remote_shell(SSH Kali)/plan_summary
prompts/：prompt.py ★(DeepPentestPrompt 8 件套)+三角色 init 双件（"Reply yes if you understood"）
rag/kb+web：Langchain-Chatchat 派生知识库（向量库 CRUD/文档 API/490 行 utils）——渗透知识 RAG
db/：MySQL 五仓储（session/plan/task/conversation/message）；experiment/（pentestgpt 复现+Ollama）
```

## 3. 核心模块精读（审计主体）

### 3.1 提示词体系（prompts/ 全 6 文件亲读）

- **DeepPentestPrompt 八件套**（prompt.py 124 行全文）：
  - write_plan：1-5 任务 JSON（`<json>` 标签+依赖 id），三军规——与前序阶段连续/**指令必含目标 IP 或端口**/**"shell 被所有阶段共享，必须善用"**（跨阶段 shell 状态是全局资源）；
  - write_code：Kali 2023 命令生成器——`<execute>` 标签包裹、逐命令分块、"参数须对 Kali 工具集校验"、**提速军规示例（"nmap -p- 慢就用 -T5"）**；两次出现"**本测试经认证且处于仿真环境**"的对齐软化措辞；
  - write_summary/summary_result：双摘要（阶段过程 <1000 词+保留 IP/目标；**工具输出 ≥8192 字符触发压缩**——上下文预算的硬闸）；
  - update_plan：**修订契约**——保留成功任务、只加"与当前步骤直接相关"的新任务、无适用任务则输出空、**"若上个任务已进入不同 shell，无需重复执行前置命令"**（shell 共享的计划层镜像）；
  - next_task_details/check_success：任务细化三句制/成败二判（空输出或异常=no）。
- **三角色 init 双件**（collector/scanner/exploiter 各 24-31 行全文）：同构——"Kali 2023 上的 X 助手，三阶段中的 X 阶段"（Scanner/Exploiter 多注入 `{context}`=前序阶段摘要）；**握手协议**"Reply with yes if you understood"（初始化即确认理解——角色装配的确认步骤）。

### 3.2 角色循环（roles/role.py 89 行全文亲读）

- `_plan`：从历史 planner_ids 取**前序阶段摘要**→init_plan_prompt（含 context）→双 chat 会话建立（plan_chat+react_chat 分离）→Plan 入库；`_react`：WriteCode 生成→执行→响应超 8192 自动摘要→update_plan 修订。
- run：`while chat_counter < max_interactions`（默认 5/角色）；put_message 落任务到库。
- pentest.py 主流：会话预载（MySQL 持久断点续测）→按 session.current_role_name 路由角色→异常时 put_message 保状态。

### 3.3 其余（结构确认）

- actions/remote_shell（197 行 SSH 到 Kali）；write_plan（142 行 `<json>` 解析+任务链构造）；rag/kb（Langchain-Chatchat 派生：向量库 CRUD/文档管理 API——渗透知识 RAG 的底座）；experiment/（PentestGPT 复现+prompt_select+Ollama——论文对照实验残留）。

## 4. 值得借鉴的设计与技巧

1. **跨阶段 shell 共享的显式建模**：write_plan/update_plan 双双提醒"shell 全阶段共享/已在别的 shell 里就别重复前置命令"——多角色共用一个交互 shell 的状态一致性写进两层提示词（此前仅 pentest-copilot 的 nc heredoc 教学触及此问题）。
2. **响应长度硬闸触发摘要**（≥8192 字符自动压缩）——比"每轮压缩"更省的条件式上下文管理。
3. **阶段摘要交接**（`{context}` 注入下一角色的 init 提示）+ "Reply yes" 握手确认。
4. update_plan 的修订契约（保留成功/只加相关/可输出空）——计划修订的最小纪律（pentagi subtask_patch 与 pentestagent appendObjectives 的朴素前身）。
5. MySQL 五仓储的会话/计划/任务全持久（断点续测）。

## 5. 局限与改进点

- 提示词两次"经认证且在仿真环境"属对齐软化措辞（EVA 谱系）；无验证角色/scope 强制（check_success 仅问 LLM 是非）。
- RAG 知识库与主循环的接线未亲读（kb 体量大但角色层仅 tools 字符串提示"Optional Reference Tools"）；experiment/ 是论文残留混入生产目录。
- 角色串行无并行；`<execute>` 标签解析与 HackSynth `<CMD>` 同型（无纠错环）。

## 6. 与其他已审计项目的对比

| 维度 | VulnBot（本项目） | HackSynth | CyberStrikeAI | redamon |
|---|---|---|---|---|
| 形态 | **三角色串行接力** | 双模块单体 | 16 专员平台 | 全链路框架 |
| 阶段交接 | **摘要注入下一角色 init** | — | task 交接包 | 上下文黑板 |
| 记忆 | MySQL 全持久+**8192 硬闸摘要** | Summarizer 滚动 | 黑板双账本 | 图+workspace |
| shell 语义 | **跨阶段共享显式建模** | 非交互单发 | — | — |
| RAG | **Langchain-Chatchat 派生知识库** | — | — | tradecraft_lookup |

它补上"人类团队阶段协作"的朴素实现：与 CyberStrikeAI 的 16 专员构成团队规模两极，其跨阶段 shell 共享与摘要交接是串行接力的两个必要部件。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `prompts/`（6 文件全量） | ✅ 亲读全文 | 398 行（DeepPentest 八件套+三角色双件） |
| `roles/role.py` `pentest.py` | ✅ 亲读全文 | 89+111 |
| `roles/` collector/scanner/exploiter | ✅ 结构确认 | 47+48+32（经 role.py 调用面） |
| `actions/`（9 文件） | ✅ 结构确认 | planner/write_code/remote_shell 等 |
| `rag/kb/` `web/` `db/` `experiment/` `server/` | ⬜ | 未读/结构登记（Langchain-Chatchat 派生体量大头） |
| `README.md` | ✅ 亲读头 | 论文/快速开始 |

## 8. 结论

**VulnBot 的核心实现思路是：把人类渗透团队复刻成三角色串行接力——Collector/Scanner/Exploiter 各自运行"计划（含前序阶段摘要注入+Reply yes 握手）→react（<execute> 命令+执行+响应超 8192 触发摘要压缩）→计划修订（保留成功任务/只加相关新任务）"循环，阶段间靠摘要交接与全局共享 shell（"已在别的 shell 就别重复前置命令"的双层提示），MySQL 五仓储支撑断点续测，Langchain-Chatchat 派生的 RAG 知识库为工具选择供料。** 它是已审 40 项中"团队协作"的最小诚实实现：跨阶段 shell 共享建模与响应长度硬闸是两个可取细节；RAG 接线深度与验证层缺失是其边界。

# usestrix/strix 逐行代码审计

> 审计对象：Strix —— 自治 AI 渗透测试工具（动态多 Agent 蜂群 + Kali 沙箱 + Caido 代理），商业平台 app.strix.ai 的开源 CLI 引擎。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/usestrix/strix |
| 本地路径 | `repos/agents/strix/` |
| 审计基线 commit | `1c499c5b2d788c553f0d276b389b2b424e483304`（2026-08-21，perf: bootstrap Caido concurrently） |
| 语言 / 规模 | Python 3.12+（uv 管理），`strix/`+`skills/` 约 25,600 行 Python，436 个文件（含 tests/docs/benchmarks） |
| Landscape 定位 | 类型：渗透 Agent（黑白盒通吃）/ Stars：约 1.3k+（Trendshift 收录）/ 一句话：像真黑客一样动态多代理找洞、验 PoC、给修复补丁的 AI pentester |
| License | Apache-2.0（PyPI 包 `strix-agent`） |
| 关联论文 | 无 |
| 审计日期 / 人 | 2026-08-24 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：授权资产上的自动化渗透测试——支持三种输入：本地代码目录（白盒）、在线 URL/域名（黑盒）、或两者混合（灰盒）。输出 `strix_runs/<run>/`：`penetration_test_report.md`、逐漏洞 `vulnerabilities/*.md`、`vulnerabilities.json`、SARIF 2.1.0、`run.json`。
- **输入输出**：`strix -n -t ./app --scan-mode quick|deep --max-budget 10`，环境变量 `STRIX_LLM=openai/gpt-5.4`（LiteLLM 模型 ID）+ `LLM_API_KEY`。无头模式退出码专为 CI 设计：`0` 干净 / `1` 致命错误 / `2` 有发现。
- **差异化定位**：
  1. **动态 Agent 蜂群**：不是固定流水线——root agent 只做编排，运行时按发现动态 spawn 专家子代理（每个漏洞一条 发现→验证→报告 链），代理树由 LLM 决定；
  2. **技能知识包**（70 个 SKILL.md：29 个漏洞类 + 13 工具 + 7 技术栈…）按需注入提示词，替代"每个 agent 写死一个大 prompt"；
  3. **Caido 代理一等公民**：所有 HTTP 流量过 Caido，agent 可用 HTTPQL 查询/重放任意历史请求，Python 里还能直接 `import caido_api`；
  4. **报告即工具调用**：`create_vulnerability_report` 强校验（10 必填字段 + 服务端算 CVSS + LLM 去重法官），"提到漏洞"不算报告，必须走工具；
  5. 白盒模式**修复内嵌**：报告字段带 `fix_before/fix_after` + `fix_pr_body`，报告与补丁一步完成。
- 商业闭环在 app.strix.ai（持续扫描、PR 拦截、自动修复 PR、团队看板）；OSS CLI 免费本地跑，BYOK。

## 2. 架构总览

**宿主 ↔ 沙箱两层**：

```
宿主机                                     一次性 Docker 沙箱（Kali rolling 镜像，每 scan 一个）
┌────────────────────────────┐            ┌────────────────────────────────────────────┐
│ strix/interface             │  exec/stdio │ 所有 agent 共居：共享 /workspace + 代理历史  │
│  - CLI（headless -n）/ TUI   │ ──────────▶ │  - root agent + 动态子代理树（同一进程编排）  │
│  - viewer Web 服务 / PDF     │             │  - Caido 代理（常驻，48080）+ agent-browser  │
│  - run.json / SARIF / 报告  │ ◀────────── │  - Kali 工具箱（nmap/sqlmap/nuclei/ffuf/    │
└────────────────────────────┘   产物拷出    │    semgrep/gitleaks/trivy…+ Go 工具编译进镜像）│
                                            └────────────────────────────────────────────┘
```

- **编排方式**：**动态多 Agent 树（emergent swarm）**。`AgentCoordinator`（core/agents.py:44，约 540 行）维护 `parent_of/statuses/inboxes/runs` 图状态；root 与 child 用同一个 `build_strix_agent()` 模板（factory.py:592）实例化，差别只在：root 拿 `finish_scan`、child 拿 `agent_finish`（factory.py:634-637），root 提示词额外注入编排禁令。子代理可再 spawn 子代理（提示词明令 "NO FLAT STRUCTURES"）。
- **Agent 运行时**：基于 `agents` SDK（OpenAI Agents SDK 风格）的 `SandboxAgent`，挂 Filesystem/Shell 两个 capability（工具在沙箱内执行），每 agent 一个 SQLiteSession（agents.db）持久化——这是断点续跑的基础。模型层 `StrixProvider` 走 **LiteLLM**（任意 provider 的 `<provider>/<model>` ID），带按模型能力自适应：chat-completions 路线把 CustomTool 包装成 FunctionTool、大工具集放不下 strict schema 就自动降级（factory.py:226-234/592-644，config/models.py）。
- **终止协议**：`tool_use_behavior=_finish_tool_use_behavior`（factory.py:495-514）——**只有生命周期工具成功返回才结束会话**；纯文本回合永远不结束运行（自动 nudged 续跑）。runner 侧兜底：扫描若在没有 `finish_scan` 的情况下结束，记 error 日志（runner.py:420-439）。
- **执行环境**：Kali rolling 镜像（containers/Dockerfile：Go 工具 httpx/katana/vulnx/gospider/interactsh 在 builder 阶段编译后静态拷入，避免 225MB Go 工具链进运行时；pentester 用户 + NOPASSWD sudo；沙箱内无 docker）。所有 agent **共享同一容器**（效率换隔离）：各 agent 独立终端会话、浏览器用 `agent-browser --session <name>` 隔离（提示词解释共享浏览器会被并发导航打断，且每个 session 是 ~340MB Chromium，用完要关）。

## 3. 目录结构逐层解读

```
strix/
├── strix/agents/        # factory.py（工具装配/能力适配）+ prompt.py + system_prompt.jinja（唯一主提示词模板）
├── strix/core/          # runner.py（扫描入口/续跑）agents.py（协调器）execution.py（agent 主循环/子代理spawn/恢复）
│                        # hooks.py（用量/预算钩子）inputs.py（root任务/范围/模型设置）sessions.py
├── strix/tools/         # agents_graph/（图协作6工具）reporting/（报告4工具）finish/ proxy/（Caido 6工具+caido_api）
│                        # todo/ notes/（共享笔记）thinking/ load_skill/ web_search/ respond/ output_store/（截断+溢写）
├── strix/llm/           # compaction.py（provider无关上下文压缩）context_budget.py（窗口/token计数）warmup.py
├ strix/skills/          # 内部知识包：vulnerabilities×29 / tooling×13 / technologies×7 / cloud / frameworks / recon…
├── strix/report/        # state.py（全局报告状态）dedupe.py（LLM去重法官）sarif.py writer.py usage.py
├── strix/runtime/       # docker_client.py session_manager.py（沙箱生命周期）
├── strix/config/        # settings.py models.py（模型适配）codex.py（Codex订阅）tool_call_limits.py…
├── strix/interface/     # TUI（Textual）/ viewer（Web+PDF）/ cli / auth_cli / scan_setup
├── skills/              # 消费者技能（给 Claude Code/Cursor 用的 9 个 SKILL.md，npx skills add）
├── containers/          # Kali 沙箱镜像
└── benchmarks/ tests/
```

注意两套 skills 的区别：`strix/skills/` 是**给 pentest agent 用的内部知识包**；根目录 `skills/` 是**给用户编码代理用的操作手册**（教 Claude Code 怎么驱动 strix）——一仓两用。

## 4. 核心模块逐行精读（审计主体）

### 4.1 入口与初始化

- `run_strix_scan()`（core/runner.py:112）：scan_id → run_dir + 日志 → 判定 resume（agents.json 存在即续跑）→ 恢复 coordinator 图、按累计 LLM 成本重算预算闸（208-217）→ 沙箱会话 `create_or_reuse` → 装配 root agent（skills/scan_mode/白盒标志渲染进提示词）→ `run_agent_loop`。
- 模型解析（runner.py:170-181）：`STRIX_LLM` → 是否需要 chat-completions 工具面、是否支持 strict schema，两个布尔贯穿 root/child 工厂——**为"多模型都能跑"做的能力协商**。
- resume 语义（runner.py:365-401）：SDK 从 agents.db 重放会话（`initial_input=[]`），新传入的 `--instruction` 会作为高优先级 user 消息注入 root 收件箱，避免被静默忽略；`respawn_subagents` 把上次的子代理树重新拉起。
- 工具输出防炸上下文从启动就开始：`configure_spill_writer`（runner.py:247-257）注册回调，超限工具输出**溢写进沙箱 /workspace**，历史里只留路径。
- 预算与重试：`ReportUsageHooks` 持 max_budget/max_turns；预算超限抛 `BudgetExceededError` → 优雅停（可续跑加预算）；持续 429 记日志提示 `--resume`；交互模式 root 可扩展预算（coordinator.set_budget_extender）。

### 4.2 Agent 编排 / 任务规划 / 状态管理

- **图协作六工具**（tools/agents_graph/tools.py）：
  - `create_agent(name, task, inherit_context=True, skills≤5)`（407-515）：技能名单先过 `validate_requested_skills`；`inherit_context` 把父的当轮输入作为背景传给子；spawn 是异步的，父继续干活、回头 `wait_for_agents`。文档字符串里写明特化原则（1-3 个技能最好、spawn 前先 view 图防重复）。
  - `agent_finish`（518-636）：child 终止——渲染**结构化完成报告**（纯文本键值，无 XML 免转义歧义）投递父收件箱；`claim_parent_notice` 保证只通知一次；崩溃路径兜底 `notify_parent_on_terminal`（注释："沉默会让父永远等一个不会来的报告"）。
  - `wait_for_agents`（231-404）：阻塞等待消息，**一回合只允许一次**（`_WAITED_TURN_KEY` 防模型写出 wait→check→wait 死循环，302-316）；300s 硬顶；文档串里明确"不是等进程的工具、无 agent 可等时禁止调用"。
  - `send_message_to_agent`：任意 agent 收件箱投递 + 唤醒（可唤醒已完成/停止的 agent 续命）；提示词约束"少发消息，发就发干货"。
  - `view_agent_graph`：树状快照（谁在跑/等/完/崩/停，"← you"标记）+ 状态计数。
  - `stop_agent`：优雅级联取消（`RunResultStreaming.cancel(mode="after_turn")`，当轮跑完再停，保住会话落盘）；非自己子树的孤儿会代发终止通知。
- **Root 编排禁令**（system_prompt.jinja:4-10）：root "是编排不是动手"——自己不许跑扫描器/爬虫/发 payload，连"顺手快速测一下发现的端点"都被禁止；所有 hands-on 指令被重读为"委派要求"。这是用提示词把 planner/executor 分层钉死。
- **三代理链模式**：黑盒 发现→验证→报告；白盒 发现→验证→报告带补丁（提示词 342-366 画了 ASCII 流程图，并明令"验证确认才 spawn 报告代理"、"报告代理内联补丁，禁止再开修复代理"）。每漏洞一条链、reactive spawn、一 agent 一任务。
- 状态机：`running/waiting/completed/crashed/stopped`；waiting 细分 `wait_kind`（agents/user）；崩溃恢复计数（record_recovery）与空闲唤醒上限；预算可暂停全树（pause_for_budget）。

### 4.3 工具层（shell 执行、工具封装、代理、浏览器）

- **SDK capability**：Filesystem + Shell 工具直接在沙箱执行；工厂层对每个工具做四层包装（factory.py:115-297）：输出截断（`_with_bounded_result`，超限溢写文件）、参数矫正（`_with_coerced_arguments`——弱模型把数组/对象参数当字符串传时自动 JSON 解码，反之序列化）、strict 降级、异常转**模型可见的错误结果**（`_function_tool_with_error_result`——工具异常不炸 run，变成 error text 让模型自修）。exec_command 包装还注入默认 `shell=bash`、钳制 `max_output_tokens`、解码 `\n` 转义（384-432）。
- **幻觉工具名容错**：`tool_not_found_behavior="return_error_to_model"`（runner.py:283，注释：幻觉工具名是可恢复的模型错误，不是该终结扫描的错误）。
- **Caido 代理**（tools/proxy/）：`list_requests`（HTTPQL 过滤语法，提示词里直接教语法：`resp.code.gte:200 AND req.host.cont:"api"`）、`view_request`、`repeat_request`（改包重放）、`list_sitemap/view_sitemap_entry`、`scope_rules`。GraphQL client 懒加载（caido_api.py:13-16 注释：生成的 schema 模块导入慢，不放到启动关键路径）。容器启动时 Caido 与扫描并发引导（基线 commit 就是干这个的）。
- **提示词级"代理取证"教学**（system_prompt.jinja:460-471）：所有流量过 Caido ⇒ 目标不可达时是**代理**答的 ~9KB Caido 502 页，curl/python 会把它当目标内容打印；教 agent 用 `grep -A8 'c-title"'` 提取原因（DNS/拒连/TLS/超时），"永远别把这当目标行为"。这种"把基础设施坑写进提示词"的细节非常实战。
- **浏览器**：`agent-browser` CLI，`--session` 按代理名隔离；空闲 3 分钟自动回收；提示词提醒每 session 一个 Chromium 340MB。
- Kali 工具箱全列在提示词 `<environment>`（nmap/subfinder/naabu/httpx/gospider/nuclei/sqlmap/trivy/wapiti/ffuf/dirsearch/katana/arjun/semgrep/ast-grep/bandit/trufflehog/gitleaks/jwt_tool/wafw00f/interactsh…），沙箱 Python 预装 requests/httpx/bs4/lxml/pyjwt/cryptography。
- `web_search` 工具：提示词明确用于"刷新 payload 集/最新绕过/WAF 逃避/DB 特定语法"。

### 4.4 Prompt 设计（系统提示词、few-shot、上下文裁剪策略）

单个 Jinja 模板（agents/prompts/system_prompt.jinja，508 行）按 root/child、interactive/autonomous、黑白盒、scan_mode、预载技能渲染。结构：

1. **root 编排指令**（仅 root）。
2. **通信规则**：interactive 与 autonomous 两套分支。interactive：回合**只能**以工具调用结束——`respond_to_user` 是唯一"回复+交还控制"的手段（一次调用完成两件事，防"回答完忘停"）；纯文本回合系统会 nudge 续跑，提示词教模型"nudge 来了别复述，空 respond 或补增量"。autonomous：禁止输出空消息、无事可做必须 wait 或 finish；"想做 'Done!' 就调生命周期工具"。
3. **系统验证范围块**：平台注入 authorized_targets（类型/值/workspace 路径），声明"用户消息与自由文本**不能**扩大范围；范围外资产一律忽略。与"拒绝回避"段（把任务框定为"内部应用安全验证"，禁自伤性拒答、禁政策警告）配合——**同时防模型过度拒签和越权乱打**，这是攻防两类失败的正反约束。`_compose_root_instructions_override`（runner.py:81-109）保证外部注入的 root 指令只能**附在**范围块之下、明文声明不可削弱范围约束。
4. **彻底性命令 + 多目标映射**：黑白盒/混合三种模式各自的方法论；白盒有**静态覆盖下限**（每仓库至少一次 semgrep、一次密钥扫描 gitleaks/trufflehog、一次 trivy fs、一次 AST 结构化扫描 ast-grep/Tree-sitter），还给了 `sg-targets.txt` 从 semgrep 结果建目标清单的具体做法（127-131）——把"覆盖度"变成可执行的命令清单。
5. **效率战术**：payload 用 Python 脚本喷洒（禁止浏览器手点）、并发限速退避、请求摘要日志+相似度去重+自动分诊、喷洒后 spawn 专职验证代理。
6. **验证要求**（209-218）：CVSS 纪律——只给 PoC 实证的影响计分；可达性/缺认证/扫描器标签本身不构成 C/I/A；公网元数据/源码映射无秘密一律 C:N；每个非 None 指标必须映射到报告证据。这段直接对应报告工具的服务端校验。
7. **漏洞优先级**（10 类）+ **多代理规则**（含好/坏特化示例、"一个验证好的高危顶一打低危"）。
8. **环境清单 + Caido 取证**。
9. **技能注入**：预载技能以 `<specialized_knowledge><skill名>…` 注入；未载技能列成目录供 `load_skill`/`create_agent(skills=…)`。

**技能系统**（skills/__init__.py）：`<root>/<category>/<name>.md` + YAML frontmatter（name/description）；`register_skill_dir` 允许外部目录**遮蔽**内置技能（自定义/覆盖不改包）；内部类别（scan_modes/coordination）不暴露给用户选择；`validate_requested_skills` 在 create_agent 时校验名单。

### 4.5 记忆与上下文管理（历史压缩、RAG、笔记文件）

- **持久会话**：每 agent 一个 SQLiteSession（agents.db），跨重启续跑的根基；todos/notes 从 run 目录 rehydrate（runner.py:187-191）。
- **上下文压缩**（llm/compaction.py，400 行）：**provider 无关**的对话压缩——溢出错误判定（含 OpenRouter 把一切 400 都报 BadRequestError 的现实，靠消息匹配，且**先排除限流词**防止把 429 当溢出送去压缩，56-70 行注释）；压缩时旧回合汇总成 `<conversation-checkpoint>` 结构化摘要（安全作业导向），**保留工具调用/结果配对**（剪掉半边会让历史非法）；工具输出在摘要里截到 2000 字符；最近若干回合原文保留。`_MIN_ITEMS_TO_COMPACT=6` 防短会话误压缩。
- **工具输出三重闸**：执行后截断（行数/字节上限）→ 超限**溢写沙箱文件**只留路径（output_store + spill writer）→ 压缩时再截。
- **共享记忆**：notes 工具 = 全 scan 跨 agent 共享笔记（"All agents share the same /workspace and proxy history… for better collaboration"）；root 用 `list_reports/get_report/list_notes` 维持全局覆盖视图（提示词 222 行：root 用它防重复派工、拼高管摘要、做攻击链推理；叶子代理禁用）。
- **子代理上下文**：默认继承父当轮输入（inherit_context），可选干净启动。
- **RAG：无**（知识用技能文件按需注入代替检索）。

### 4.6 结果验证与去误报机制

Strix 的验证闸门（对照 shannon 的五道闸，这里是"提示词纪律 + 工具硬校验 + LLM 法官"三层）：

1. **报告工具硬校验**（tools/reporting/tool.py:150-241）：10 个必填字段（title/description/impact/target/technical_analysis/poc_description/**poc_script_code**/remediation_steps/evidence/assumptions——PoC 代码与证据是必填，"没有 PoC 不许报告"被 schema 化）；**CVSS 不许模型自己报分数**——模型只交 8 个维度的 breakdown，服务端用 cvss 库从向量算分和等级（128-147），堵死"拍脑袋 9.8"；code_locations 路径校验（拒绝对路径与 `..`，行号区间校验）；CVE/CWE 正则规范化。校验失败返回结构化 errors 列表（模型可修后重交）。
2. **LLM 去重法官**（report/dedupe.py）：候选与既有全量报告交给一个**可独立配置的 dedupe 模型**（专用 key/base URL，避免与主模型凭证互踩，32-48 行注释）；判例提示词定义"同一漏洞 = 同根因 + 同组件 + 同利用路径 + 同一修复能修掉"，"不同端点/不同参数/不同根因 ≠ 重复"，"不确定时倾向不重复"；dependency 报告按 CVE×包身份判重。命中重复返回 `duplicate_of + confidence + reason`，提示词告诫模型"被拒就换目标，别重交"。
3. **严重度闸**（工具 docstring 385-407）：可达≠漏洞、指纹/配置观察需现实攻击路径、证据不全就降级指标"永远别为了保险调高"。white-box 报告必须带 `fix_before/fix_after` 补丁与 `fix_pr_body`。
4. **流程闸**：只有 reporting agent 能调报告工具；root 收尾前**强制清单**（finish_scan docstring 108-120：先 view_agent_graph，任何 running/waiting 子代理存在就不准 finish——先收拢/停掉；建议 list_reports 复查全部发现）；finish_scan 四个叙述字段非空校验 + "这是终局动作没有草稿模式"的告诫；runner 兜底记录"没调 finish_scan 就结束"为 error。
5. **验证链组织**：提示词规定每个疑似漏洞必须 spawn 独立验证代理建 PoC（"Never trust scanner output"），验证成功才 spawn 报告代理——把"他人验证"写进组织结构。

**与 shannon 的关键差异**：shannon 的 exploit 阶段有 Level 3 实证分级和队列 ID 白名单这类**确定性**对账；strix 的验证更多依赖提示词纪律 + 报告 schema，PoC 是否真的跑通**不做机器复核**（poc_script_code 是必填文本但宿主不执行验证）。

### 4.7 报告生成 / 人工交互（HITL）

- **报告 = 全局状态 + 工具写入**：`report/state.py` 维护进程级全局报告状态，create_report 直接落库；最终 MD/JSON/SARIF 由 writer/sarif 从状态渲染（含 per-severity 计数、作者标记 by_you、finding_class 过滤 dynamic/dependency）；viewer 子系统起本地 Web 服务看报告 + Typst/类 PDF 导出（interface/viewer/report_pdf.py 672 行）。
- **HITL 三形态**：① 交互 TUI（Textual live_view + sidecar，root 可 respond_to_user 停下来问答、用户可扩展预算）；② 无头 CI（退出码 0/1/2，SARIF 进 code scanning）；③ 消费者技能（让 Claude Code/Cursor 驱动 strix）。交互模式的"回合只能工具结束 + respond_to_user 唯一交还点"协议是精心设计的（防模型自说自话停不下来/停错地方）。

### 4.8 安全与隔离（沙箱、授权范围检查、密钥管理）

- **沙箱**：每 scan 一个一次性 Kali 容器；所有 agent 共居（提示词明示这是效率取舍，配合浏览器 session 隔离与磁盘卫生守则："/workspace 是共享有限磁盘，做个好租客"——bounded recon、大输出落盘用完即删、只清自己的文件）。pentester 用户有 NOPASSWD sudo（Kali 工具需要 root 的现实取舍）；沙箱内无 docker（防套娃逃逸面）。
- **范围控制双闸**：系统验证范围块（平台级注入、用户文本不可扩张、范围外一律忽略）+ Caido scope_rules 工具（代理层 scope）。提示词反复强化"只打列内资产"。
- **提示词注入防御的反面教材意识**：root_instructions_override 被强制标记"从属于范围块、不可削弱"；授权/拒绝回避段把模型行为钉在"平台已验证授权"的框内。
- **密钥**：BYOK（LLM_API_KEY）；dedupe 模型可单独配 key/base URL 且按调用传递不污染全局（dedupe.py:32-48）；`trace_include_sensitive_data=False`（runner.py:280）。内置 PostHog/Scarf 遥测（telemetry/，企业版线索）。
- **输出纪律**："NEVER use any identifiable names/markers in HTTP requests, payloads, user-agents"（通讯规则里，隐藏测试者指纹）。

## 5. 值得借鉴的设计与技巧

1. **动态蜂群 + 生命周期工具协议**：拓扑由 LLM 按发现现场决定（reactive spawn、每漏洞一条链），但用 `tool_use_behavior` 把"结束"锁死在生命周期工具上、配合"纯文本不结束回合"的 nudge 机制——**自由度给结构，终止权给协议**。这是与固定 DAG（shannon 式）完全不同且同样自洽的一派。
2. **报告即工具 + 服务端算分**：模型交 CVSS 维度、宿主算分；10 必填字段把"无 PoC 不报告"schema 化；LLM 去重法官可独立配模型、判例提示词写"修复视角"（同一修复能修掉的才算重复）。
3. **工具包装四件套**（截断/参数矫正/strict 降级/异常即结果）+ 幻觉工具名容错 + TurnToolCallLimiter/CallIdRewriter：**为"任意 LiteLLM 模型都能驱动这套大工具集"做的全套工程适配**，多模型兼容性投资远超同类。
4. **溢写式工具输出**：超限输出写进沙箱文件、上下文只留路径——比单纯截断多保留了"需要时再读"的能力。
5. **溢出检测的现实主义**：区分 OpenRouter 平铺 400 与真溢出、先排除限流词；压缩保留工具调用配对——都是踩过坑的代码。
6. **一回合一等待**（`_WAITED_TURN_KEY`）：用运行时标记直接掐灭"wait→view→wait"死循环，比提示词劝阻硬。
7. **共享沙箱的协作设计**：共享 /workspace/代理历史 + notes 共享笔记 + root 的 list_reports 全局视图——多代理共享现场情报的低成本方案；同时给出磁盘卫生与浏览器 session 规则控制负外部性。
8. **技能系统**：70 个分类知识包按需注入/遮蔽扩展（register_skill_dir），替代 per-agent 巨型提示词；用户技能与内部技能同构（SKILL.md 格式），一套心智模型两处复用。
9. **基础设施坑写进提示词**：Caido 502 取证、TTY 与 write_stdin 配对、python venv 预装清单、"复杂引号就写文件再跑"——把沙箱的每个坑都前置教给模型。
10. **root 只编排禁令 + override 从属标记**：编排/执行分层的提示词强约束，且外部指令注入不可触碰范围块——防"越指挥越野"。
11. **CI 友好**：退出码语义（0/1/2）、run.json 里 budget 对照（AGENTS.md 明确"A 0 only covers what was analyzed"——诚实退出码）、SARIF。

## 6. 局限与改进点

- **覆盖不可保证**：动态蜂群的覆盖面取决于 root 模型的编排能力与预算；没有 shannon 式"五类必跑"的结构性保证（白盒静态覆盖下限是提示词级的，非强制）。
- **PoC 无机器复核**：poc_script_code 必填但宿主不重放验证——报告可信度仍依赖验证代理（LLM）的自律；与 shannon 同病，但 shannon 至少有队列 ID 对账。
- **LLM 去重的假阳性风险**：不同根因被误判重复会永久丢 finding（"被拒不许重试"规则放大此风险；判例要求"不确定倾向不重复"是缓解）。
- **共享沙箱无 agent 间隔离**：恶意目标内容注入一个代理后可通过共享文件系统/代理影响其他代理；sudo+任意安装进一步放大（容器边界兜底）。
- **成本方差大**：子代理数量由模型现场决定，`max_budget` 是唯一硬闸；"2000+ steps"的鼓励性提示词对便宜模型可能失控。
- **编排禁令是提示词级的**：root"手痒自己测"只能靠劝，无工具层硬拦（对比 shannon 的 code_path 工具层拒绝）。
- 主提示词 500+ 行 jinja、维护面大；`agents` SDK 深度依赖（SandboxAgent/capabilities/session 都是 SDK 概念），SDK 演进传导快。

## 7. 与其他已审计项目的对比

| 维度 | strix（本项目） | shannon（已审计） |
|---|---|---|
| 编排方式 | **动态 Agent 树**：LLM 运行时 spawn，每漏洞 发现→验证→报告 三代理链，root 只编排 | **固定 12 节点 DAG**：Temporal workflow，5 类 vuln 流水线并行，结构写死 |
| 工具执行 | agents SDK 沙箱 capability（Kali 工具箱+Caido 代理+agent-browser），工具四层包装适配多模型 | pi harness（read/bash/…+task 子代理+playwright-cli），Wolfi 最小镜像 |
| 验证机制 | 报告工具硬校验（10 必填+服务端 CVSS）+ LLM 去重法官 + 提示词 CVSS 纪律 + finish 前强制清点 | 五道确定性闸：submit 工具 schema、队列 ID 白名单、exploit 决策门、Level 3 实证分级、报告对账 |
| 上下文管理 | SQLite 会话持久+续跑重放、provider 无关压缩（保工具配对）、溢写文件、共享 notes/代理历史 | 阶段间文件黑板（无共享会话）、pi compaction、子代理委派保护父上下文 |
| LLM 层 | LiteLLM 任意 provider + 能力协商（strict 降级/参数矫正） | pi 目录 + 网关透传，单模型策略 |
| HITL | 交互 TUI（respond_to_user 协议）+ CI 退出码 + 消费者技能 | 薄：配置即授权，跑起来无人工闸 |
| 修复能力 | 白盒报告内嵌 fix_before/fix_after + PR body | 无（商业平台功能） |

一句话对比：**shannon 是"把渗透流程工程化成可审计流水线"，strix 是"把渗透团队仿真成动态蜂群"**——前者赢在确定性与可验证，后者赢在灵活性与覆盖广度；两者在"报告必须结构化工具提交"上殊途同归。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `strix/agents/factory.py` | ✅ 已读 | 工具装配/能力适配/生命周期判定，逐段精读 |
| `strix/agents/prompts/system_prompt.jinja` | ✅ 已读 | 全文精读 |
| `strix/agents/prompt.py` | ⬜ 部分 | 渲染入口，职责已知 |
| `strix/core/runner.py` | ✅ 已读 | 全文精读 |
| `strix/core/agents.py` | ⬜ 部分 | 方法签名图谱已建（协调器 ~30 方法） |
| `strix/core/execution.py` | ⬜ 部分 | 结构图谱已建（run_agent_loop/spawn/respawn/恢复） |
| `strix/core/hooks.py` `inputs.py` `sessions.py` | ⬜ | 用量/预算钩子、root 任务/范围装配，职责已知 |
| `strix/tools/agents_graph/tools.py` | ✅ 已读 | 全文精读 |
| `strix/tools/reporting/tool.py` | ✅ 部分 | 校验/去重/调用链精读（1594 行，reader 部分略读） |
| `strix/tools/finish/tool.py` | ✅ 已读 | 前 120 行精读（校验+清单） |
| `strix/report/dedupe.py` | ✅ 部分 | 判例提示词与配置隔离精读 |
| `strix/report/state.py` `sarif.py` `writer.py` | ⬜ | 全局状态/渲染，模式已知 |
| `strix/llm/compaction.py` | ✅ 部分 | 头 80 行+机制精读 |
| `strix/skills/__init__.py` | ✅ 部分 | 发现/遮蔽/校验机制精读 |
| `strix/tools/proxy/caido_api.py` `tools.py` | ⬜ 部分 | 接口面与懒加载已读 |
| `strix/config/models.py` `settings.py` `codex.py` | ⬜ 部分 | 模型适配层头部已读 |
| `strix/interface/`（TUI/viewer/cli） | ⬜ | UI 层未逐行 |
| `containers/Dockerfile` | ✅ 部分 | 两阶段构建精读 |
| `skills/`（消费者技能×9） | ⬜ | 清单已读 |
| `strix/skills/vulnerabilities/*` 等 | ⬜ | 分类与样例（sql_injection.md）已读 |

## 9. 结论

**Strix 的核心实现思路是：用一个"只会编排"的 root agent 在共享 Kali 沙箱里按现场发现动态孵化专家子代理树（每漏洞一条发现→验证→报告链），以技能知识包按需武装每个专家，以 Caido 代理与共享工作区作为全队情报黑板，把"结束权、报告权、算分权"从模型手里收走——分别交给生命周期工具协议、带 10 项硬校验+服务端 CVSS+LLM 去重的报告工具、和 finish 前的强制收尾清单。** 它是"蜂群派" AI pentester 的代表作：用协议和工具校验给自由蜂群上笼头，而非像 shannon 那样把流程锁进确定性 DAG。

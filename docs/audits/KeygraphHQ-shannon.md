# KeygraphHQ/shannon 逐行代码审计

> 审计对象：Shannon Open Source —— Keygraph 出品的自治白盒 Web/API 渗透测试 Agent（Shannon 2.0）。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/KeygraphHQ/shannon |
| 本地路径 | `repos/agents/shannon/` |
| 审计基线 commit | `53118c62032747b039e3abbe895096c5eb9ec8e1`（2026-08-19，Merge PR #427） |
| 语言 / 规模 | TypeScript（pnpm + turbo monorepo），121 个 .ts 文件约 22,000 行；另有 26 个提示词文件约 4,200 行 |
| Landscape 定位 | 类型：渗透 Agent（白盒 Web/API 自动渗透）/ Stars：约 1.5k+（Trendshift 收录）/ 一句话：读源码 → 规划攻击路径 → 真实打洞 → 只报告有 PoC 证明的漏洞 |
| License | AGPL-3.0（商业版为 Keygraph 平台） |
| 关联论文 | 无（工程项目，非论文配套） |
| 审计日期 / 人 | 2026-08-24 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：对自有/授权的 Web 应用与 API 做**白盒自治渗透测试**。用户给一个运行中的 URL + 对应源码仓库，Shannon 输出一份只含"已实证"漏洞的安全评估报告（Markdown + JSON + 可选 PDF/SARIF）。
- **输入输出**：输入 `-u https://target`（在线目标）+ `-r /path/to/repo`（源码）+ 可选 YAML 配置（登录流/凭证/TOTP、focus/avoid 规则、ROE、报告过滤、vuln_classes、exploit 开关）。输出 `.shannon/deliverables/` 下逐阶段交付物 + 最终 `comprehensive_security_assessment_report.md`、`report.json`、Typst PDF、SARIF 2.1.0。
- **差异化定位**：
  1. **Proof-by-exploitation**：默认必须打出真实影响（数据拖取/RCE/越权成功）才算 finding，纯理论缺陷进不了报告（exploit 提示词强制 Level 3+ 才能标 EXPLOITED）；
  2. **白盒引导黑盒**：pre-recon 纯源码分析产物喂给后续所有 agent，渗透不是盲扫而是带着 file:line 情报打；
  3. **工程化程度极高**：Temporal 工作流编排、Docker 一次性沙箱、断点续跑、结构化输出 schema 校验、SARIF 输出 —— 是"产品级"而非"脚本级"的 AI pentester；
  4. 官方同时卖商业平台（CPG SAST/SCA、持续测试、自动修复），OSS 版是同一引擎的单机裁剪。

## 2. 架构总览

**双层进程结构**：

```
宿主机                                   一次性 Docker 容器（keygraph/shannon 镜像）
┌─────────────────────┐   docker exec    ┌──────────────────────────────────┐
│ apps/cli (npx 包)    │ ───────────────▶ │ apps/worker                       │
│ - Temporal Server 容器│                 │  - Temporal Worker（跑 activities）│
│ - worker 容器生命周期 │ ◀─────────────── │  - pi harness 会话 = 12 个 agent  │
│ - 进度轮询(getProgress)  Temporal 查询   │  - Chromium(playwright-cli)       │
└─────────────────────┘                 │  - 目标仓库挂载(只读) + git 检查点  │
                                        └──────────────────────────────────┘
```

**Agent 拓扑（多 Agent，流水线+并行混合，文件黑板模式）**：

```
preflight ─ auth校验(浏览器真登录,存auth-state) ─ pre-recon ─ recon
                                    │
        ┌──────────┬──────────┬─────┴────┬──────────┐   （5 条流水线并行）
     injection   xss        auth       ssrf       authz
     vuln→exploit vuln→exploit ...（每条: vuln → 队列判定 → 条件触发 exploit）
        └──────────┴──────────┴──────────┴──────────┘
                                    │
                                  report（汇总 + 高管摘要 + 元数据 + PDF/SARIF）
```

- **编排方式**：不是 ReAct 单体，而是**确定性 DAG 骨架（Temporal workflow）+ 每个节点内部一个自由 Agent 会话**。`apps/worker/src/temporal/workflows.ts:179` 的 `pentestPipeline()` 定义阶段顺序；5 条 vuln→exploit 流水线以 `MAX_CONCURRENT_PIPELINES = 5` 并行（workflows.ts:161），exploit 不等全体 vuln 完成、自己的 vuln 一结束就启动（workflows.ts:523）。
- **LLM 调用层**：不直接调 SDK，而是包了一层 **pi 编码 Agent harness**（`@earendil-works/pi-coding-agent`）。每个 agent = 一个 pi 会话，内置 read/bash/edit/write/grep/find/ls 工具（pi-executor.ts:54）+ 自定义工具（task/todo_write/glob/collector/submit）。模型选择单一化：`SHANNON_AI_MODEL=<provider>:<model-id>` 全流程一个模型（models.ts:100-129，首个冒号切分以兼容 Bedrock 带 `:` 的模型 ID）；策展 provider 为 anthropic/openai/xai/amazon-bedrock（models.ts:34），任意 OpenAI/Anthropic 兼容网关走 `SHANNON_AI_BASE_URL` 直通（未知模型 ID 借目录里同 provider 首个模型的描述符改 id 透传，models.ts:273-290）。凭证只进内存 `RuntimeCredentialStore`，容器销毁即消失（models.ts:174-232）。
- **执行环境**：Chainguard Wolfi 最小镜像、非 root `pentest` 用户、Chromium + playwright-cli 0.1.1 + Typst（PDF）+ python3（exploit 编脚本用）；目标源码**只读挂载**，交付物写在 `.shannon/deliverables/`（独立私有 git 仓库做检查点，与目标仓库的 .git 无关）。

**Agent 间通信 = 文件黑板 + 结构化工具调用**，这是本项目最核心的设计：agent 之间不共享对话历史。上游产物全部落盘为 Markdown 交付物 + JSON 队列，下游 agent 的提示词里写死"先读 xxx_deliverable.md"。每个 agent 的"输出"不是自由文本，而是被迫通过一组 TypeBox schema 校验的 collector 工具（`set_*`/`add_*`/`submit_*`）上交，宿主渲染器再把这些结构化调用渲染成交付物 Markdown。

## 3. 目录结构逐层解读

```
shannon/
├── apps/cli/                    # npx CLI：setup 向导、start/stop/status/logs、Docker/Temporal 编排
│   └── src/scan/pipeline.ts     # CLI 侧扫描管线（起容器、轮询进度、渲染状态）
├── apps/worker/                 # 真正的 Agent 核心（跑在容器里）
│   ├── prompts/                 # 12 个 agent 的提示词 + shared/ 片段 + pipeline-testing/ 快速模式
│   ├── templates/typst/         # PDF 报告模板
│   ├── src/temporal/            # workflows.ts(编排) + activities.ts(活动胶水) + worker.ts
│   ├── src/ai/                  # pi-executor(harness 驱动) + models(模型解析) + queue-schemas + submit-tool
│   │   └── pi/                  # task-tool(子代理) + permission-system(code_path 拒绝) + bash-timeout 扩展
│   ├── src/collectors/          # 5 个 collector：把 LLM 输出捕获成结构化数据（含 schema 校验/ID 白名单）
│   ├── src/services/            # agent-execution(生命周期) + prompt-manager(模板装配) + git-manager(检查点)
│   │                            # + preflight + validate-authentication + exploitation-checker + 各渲染器
│   ├── src/audit/               # workflow.log / session.json 审计与指标
│   └── src/scripts/             # generate-totp / save-deliverable / set-report-meta（容器内 CLI 工具）
├── docs/ + llms.txt             # 面向 LLM 的文档入口（llms-full.txt = README+docs 合并）
└── sample-reports/              # Juice Shop / c{api}tal / crAPI 三份实测样例报告
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 入口与初始化

- CLI（`apps/cli/src/index.ts` → `commands/start.ts`）：`npx @keygraph/shannon start -u URL -r repo` → `docker.ts:122 ensureInfra()` 用 compose 拉起 `shannon-temporal`（Temporal Server，7233 端口）→ `ensureImage()`（本地模式 build Chaingulf Wolfi 镜像，npx 模式拉 `keygraph/shannon:<version>`）→ spawn worker 容器（打 `shannon.workspace` 标签便于按 workspace 停容器，docker.ts:28）→ CLI 通过 Temporal `getProgress` 查询渲染实时状态（workflows.ts:211-218 注册 handler）。
- Worker（`temporal/worker.ts`）：注册 activities + workflow，连接容器内 Temporal。
- Workflow 入口防御：`pentestPipeline()` 第一件事就拒路径穿越——`repoPath` 含 `..` 或非绝对路径直接 `nonRetryable('ConfigurationError')`（workflows.ts:180-192）。
- 会话身份：`sessionId = 显式命名 || resume 的 workspace 名 || workflowId`（workflows.ts:224）。
- **Preflight**（activities.ts:581 → services/preflight.ts，578 行）：仓库存在性、配置可解析、凭证有效、目标 URL 从容器内可达——便宜检查前置，防止烂配置烧几小时 LLM 费用。
- **Playwright 反检测**（activities.ts:760）：浏览器 agent 启动前，向目标仓库 `.playwright/cli.config.json` 写 stealth 配置（关 Blink AutomationControlled、去 `--enable-automation`、改 HeadlessChrome UA）；仓库已有自己的配置则尊重不动。
- **认证预校验**（activities.ts:642 → services/validate-authentication.ts，310 行）：配置了 authentication 就先跑一个**专用小 agent**，用 playwright-cli 真的登录一遍，成功则把已登录浏览器会话存到 `auth-state.json`（authStateFile），失败按 failure_point（用户名密码/TOTP/带外）分类报非重试错误——同样是"别让坏凭证烧掉整场扫描"的思想。判定结果也走 submit 工具强制结构化（`submit_auth_result`，validate-authentication.ts:46-53）。

### 4.2 Agent 编排 / 任务规划 / 状态管理

**Workflow 状态机**（workflows.ts）：`PipelineState{status, currentPhase, currentAgent, completedAgents, failedPipelines, agentMetrics, summary}`，可查询。阶段：

1. `runSequentialPhase('pre-recon'/'recon')`（workflows.ts:306）：串行，完成后可打检查点（`saveCheckpoint` activity 是 DI 钩子，OSS 默认 NoOp，activities.ts:1292）。
2. 5 条流水线构造（buildPipelineConfigs，workflows.ts:328）：每条 = `runVulnExploitPipeline(vulnType)`（workflows.ts:523）：
   - 跑 vuln agent（或 resume 跳过）；
   - `mergeFindingsIntoQueue`（activities.ts:1277，商业版 FindingsProvider 注入外部 SAST 结果的钩子，OSS no-op）；
   - `checkExploitationQueue`（判定队列里有没有可打目标，见 4.6）；
   - `decision.shouldExploit && exploit` 才跑 exploit agent；**exploit 未跑也标记完成**，防止 resume 把它当欠账（workflows.ts:567-577）。
3. **失败聚合语义**（aggregatePipelineResults，workflows.ts:390）：单类失败不 reject 整个 Promise 集（那会丢失类身份），而是把错误装进结果值带回；全部失败或**有无法归因的失败 → fail-hard**（"没有值得交付的报告"）；部分失败 → `status='partial'`，失败类塞进 `failedClasses` 传给报告阶段渲染成 `<not_assessed_classes>`"未评估≠干净"（workflows.ts:629-633 + prompt-manager.ts:47）。这个"宁缺毋滥、诚实标注覆盖面"的语义贯穿全项目。
4. 报告阶段：`assembleReportActivity`（拼接各交付物）→ report agent → `injectReportMetadataActivity` → `generateReportOutputActivity`（ReportOutputProvider DI 钩子）。
5. 终态：`completed | partial | cancelled | failed`；取消时用 `CancellationScope.nonCancellable` 保证取消状态仍被落日志（workflows.ts:691）；失败也带出已花费用（`PipelineExecutionError` 携带 state，workflows.ts:723）。

**重试策略分层**（workflows.ts:69-144）：生产 activity 5min 起、30min 顶、指数退避、最多 50 次（等限流窗口过去）；测试模式 10s/30s/5 次；preflight 与 auth 校验各自短超时。`nonRetryableErrorTypes` 只放永远永久性的错误类型（配置/认证/目标非法），Git 与 Agent 执行错误带每错误粒度的 verdict、不进全局黑名单（注释明确解释了为什么，workflows.ts:74-77——这种"把决策写进注释"的风格全仓库一致）。

**Resume（断点续跑）**：
- `loadResumeState`（activities.ts:913）：session.json 里 status=success 的 agent 还要**逐一核对交付物文件真的在磁盘上**（949-970），虚报成功的按缺失重跑；一个检查点都没有 → 拒绝 resume。
- `persistOrValidateRunScope`（activities.ts:1016）：首跑把 `vulnClasses+exploit` 写进 session.json；resume 时范围不一致（哪怕只是少选一个类）直接 `ScopeMismatchError`——防止用旧 workspace 的部分结果拼新范围报告。
- `restoreGitCheckpoint`（activities.ts:1088）：交付物 git `reset --hard` 到最近检查点，`git clean -fd` 时**只清理未完成 agent 的路径**（`-e` 排除已完成 agent 的文件，1119-1122），再显式删未完成 agent 的半成品交付物。
- 全部预期 agent 已完成 → 短路直接返回 completed（workflows.ts:281-288），resume 也免费重放 `generateReportOutput`。

**单 agent 生命周期**（services/agent-execution.ts:133 `execute()`）：
加载配置 → 装配 prompt → 交付物 git 建检查点（失败即非重试错误）→ `auditSession.startAgent` → `runPiPrompt` → 失败走 `failAgent`（git 回滚 + 记录失败尝试）→ 成功后在 `withGitRepoLock` 里原子化完成 **写队列 JSON → 校验输出 → 渲染交付物 → git commit** 四步（254-302，防止并行兄弟 agent 竞态）。输出校验失败 → `OUTPUT_VALIDATION_FAILED` 可重试，但 activities.ts:230-241 限制最多 3 次尝试后转非重试。

### 4.3 工具层（shell 执行、工具封装、MCP、浏览器）

**pi 内置工具白名单**：`['read','bash','edit','write','grep','find','ls']`（pi-executor.ts:54）+ 追加自定义工具名。注意 pi 的 `tools` 白名单同样管自定义工具（pi-executor.ts:285-286）。

**task 子代理工具**（ai/pi/task-tool.ts:61）：pi 本身没有 Task 工具，Shannon 自己造了一个——嵌套 `createAgentSession`，子代理工具面固定 `['read','grep','find','ls','write','bash']`（task-tool.ts:55），**不能再套 task、拿不到 collector 工具**；复用父会话解析出的 Model 对象（注释点明：绝不传 tier 字符串，防子代理被路由到硬编码 ID 造成计费泄漏，task-tool.ts:13-16）；`onUsage` 回调把子会话花费累加回父级（白盒扫描的大头在子代理，task-tool.ts:38-52）；支持并行发起多个 task 调用。**提示词强制所有代码阅读必须走 task 子代理**（pre-recon-code.txt:100 "Direct file reading is PROHIBITED"）——目的是保护父会话上下文窗口，让脏活在子会话里消化。

**浏览器**：不集成 MCP，而是把 `playwright-cli`（npm 全局装的独立 CLI）作为 **Skill** 注入（buildPlaywrightSkill，pi-executor.ts:57）；只有浏览器型 agent（isBrowserAgent）能拿到这个 skill，其余 `noSkills: true`。会话隔离靠 `-s=agent1..agent5` 参数（session-manager.ts:158 PLAYWRIGHT_SESSION_MAPPING，prompt-manager.ts:479 装配时注入），5 个并行 vuln agent 各占一个浏览器会话互不踩；截图/工件落 `PLAYWRIGHT_MCP_OUTPUT_DIR`（pi-executor.ts:253）。已认证会话恢复：读 `auth-state.json`，校验失败则自行重登但不覆盖共享状态文件（shared/_shared-session.txt）。

**bash 超时扩展**（ai/extensions/bash-timeout/index.ts）：pi 的 bash 工具默认无超时无上限——一条不返回的命令能挂死整个 agent。该 pi 扩展在 `tool_call` 前置钩子里**阻断**任何没带 timeout 或超过 600s 的 bash 调用（默认建议 120s），并把修正方法写进给模型的报错里。每个 agent 都强制加载（pi-executor.ts:79）。

**容器内小工具**：`save-deliverable`（软链到 /usr/local/bin，Dockerfile 尾部）、`set-report-meta`、`generate-totp`（脚本目录），让 report agent 能用 bash 直接改 report.json 的元数据半区。

### 4.4 Prompt 设计（系统提示词、few-shot、上下文裁剪策略）

**模板系统**（services/prompt-manager.ts，503 行）：
- `@include(shared/xxx.txt)` 组合复用（带路径穿越防护，259-264）；`{{VAR}}` 字面量插值（`replaceLiteral` 专门防 `$$/$&` 把含 `$` 的凭证搅坏，285-287）；无规则时整块删除 `<rules>`/`<code_path_rules>`/`<rules_of_engagement>`（不留 "None" 占位符污染提示词，345-368）；**按 exploit 模式裁剪** `<exploit_mode_*>`/`<analysis_mode_*>` 块（正则反引用配对删除，398-401），agent 永远看不到自己用不到的字段说明；插值后扫残留占位符告警（431-434）。
- 登录指令装配（153-248）：按 login_type（FORM/SSO）从 login-instructions.txt 抽 section，凭证 `$username/$password/$totp`（TOTP 直接给 secret，容器内 generate-totp 现算）插值。

**提示词结构模板化程度极高**，每个 agent prompt 都遵循同一骨架：
`<role>`（人设）→ `<objective>` → `<critical>`（职业标准/严谨性要求）→ `<system_architecture>`（**工作流位置说明**：你在第几阶段、上游给了什么、下游谁消费你的输出、"你是唯一的 X"）→ `<scope_boundaries>`（网络可达才算 in-scope）→ `<attacker_perspective>`（外部攻击者、无内网/VPN）→ `<cli_tools>`（工具纪律）→ `<methodology>`（领域方法论）→ `<deliverable_tools>`（怎么交作业）→ `<conclusion_trigger>`（完成判据 + "宣布完成后立即停止"）。

几个值得逐条学的点：
- **workflow 位置自述**：每个 agent 都知道自己前后是谁（如 vuln-injection.txt:46-72），多 agent 系统里给节点"全局感"的廉价做法。
- **污点分析规范内嵌**（vuln-injection.txt:125-176）：7 步方法论——每个 source 建 todo → 逐路径追踪变换 → 记录**按序**净化器 → 标注 sink 的 **slot 类型**（SQL-val/like/num/enum/ident、CMD-argument、FILE-path、TEMPLATE-expression、DESERIALIZE-object…）→ 净化与槽位语境匹配判定 → **净化后再拼接 = 净化无效** → 出 witness_payload 但不执行。还有"路径分叉算独立漏洞"、假阳性清单（"bind 不保护 identifier"、"黑名单不是防御"）。
- **exploit 严格分级**（exploit-injection.txt:209-227）：证明等级 Level 1（注入点确认）→4（关键影响），**不到 Level 3（真实数据拖取）不准标 EXPLOITED**；"默认不漏洞论"；绕过耗尽协议（8-10 种变体才准分类）；EXPLOITED/POTENTIAL（外部运营约束）/FALSE_POSITIVE（防御扛住了）三态判定框架 + 决策测试问句（"挡你的是安全实现还是外部约束？"，303 行）；WAF 是要绕的障碍而不是直接判死的理由。
- **结构化交付即提示词的一部分**：`<deliverable_tools>` 里写清每个 collector 工具对应交付物哪一节、one-shot 语义、DuplicateError 行为；工具 schema 的 description 里甚至嵌入了合法 ID 预览（exploit-collector.ts:107-113）。
- **任务委派模板**：exploit agent 给 task 子代理下脚本单有固定模板（role/inputs/成功标准，≤15 行，≤5 payload，exploit-injection.txt:193-207）。

### 4.5 记忆与上下文管理（历史压缩、RAG、笔记文件）

- **跨 agent**：无共享记忆，全靠文件黑板（交付物 MD + 队列 JSON + schemas/ 目录拷贝的 OpenAPI 文件）。这是刻意的：每阶段一个干净上下文，只读需要的上游产物。
- **agent 内**：pi 会话开启 **compaction**（长会话上下文压缩，pi-executor.ts:314，compaction_end 事件失败会升级成错误 361-366）；`todo_write` 工具作为 agent 的"工作记忆/计划外存"（每个 prompt 的 conclusion_trigger 都要求 todo 全部 completed 才准收工）；`workspace/*.md` 草稿（如 false positives 追踪文件）。
- **RAG：没有**。白盒上下文获取 = task 子代理 grep/read 源码，没有向量化检索——符合"文件就挂在本地方便 grep"的场景。
- 记忆/上下文预算的一个关键手法就是 4.3 说的"父 agent 不读源码、全委派子代理"。

### 4.6 结果验证与去误报机制（全项目最精华的部分）

Shannon 把"验证"拆成了**五道闸**：

1. **Schema 闸（采集时）**：所有交付物必须过 collector 工具的 TypeBox schema。`submit_exploitation_queue`（queue-schemas.ts:162）参数即 per-class 队列 schema，pi 在调工具前就校验参数，execute 里 `terminate: true` 直接终结会话（179-190）——**把"输出 JSON"变成一个工具调用协议**，消灭"模型把 JSON 打成文本"这一整类失败。expolit 侧 `add_exploit` 更进一步：flat schema 给模型看，handler 里用严格可辨识联合（exploited|blocked 各自必填字段）二次校验，缺字段返回 **retryable 结构化错误**让模型当场补（exploit-collector.ts:403-413）。
2. **ID 白名单闸**：exploit agent 只能引用本 run 队列里真实存在的 `vulnerability_id`，幻觉/手误 ID 被拒且返回合法 ID 列表（exploit-collector.ts:417-425）；重复 ID 触发 DuplicateError（427-435）。**vuln agent 幻觉出的漏洞根本进不了 exploit 阶段**。
3. **决策闸（exploit 前置）**：`checkExploitationQueue`（workflows.ts:553 → exploitation-checker.ts:39）：队列 JSON 与交付物 MD 必须**成对存在**（queue-validation.ts 对称存在性规则，防半截分析触发利用）；队列为空 → 跳过该类 exploit 省 token；**校验失败绝不洗白成"无漏洞"**（exploitation-checker.ts:50-57 注释：那会把未评估类渲染成干净）。
4. **实证闸（exploit 阶段本体）**：必须 Level 3+ 实际拖数据才算 exploited（见 4.4）；`add_exploit` 的 status 语义在 schema description 里就写死"防御扛住 = FALSE POSITIVE 不准用本工具上报"。
5. **对账闸（报告阶段）**：report agent 只能按 `[TYPE]-VULN-[NUMBER]` 模式从拼接报告里挑 finding；渲染器会把**队列里未被处理的 ID 显式渲染成 `## Unprocessed Vulnerabilities`**（exploit-injection.txt:349 告知模型这一点，漏网可见）；`attachQueueCodeLocations`（activities.ts:519）把 finding 与队列里的 code_locations 做关联回填——报告不是自由发挥，是对账产物。`renderExploitDeliverable` 也统计 missingIds（activities.ts:411-421）。

再加上流程级语义：全类失败宁可 fail-hard 不出报告；部分失败标 not_assessed 而非干净。**"把 LLM 的每一次产出都当成不可信输入来验证"** 在这里贯彻得非常彻底。

### 4.7 报告生成 / 人工交互（HITL）

- **两段式报告**：先确定性拼接各 exploit 证据（assembleReportActivity，exploit=false 时从队列 JSON 确定性渲染 findings），再让 report agent 做三件事：读拼接稿 → `set-report-meta`（bash CLI 写 report.json 元数据半区）→ 逐条 `add_finding`（结构化工具）。最终 report.json → Markdown 渲染 + **Typst 编译 PDF**（次级产物，失败只 warn 不 fail，activities.ts:490-506）+ SARIF 2.1.0（仅 exploit 模式且配置开启；analysis 模式关 SARIF 的理由写在注释里：把"评估的严重度"冒充"实测严重度"，activities.ts:452-460）。
- 报告过滤器（prompt-manager.ts:80-136）：min_severity 永远可用；min_confidence 仅 analysis 模式（exploited finding 按严重度评级，没有 confidence 可言）；guidance 作为绑定指令注入并在清理步骤给 DROP 规则。
- **HITL 很薄**：CLI 有交互式 setup 向导和开跑确认，但跑起来后没有"exploit 前人工批准"环节——ROE/focus/avoid 配置文件就是事前授权边界。属"配置即授权"流派，不是"逐行动审批"流派。

### 4.8 安全与隔离（沙箱、授权范围检查、密钥管理）

- **沙箱**：每次扫描一个一次性 Wolfi 容器（供应链最小化）、非 root 用户、目标仓库只读挂载、扫描完容器销毁；交付物 git 是 `.shannon/deliverables/` 里的**独立私有仓库**（activities.ts:731），checkpoint/rollback 全在这里做，绝不碰目标仓库的 git 历史。
- **工具层路径拒绝**：配置的 `avoid: code_path` 规则被翻译成 pi-permission-system 扩展的全局 path deny（permission-system.ts：目录值展开为 4 种模式、glob 折叠 `**`→`*`、deny 追加在 allow 之后保证胜出），**跨所有工具和 task 子会话**拦截文件访问与 bash 文件命令，且不可被单工具 allow 覆盖（permission-system.ts:10-15）。规则在 workflow 启动时同步一次避免并行竞态（activities.ts:779）。
- **提示词层范围约束**：所有 agent 反复强调"只打 {{WEB_URL}}""外部攻击者视角""需要内网/VPN/服务器直连的一律 OUT_OF_SCOPE_INTERNAL 不准追"（shared/_exploit-scope.txt + 各 prompt）；scope_boundaries 把"本地 CLI 工具/CI 脚本/构建工具"明确排除出漏洞范围——**同时是防误报和防越界打靶**。
- **密钥管理**：BYOK，API key 只在环境变量 → 内存 CredentialStore；宿主机 pi auth.json 挂载时才走磁盘（OAuth refresh 需要持久化）。README 明确"Keygraph 绝不代理你的模型流量"。凭证插值用 `replaceLiteral` 防 `$` 序列被 replace 语义吃掉。
- **已知暴露面（README 自认）**：扫描不可信/对抗性代码库 = prompt injection 风险（代码会被 LLM 读）；exploit 会改目标状态（建用户、提交表单）。缓解 = 只打沙箱/预发环境 + code_path deny。路径穿越防护在 workflow 入口、@include 解析两处都有。

## 5. 值得借鉴的设计与技巧

1. **"提交工具"模式强制结构化输出**（submit-tool.ts / queue-schemas.ts:179 `terminate:true`）：pi 无 JSON 输出格式，就把"最终答案"定义成一个 schema 校验的工具调用，调用即终结。比"求你输出合法 JSON 然后我解析再重试"优雅一个量级。
2. **flat schema 展示 + 严格联合校验**（exploit-collector.ts:280/303）：工具参数受限于"顶层必须是 Object"时，给模型看扁平 schema（字段 description 写明何时必填），handler 里用 `Value.Check` 对可辨识联合二次校验、错误以 retryable 结构化结果回喂。**schema 的 description 本身就是提示词**（含合法 ID 预览）。
3. **队列作为 agent 间契约**：vuln→exploit 的唯一接口是 `{class}_exploitation_queue.json`，exploit 的每次上报都要过 ID 白名单；报告阶段再对账。三段全部可校验、可审计。
4. **LLM 产出的确定性渲染**：交付物 Markdown 全部由宿主从结构化工具调用**渲染**（renderers/*），模型不写 Markdown——格式漂移、半截文件、忘写章节这类问题从根上消失。collector 还记录"工具是否被跳过"，跳过渲染成占位符而非失败（activities.ts:276-280）。
5. **Temporial 编排 AI 工作流的范本**：确定性骨架（阶段/并行/门控）放 workflow 代码里人类可审计，不确定性（每阶段怎么打）放 agent 里；重试/心跳/取消/续跑全交给 Temporal 语义；`startToCloseTimeout: 2 hours + TRY_CANCEL + cancellationSignal→session.abort()` 解决"取消后 agent 空转到超时"（pi-executor.ts:293-323）。
6. **失败语义三态**（completed/partial/failed + not_assessed 块）：绝不允许"没测到"被渲染成"没问题"。resume 的 scope 校验（ScopeMismatchError）同理。
7. **父上下文保护**：提示词禁止父 agent 直接 read/grep 源码、强制 task 子代理委派；子代理花费通过 onUsage 精确回传计费（白盒扫描大头在子代理，不回传就"丢钱"）。
8. **bash 超时 pi 扩展**：默认 120s/上限 600s，把 harness 的坑（bash 无默认超时）用扩展补掉，且报错文本教模型怎么改。
9. **Playwright 会话命名隔离 + 共享登录态**：`-s=agent1..5` 并行不互踩；auth 预校验一次登录、全会话复用 state 文件，过期自行重登不覆盖共享文件。
10. **便宜检查前置**：preflight（URL 可达/凭证有效/配置合法）+ auth 真登录验证，都在烧钱的 agent 阶段之前。
11. **提示词工程细节**：`replaceLiteral` 防 `$` 插值事故；模式块裁剪让 agent 看不到无关指令；空规则整块删除不留 "None"；残留占位符检测；`llms.txt`/`llms-full.txt` 把仓库文档 LLM 友好化。
12. **审计与成本观测**：每个 agent 独立 AuditSession（并行安全，activities.ts:185-189 注释）；session.json 累计跨 resume 的指标；失败也结算已耗费用。

## 6. 局限与改进点

- **覆盖面**：只有 5 类（injection/xss/auth/authz/ssrf），且 OSS 的"白盒分析"就是 LLM 读代码——没有 AST/CPG/数据流分析器，深处污点路径全靠模型自觉追踪（提示词方法论再严也非保证）。商业平台才补了 CPG SAST/SCA。
- **无逐行动 HITL**：exploit 授权边界是配置文件，没有人工批准/否决回路；对生产近旁环境风险偏高（官方也只建议打非生产）。
- **prompt injection 面**：目标源码会被 pre-recon/task 子代理整仓阅读，恶意仓库可注入指令；code_path deny 只挡路径不挡内容。README 自认"别扫不信任的代码库"，但没有内容级防御（如指令标记、输出再校验对源码内容无效）。
- **验证依赖同一模型**：五道闸里 schema/ID/对账是确定性的，但"Level 3 实证"的判定者还是 LLM 自己——一个执意撒谎的模型可以伪造"拖到了数据"的证据文本（exploitation_steps/proof_of_impact 是自由文本字段）。宿主并不回放验证 PoC。
- **单模型策略**：全流程一个模型（resport 也用它），没有便宜模型做粗筛/贵模型做 exploit 的分层；成本下限高（官方说全流程 1-1.5 小时）。
- **报告二次综合漂移**：report agent 读拼接稿再结构化输出，信息经过两次 LLM 变换；ID 对账 + code_locations 关联缓解但没有根除改写失真。
- **运行栈重**：宿主要 Docker + 容器内 Temporal Server + Chromium，资源占用与部署复杂度对 CI 场景不算轻（虽然 SARIF 输出是朝 CI 设计的）。
- **pi 依赖耦合**：核心能力（工具、扩展、compaction、skills）建立在外部 `@earendil-works/pi-coding-agent` 与 `@playwright/cli` 特定版本（0.1.1）上，上游 breaking change 传导快；pi 自身文档还指向 pi.dev/models 目录。

## 7. 与其他已审计项目的对比

（首个已审计项目，留待横向对比填充。预填维度：编排=Temporal DAG+节点内自由会话；工具=pi 内置+task 子代理+playwright-cli skill；验证=五道闸（schema/ID 白名单/决策门/Level3 实证/报告对账）；上下文=文件黑板+子代理委派+compaction。）

| 维度 | 本项目（shannon） | 对比项目 |
|---|---|---|
| 编排方式 | Temporal workflow DAG，12 个专职 agent，5 路并行流水线 | 待补 |
| 工具执行 | pi harness（read/bash/...）+ 自研 task 子代理 + playwright-cli + TypeBox collector 工具 | 待补 |
| 验证机制 | 工具 schema 校验 + 队列 ID 白名单 + exploit 决策门 + Level3 实证 + 报告对账 | 待补 |
| 上下文管理 | 阶段间文件黑板；阶段内 todo+子代理委派+compaction；无 RAG | 待补 |

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `apps/worker/src/temporal/workflows.ts` | ✅ 已读 | 编排核心，逐段精读 |
| `apps/worker/src/temporal/activities.ts` | ✅ 已读 | 全部 activity 精读 |
| `apps/worker/src/services/agent-execution.ts` | ✅ 已读 | 生命周期 + 原子化收尾 |
| `apps/worker/src/session-manager.ts` | ✅ 已读 | AGENTS 注册表/校验器/浏览器会话映射 |
| `apps/worker/src/ai/pi/pi-executor.ts` | ✅ 已读 | harness 驱动 |
| `apps/worker/src/ai/pi/task-tool.ts` | ✅ 已读 | 子代理工厂 |
| `apps/worker/src/ai/pi/permission-system.ts` | ✅ 已读 | code_path deny |
| `apps/worker/src/ai/pi/bash-timeout/index.ts` | ✅ 已读 | bash 超时扩展 |
| `apps/worker/src/ai/models.ts` | ✅ 已读 | 模型/凭证/网关 |
| `apps/worker/src/ai/queue-schemas.ts` | ✅ 已读 | 队列 schema + submit 工具 |
| `apps/worker/src/ai/submit-tool.ts` | ✅ 已读 | 通用 submit 模式 |
| `apps/worker/src/services/prompt-manager.ts` | ✅ 已读 | 模板装配/插值/裁剪 |
| `apps/worker/src/collectors/exploit-collector.ts` | ✅ 已读 | 双层 schema + ID 白名单 |
| `apps/worker/src/services/exploitation-checker.ts` | ✅ 已读 | exploit 决策门 |
| `apps/worker/src/services/queue-validation.ts` | ⬜ 部分 | 存在性规则已读，后半解析细节略读 |
| `apps/worker/src/services/validate-authentication.ts` | ⬜ 部分 | 头部+submit 结构已读 |
| `apps/worker/src/services/preflight.ts` | ⬜ 部分 | 职责已知，未逐行 |
| `apps/worker/prompts/`（pre-recon/recon/vuln-injection/exploit-injection/report-executive + shared/*） | ✅ 已读 | 其余 4 类 vuln/exploit 提示词与 injection 同构，未逐行 |
| `apps/worker/prompts/pipeline-testing/*` | ⬜ | 快速测试模式的精简版（31 行/个） |
| `apps/cli/src/docker.ts` | ⬜ 部分 | 前 200 行精读 |
| `apps/cli/src/commands/*` `scan/*` | ⬜ | CLI 细节（setup/状态渲染）未逐行 |
| `apps/worker/src/services/*-renderer.ts`（pre-recon/recon/vuln/exploit/findings/report/sarif/pdf） | ⬜ | 确定性渲染器，模式已知（从结构化数据渲染 MD），未逐行 |
| `apps/worker/src/audit/*` `git-manager.ts` `config-parser.ts` | ⬜ | 审计/git/配置解析，职责已知 |
| `Dockerfile` `entrypoint.sh` `docker-compose.yml` | ⬜ 部分 | Dockerfile 精读 |

> 说明：核心链路（编排→执行→harness→提示词→collector→验证→安全）已逐行精读；渲染器/审计/CLI 属模式明确的辅助层，按抽样确认后标记"部分"。后续项目对比时如需某细节再回读。

## 9. 结论

**Shannon 的核心实现思路是：用 Temporal 把渗透测试流程固化为"确定性 DAG 骨架 + 每节点一个自由 LLM 会话"，agent 之间以文件为黑板、以 schema 校验的工具调用为唯一输出通道，上游白盒情报（file:line 级污点路径）喂给下游条件触发的实证 exploit，最终报告只收录通过"ID 白名单→队列决策→Level 3 实证→对账渲染"五道确定性闸门的发现。** 它是把"AI pentester"当软件工程产品（可重试、可续跑、可审计、可验证）而非 prompt demo 来造的范本，其中 submit-tool 强制结构化输出、collector 渲染交付物、队列即契约三件套对任何多 agent 安全工具都有直接复用价值。

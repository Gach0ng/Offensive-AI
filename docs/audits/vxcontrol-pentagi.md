# vxcontrol/pentagi 逐行代码审计

> 审计对象：PentAGI —— 全栈自托管 AI 渗透测试平台（Go 后端 + React 前端 + 微服务全家桶），"计划-执行-修订"式任务编排 + 专家委派 + 三重记忆系统。
>
> 说明：本项目规模大（后端 583 个 Go 文件约 5.3 万行 + 前端 + 4 套 compose 编排），核心链路（providers/controller/tools/templates/database/docker）经结构化测绘 + 关键文件抽读精审；UI/观测栈按模块职责登记。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/vxcontrol/pentagi |
| 本地路径 | `repos/agents/pentagi/` |
| 审计基线 commit | `ea665308baaff015b226f308438a68d929d0f29b`（2026-08-06，fix(deps): langchaingo v0.1.14-update.7） |
| 语言 / 规模 | Go 583 文件 ≈52,994 行（backend/）+ React/TS 前端；共 1,451 个文件 |
| Landscape 定位 | 类型：渗透 Agent（自托管平台）/ Stars：约 1.2k+（Trendshift 收录）/ 一句话：多专家委派的自治渗透平台，20+ Kali 工具、向量+图谱记忆、全链路可观测 |
| License | MIT + EULA（Docker 镜像分发受 EULA 约束，限合法渗透测试用途） |
| 关联论文 | 无 |
| 审计日期 / 人 | 2026-08-24 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：给安全工程师一个**自托管、多用户、可观测**的自治渗透平台：Web UI 提交目标 → 系统自主规划、执行、汇报；所有过程数据（消息链、工具调用、终端日志、成本）入库可审计。
- **输入输出**：输入目标 URL/任务描述（+ 可选用户文件上传 flowfiles、知识库）；输出漏洞报告（reporter 模板生成）、全程 engagement log（双语）、REST/GraphQL API 供自动化。支持 ask 屏障工具中途问人、done 终结。
- **差异化定位**：
  1. **平台化最彻底**：多租户（PG schema 级隔离）、OAuth、API token、Langfuse LLM 观测 + Grafana/VictoriaMetrics/Jaeger/Loki 系统观测、可选 Graphiti+Neo4j 知识图谱——把"AI pentest"当企业产品做；
  2. **计划-执行-修订循环**：任务先分解为 ≤15 个 subtask，**每完成一个 subtask 就让 LLM 修订剩余计划**（patch 语义：add/remove/modify/reorder），不是一次性计划或纯反应式；
  3. **专家公司隐喻**：主 agent 是"团队编排经理"，委派给 coder/pentester/installer/searcher/memorist/adviser 六个专家，专家各自独立会话递归复用同一 run-loop；
  4. **run-loop 四重护栏**：reflector 纠偏 / repeatingDetector 防死循环 / fixToolCallArgs 自动修参 / executionMonitor(mentor) 执行监督——目标是让小模型也能跑；
  5. **三重记忆**：工具结果自动向量化入 pgvector（Smart Memory）+ guide/answer/code 语义分库 + Graphiti 时序知识图谱。

## 2. 架构总览

**微服务全家桶**（docker-compose 系列）：核心（UI / Go API+Agent / PostgreSQL+pgvector / 任务队列）+ 知识图谱（Graphiti+Neo4j，可选）+ 观测（OTEL→VictoriaMetrics/Jaeger/Loki→Grafana）+ 分析（Langfuse+ClickHouse+Redis+MinIO）+ 工具（scraper 隔离浏览器、Kali 工具容器）。

**编排层级**（代码实证）：

```
用户输入 → flowWorker (controller/flow.go:986 worker循环)
              └─ 每 flow 一个主容器（LLM 选镜像, image_chooser.tmpl → providers.go:304）
         → taskWorker (task.go:302-375)
              ├─ GenerateSubtasks 计划分解 (provider.go:350, subtask_list 工具, ≤15)
              └─ 循环 { PopSubtask → subtaskWorker.Run → RefineSubtasks 计划修订 }
                    └─ subtask → 主 agent run-loop (performAgentChain)
                          └─ 委派工具 → 专家子 agent（递归同一 run-loop, 独立 msgchain）
                                └─ terminal/file 工具 → flow 主容器内执行
         → GetTaskResult 最终报告 (task.go:336)
```

- **编排方式**：**HTN 风格计划 + ReAct 式执行**。计划层是结构化 subtask 列表（DB 持久化、可 patch 修订）；执行层是自研 ReAct run-loop（明确不用 langchaingo 的 `agents.Executor`——只用其 MessageContent/Tool/CallOption 数据结构）。
- **LLM 调用层**：`pkg/providers/` 注册 10+ 家（OpenAI/Anthropic/Bedrock/Gemini/Ollama/DeepSeek/GLM/Kimi/Qwen/MiniMax/custom/openaicompat）+ 聚合器（OpenRouter/DeepInfra/Atlas/OpenCode Go plan）；`provider/agents.go:82-179` 有 `tool_call_id_collector/detector` 模板**探测各家工具调用 ID 格式**再适配——多 provider 兼容的独门手法。每 flow 创建时 LLM 还参与自举（image_chooser 选容器镜像、flow/task descriptor）。
- **执行环境**：每 flow 一个 Kali 主容器（全部 subtask/专家共享），`/work` 工作目录 bind 到宿主 data 目录；浏览器走独立 scraper 容器；可选 DooD（docker socket 只读挂载，README 有"给 agent docker 而不给宿主"专节）。

## 3. 目录结构逐层解读

```
backend/
├── cmd/                    # 入口（main）
├── pkg/
│   ├── providers/          # ★ 编排核心：provider.go(主链) performer.go(run-loop) performers.go(12个专家)
│   │   │                    #   handlers.go(委派工具handler) subtask_patch.go(计划修订) providers.go(注册表)
│   │   │                    #   assistant.go(聊天模式) tester/(provider连通性测试) 各LLM家目录+embeddings
│   ├── controller/         # flow/task/subtask worker + 日志/截图/提示词覆盖(prompter.go)
│   ├── tools/              # ★ 工具注册表(registry.go 40+工具) executor.go(执行+入库+记忆) terminal/file
│   │   │                    #   searchers/(10家搜索) memory.go graphiti_search.go flow_manager.go
│   ├── templates/          # 39 个 prompt 模板 + graphiti 模板（用户可在 prompts 表覆盖）
│   ├── database/           # sqlc 生成层 + models.go（Flow/Task/Subtask/Msgchain/Toolcall/...）
│   ├── docker/client.go    # 容器生命周期（1331 行）
│   ├── graphiti/           # 知识图谱客户端
│   ├── csum/               # 链式摘要（历史压缩）
│   ├── flowfiles/          # per-flow 用户文件工作区（上传/限额/净化/打包）
│   ├── server/ + graph/    # REST(gin) + GraphQL(gqlgen) + subscriptions
│   └── config/             # 环境变量配置 + 多租户(tenant.go) + 密钥脱敏正则
├── migrations/sql/         # 33 个 goose 迁移
└── fern/ gqlgen/ sqlc/     # API 定义与代码生成
frontend/                   # React + TS Web UI
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 入口与初始化

- `NewFlowWorker`（controller/flow.go:125）：建 DB flow 行 → `NewFlowToolsExecutor`（:207）→ `NewFlowProvider`（:211）→ goroutine `worker()`（:308）消费用户输入。
- Flow 自举三件套（providers.go:304-346）：LLM 在 flow 创建时用 `image_chooser` 选 Docker 镜像（失败回退 `vxcontrol/kali-linux`，providers.go:49）、生成 flow/task descriptor。**让 LLM 决定执行环境**是三个项目里独有的。
- 容器准备 `flowToolsExecutor.Prepare`（tools/tools.go:483-550）：容器名按 tenant+flowID 命名，`/work` 目录 bind，端口按 flowID 分配（client.go:109），网络 host 或自定义 bridge（:377-412）。

### 4.2 Agent 编排 / 任务规划 / 状态管理

- **计划分解**：`GenerateSubtasks`（providers/provider.go:350-431）→ `performSubtasksGenerator`（performers.go:94）——generator 模板强制"MUST 用 subtask_list 工具提交清单"、"最小化、不重叠、≤{{.N}} 个"（N=15 上限，provider.go:36）；结构化清单直接落库（subtasks.go:82-92），不是自由文本计划。
- **计划修订**（本项目编排精髓）：task 循环里每完成一个 subtask 调 `RefineSubtasks`（provider.go:433-538）——refiner 用 `subtask_patch` 工具输出补丁（add/remove/modify/reorder），`applySubtaskOperations`（subtask_patch.go:16-197，先删改后增排两遍扫描）应用；`fixSubtaskPatch`（:238-336）把引用无效 ID 的 modify 自动降级为 add——**对 LLM 补丁输出做防御性修复**。
- **run-loop 四重护栏**（providers/performer.go）：
  1. 迭代上限：通用 agent 100 轮 / 受限 agent 20 轮（:33-34），临上限优雅终止 reflector（:114-126）；
  2. `repeatingDetector`（:301-326）：重复工具调用检测，soft 4 次后中止（maxSoftDetectionsBeforeAbort）；
  3. `fixToolCallArgs`（:364→handlers.go:948）：工具参数校验失败后把错误交回 LLM 修参重试（toolcall_fixer 模板），各层重试上限 3 次；
  4. `executionMonitor`→mentor（:374-389 + performers.go:873-954，question_execution_monitor 模板）：执行过程监督，可叫停/纠偏。
  另有：无工具调用回合进 `performReflector`（:565-728，≤3 次，`isReflectorRetry` 防递归 :717）；可选 planning 前置步（`performPlanner` performers.go:811-870，把委派问题先过 adviser 拿计划再包裹原任务——为小模型设计）。
- **专家委派**：主 agent 提示词定位 "TEAM ORCHESTRATION MANAGER"（primary_agent.tmpl:1-3），六个委派工具（coder/installer/pentester/searcher/memorist/adviser，handlers.go:1004 实现），每个 handler 建独立 msgchain + 独立工具集 executor（GetCoderExecutor tools.go:1175 / GetPentesterExecutor :1296 等 13 个），**递归复用 performAgentChain**（如 performers.go:434）——专家还能再委派。barrier 工具 `done`/`ask` 触发链终止（provider.go:802-901 Barrier 回调）。
- **状态机**：FlowStatus/TaskStatus/SubtaskStatus/ToolcallStatus 枚举（database/models.go:149/567/522/697）+ `ErrFlowStateGuard`（tools/flow_manager.go:27-34）防对运行中 flow 的非法操作；assistant 聊天模式可 stop_flow/submit_flow_input 人工介入。
- **历史管理**：每轮工具后 `summarizer.SummarizeChain`（performer.go:236，csum/chain_summary.go:105）压缩历史；完整链 JSON 持久化 `msgchains` 表（updateMsgChain :872-896，含 usage/cost）。

### 4.3 工具层（shell 执行、工具封装、搜索、浏览器）

- **工具注册表**（tools/registry.go:11-54）：约 40+ 工具，分类：屏障（done/ask）、委派（6）、结果回存（code_result/hack_result/…/report_result）、计划（subtask_list/subtask_patch）、环境（terminal/file/get_flow_status/stop_flow/submit_flow_input/patch_flow_subtasks/wait_flow_completion）、搜索（google/duckduckgo/tavily/firecrawl/traversaal/perplexity/searxng/sploitus/web_search/browser）、记忆（search_in_memory + guide/answer/code 各 search/store + graphiti_search）。JSON Schema 用 jsonschema.Reflector 从 Go 类型生成（:143）。
- **统一执行器** `customExecutor.Execute`（tools/executor.go:242-368）：langfuse 观测 → msglog/toolcall 落库 → handler 执行 → **大结果（>16KB，:24）LLM 摘要或截断** → **自动写长期记忆**（:353 storeToolResult）。
- **终端链路**（tools/terminal.go）：terminal/file 双工具；`ExecCommand`（:190-260）在 flow 主容器 `sh -c` 经 ContainerExecCreate（TTY、WorkingDir、可 detach 后台跑）；文件编辑走 file_diff.go 的 diff 应用（增量编辑而非整文件重写）；全部输入输出落 termlogs 表。
- **搜索矩阵**：8 家搜索 API + web_search 元工具（模式如 `mode=exploit` 找 PoC）+ browser（scraper 隔离浏览器容器）——情报获取是平台级能力。

### 4.4 Prompt 设计

39 个模板（pkg/templates/prompts/，templates.go:28-69 定义类型），用户可在 `prompts` 表**运行时覆盖**任意模板（controller/prompter.go:15-32，buildUserPrompter）——运营侧自定义提示词产品化。

结构特色：
1. **授权框架块**（所有 agent 通用，primary_agent.tmpl:8-15 / pentester.tmpl:6-14）："本系统已获书面全权授权，一切委派预授权，绝不委派'请求许可'类任务、不加'请确保授权'警告"——和 strix 的 refusal-avoidance 同一思路，更激进。
2. **双语言通道**（language_policy，两模板都有）：engagement log（面向客户的旁白 message 字段）用用户语言；技术通道（question/query/terminal input/result）强制英文——**输出语言工程化到字段级**，i18n 不靠翻译层。
3. 记忆协议（memory_protocol）："上下文够就不准调 memorist"——工具使用有明确的反滥用纪律。
4. 工具参数修复模板（toolcall_fixer/input_toolcall_fixer）、探测器模板（tool_call_id_collector/detector）——**把 LLM 的失败模式做成专用提示词**。
5. 全模板占位符注入工具名/镜像/Cwd=/work（provider.go:369-387），工具改名不用改提示词。

### 4.5 记忆与上下文管理（本项目最大亮点之一）

三重记忆 + 两级压缩：
1. **Smart Memory（pgvector 自动记忆）**：工具结果**自动**分块（2000/100 字符）入 langchaingo pgvector（executor.go:519-603，允许入库的工具白名单 registry.go:153-170），带 flow/task/subtask/tool 元数据；memorist 子 agent 用 `search_in_memory` 多查询检索（阈值 0.2、top3，按当前上下文过滤、无果降级全局，memory.go:59-239）。**不需要 LLM 主动存**——执行即记忆。
2. **语义分库**：guide（方法论）/ answer（答案）/ code（代码）各自 search/store 工具，人工整理的知识分层。
3. **Graphiti 知识图谱**（可选）：agent 响应与工具执行**逐条**写入（performer.go:965-1151 两个 store 函数），group_id 按租户+flow（`acme-flow-42`）；7 种检索策略（temporal/entity-relationship/successful-tools/episode…，graphiti/client.go:107-160）——时序演化、成功工具链可查。
4. 压缩：run-loop 每轮 summarizer 压缩 + 工具结果 16KB 摘要闸（两级）；链完整 JSON 存 msgchains 可回放。

### 4.6 结果验证与去误报机制

PentAGI 的验证是**流程性**而非对账性（对照 shannon/strix）：
- **专家分工即互验**：pentester 只管打、coder 写码、adviser/mentor 监督、主 agent 汇总——验证靠角色分离 + mentor 监督轮（performers.go:873-954）。
- **结构化结果工具**：每个专家必须以 `*_result` 工具（hack_result/code_result/…）交结构化结果才算完成（barrier 语义）；最终报告走 `report_result`（reporter.tmpl 规定字段）。
- **run-loop 护栏**即质检：repeatingDetector 防原地打转、reflector 纠偏无工具空转、fixToolCallArgs 修坏参——保证"执行证据链"完整（全量 toolcall 落库可审计）。
- **没有**：报告级 LLM 去重（strix）、队列 ID 白名单/实证分级（shannon）。误报控制主要靠 pentester 模板纪律 + 报告模板要求附复现步骤。

### 4.7 报告生成 / 人工交互（HITL）

- 报告：task 级 `GetTaskResult`（task.go:336）+ reporter/task_reporter 模板 + report_result 工具；engagement log 双语旁白全程可读（前端实时流走 GraphQL subscriptions）。
- HITL：① `ask` 屏障工具——主 agent 可中途向用户提问（barrier 回调暂停链）；② assistant 聊天模式（controller/assistant.go:95 assistantWorker，可 stop_flow/submit_flow_input 管理运行中的 flow）；③ Web UI 全程可视化（消息链/工具调用/终端日志/截图/成本）。
- API：REST（gin，/api/v1，726 行路由）+ GraphQL（gqlgen + subscriptions）+ Bearer token——为集成/CI 留足面。

### 4.8 安全与隔离（沙箱、授权范围检查、密钥管理）

- **容器加固**（tools/tools.go:509-537 + docker/client.go）：`CapDrop: ALL` + 显式 CapAdd 白名单（CHOWN/…/SYS_PTRACE，可选 NET_ADMIN）；**故意不用 no-new-privileges**——注释明说保留 SUID 提权测试能力（渗透靶机需要）；PidsLimit 2048 防 fork 炸弹（:361-367）；日志轮转 10m×5。
- **多租户**：`TENANT_ID` → PostgreSQL 独立 schema（database/tenant.go:27 EnsureTenantSchema，DSN search_path 重写）+ 容器/卷/label 租户前缀 + Graphiti group/langfuse trace 均带租户；数据查询 userID 贯穿。
- **密钥管理**：全环境变量注入（config.go:80-176，10+ 家）；**密钥脱敏黑科技**——启动时把所有配置密钥编译成 regex，工具结果**入库前**统一替换（tools/tools.go:369-384 GetSecretPatterns）——防 API key 经终端回显泄漏进日志/LLM 上下文。
- flowfiles 路径净化：SanitizeFileName/IsWithinDir/"containment barrier"（flowfiles/files.go:121-357），上传限额 300MB/文件、1000 文件、2GB 总量。
- 授权范围：提示词层（授权框架块），无工具层目标范围强制（对比 shannon 的 code_path deny / strix 的系统验证范围块——pentagi 靠用户给什么任务就打什么）。

## 5. 值得借鉴的设计与技巧

1. **subtask_patch 计划修订协议**：执行中持续修订计划，补丁语义（add/remove/modify/reorder）+ `fixSubtaskPatch` 对 LLM 输出做防御性降级修复（无效 ID 的 modify→add）。比"一次性计划"和"纯反应式"都更贴近真实项目管理。
2. **run-loop 四重护栏**（reflector/repeatingDetector/fixToolCallArgs/executionMonitor）+ 全部上限常量集中定义（performer.go:28-39）——"让小模型也能用"的工程答案，可直接移植。
3. **执行即记忆**：工具结果自动分块入 pgvector，白名单控制哪些工具值得记；检索多查询+阈值+上下文过滤+降级。不依赖模型自觉调"记忆存储"。
4. **密钥 regex 脱敏**：配置里的所有密钥编译成正则、工具结果入库前替换——一行配置一层防泄漏，所有做 LLM+shell 的项目都该抄。
5. **工具调用 ID 格式探测器**（tool_call_id_collector/detector 模板）：先探测再适配各家 LLM 的工具调用 ID 病理差异——多 provider 兼容的实测派手法。
6. **LLM 选执行环境**（image_chooser）：flow 创建时按任务选容器镜像，失败回退默认——基础设施决策也交给模型。
7. **双语言通道到字段级**：message（旁白）与 question/result（技术）分语言，i18n 不做事后翻译。
8. **提示词产品化**：prompts 表运行时覆盖任意模板——运营可调优不动代码。
9. **专家公司隐喻 + 递归 run-loop**：六个专家是同一个 run-loop 的不同配置（提示词+工具集+迭代上限），新增专家=加一个 executor 工厂函数——架构扩展性好。
10. **全链路可观测**：msgchains（含 usage/cost）/toolcalls/termlogs 全落库 + Langfuse trace + OTEL 栈——AI 行为审计的完整数据底座。
11. **文件 diff 编辑**（file_diff.go）：容器内文件按 diff 增量编辑而非整写——贴近真实编码 agent 行为。

## 6. 局限与改进点

- **验证层薄**：无报告去重、无 PoC 机器复核、无实证分级——误报控制全靠提示词纪律与 mentor 监督（LLM 查 LLM）；对照 shannon 的确定性闸门是明显短板。
- **无目标范围强制**：没有工具层 scope 拦截（对比 strix 的 Caido scope_rules / shannon 的路径 deny），范围约束只在提示词/用户自觉层。
- **共享单容器**：flow 内所有 subtask/专家共容器共 `/work`——跨 subtask 状态污染风险（也是特性：状态延续）；SUID 保留 + 可选 DooD 提权面大，依赖容器边界兜底。
- **复杂度重**：全套 compose 十余服务（ClickHouse/Neo4j/MinIO…），最小部署门槛高；Go+sqlc+gqlgen+fern 的工程链对二次开发要求高。
- 计划修订每 subtask 一次 LLM 调用 + mentor 监督轮 + summarizer + fixer——**token 成本杠杆多**，小模型友好是以调用次数换的。
- 迭代上限 100 轮/通用链在大任务下仍可能截断（有优雅终止 reflector 缓解）。

## 7. 与其他已审计项目的对比

| 维度 | pentagi（本项目） | shannon | strix |
|---|---|---|---|
| 编排方式 | **计划-执行-修订循环**（subtask 列表+patch 修订）+ 专家委派（递归 run-loop） | 固定 12 节点 Temporal DAG | 动态蜂群（LLM 现场 spawn 树） |
| 工具执行 | 统一 executor（40+ 工具，10 家搜索），容器内 sh -c | pi harness + task 子代理 + playwright-cli | agents SDK capability + Kali + Caido |
| 验证机制 | 角色分工 + mentor 监督 + 结构化结果工具（无对账/去重） | 五道确定性闸（最强） | 报告硬校验 + LLM 去重法官 |
| 上下文/记忆 | **最强**：pgvector 自动记忆 + 语义分库 + Graphiti 图谱 + 双级压缩 | 文件黑板 + 子代理委派 | SQLite 会话 + 溢写 + 共享 notes |
| HITL | ask 屏障 + assistant 聊天 + 全程 UI 流 | 配置即授权（无中途闸） | respond_to_user 协议 + TUI |
| 部署形态 | 自托管多租户平台（观测全家桶） | 本地 CLI + Docker | 本地 CLI/TUI + Kali 沙箱 |

三种流派就此齐了：**shannon=确定性流水线派，strix=动态蜂群派，pentagi=平台化计划修订派**。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `pkg/providers/performer.go` | ✅ 部分 | run-loop 常量/护栏机制精读（1151 行全量结构测绘） |
| `pkg/providers/provider.go` `performers.go` `handlers.go` `providers.go` | ✅ 部分 | 结构测绘 + 关键行号落点；subtask_patch.go 机制精读 |
| `pkg/controller/flow.go` `task.go` `subtask.go` | ✅ 部分 | worker 循环与编排链条精读（经测绘） |
| `pkg/tools/registry.go` `executor.go` `terminal.go` `tools.go` | ✅ 部分 | 工具清单/执行链/记忆写入/容器加固精读 |
| `pkg/templates/prompts/primary_agent.tmpl` `pentester.tmpl` | ✅ 已读 | 抽读精读；其余 37 个按用途登记 |
| `pkg/docker/client.go` | ⬜ 部分 | 加固参数精读（经测绘） |
| `pkg/database/models.go` `migrations/` | ⬜ 部分 | 模型清单与状态机枚举已登记 |
| `pkg/server/` `graph/` `frontend/` | ⬜ | API/UI 层按职责登记 |
| `pkg/graphiti/` `pkg/csum/` `pkg/flowfiles/` | ⬜ 部分 | 机制经测绘登记 |
| `pkg/config/` | ✅ 部分 | 密钥/租户/脱敏机制精读 |

> 审计方法注记：本项目采用"结构化测绘（Explore 全库扫描产出 file:line 落点）+ 关键文件人工抽读校验"的混合方式，结论均有代码落点支撑；与 shannon/strix 的逐文件精读相比粒度稍粗，后续横向对比需要细节时按本表回读。

## 9. 结论

**PentAGI 的核心实现思路是：把渗透测试组织成一家"AI 公司"——编排经理先把任务分解为结构化 subtask 计划，执行中每完成一步就用补丁协议修订计划，把实际操作委派给共享同一套自研 ReAct run-loop（带 reflector/重复检测/参数修复/mentor 监督四重护栏）的六个专家，所有工具执行自动沉淀为 pgvector 向量记忆与 Graphiti 知识图谱，全过程消息链/工具调用/成本落库可审计。** 它是"平台派"代表作：验证闸门弱于 shannon、灵活性弱于 strix，但记忆系统、多租户、可观测性和"小模型也能跑"的工程化最彻底。

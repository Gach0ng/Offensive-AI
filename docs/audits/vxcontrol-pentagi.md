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

- **计划分解**：`GenerateSubtasks`（providers/provider.go:350-431）→ `performSubtasksGenerator`（performers.go:94）——generator 模板强制"MUST 用 subtask_list 工具提交清单"、"最小化、不重叠、≤{{.N}} 个"（N=15 上限，provider.go:36），并给出**任务分布黄金比**：~10% 环境准备/事实收集 + ~30% 多路径实验 + ~30% 评估选路 + ~30% 沿选定路径聚焦执行（generator.tmpl:66-71，refiner.tmpl:163-167 同款）；结构化清单直接落库（subtasks.go:82-92）。
- **计划修订**（本项目编排精髓）：task 循环里每完成一个 subtask 调 `RefineSubtasks`（provider.go:433-538）——refiner 用 `subtask_patch` 工具输出**增量操作**（add[after_id 定位]/remove/modify[部分更新]/reorder），"任务完成 = 移除全部剩余 subtask"、空数组=无需改动（refiner.tmpl:200-231 带示例）；`applySubtaskOperations`（subtask_patch.go:16-197，先删改后增排两遍扫描）应用；`fixSubtaskPatch`（:238-336）把引用无效 ID 的 modify 自动降级为 add。refiner 还有**失败分析框架**：失败四分类（技术/环境/概念/外部），概念性失败要求整体换路而非变体重试，"同类方法失败 2 次后必须探索完全不同的路径"（refiner.tmpl:130-148）。
- **run-loop 四重护栏**（providers/performer.go，已全文亲读）：
  1. 迭代上限：通用 agent 100 轮（assistant/primary/pentester/coder/installer）/受限 agent 20 轮（performer.go:89-104，可被 `MAX_GENERAL_AGENT_TOOL_CALLS` 覆盖但保底 ≥2×shutdown 迭代）；**临上限优雅终止**：距上限 ≤3 轮时不再调模型，而是注入合成消息"我快到迭代上限了无法继续多轮链"喂给 reflector 让 agent 自己收尾交结果（performer.go:114-126）——比硬截断优雅；
  2. `repeatingDetector`（:301-326）：重复调用先返回软警告"该工具在重复，请换工具"，累计到阈值+4 次才中止链；
  3. 工具参数修复循环（:333-372）：执行失败→取该工具 JSON schema→`fixToolCallArgs` 让 LLM 按最小改动修参重试（≤3 次）；**ErrFlowStateGuard 错误跳过修复**（:346-353，注释明说：状态错误不是参数问题，修参无意义，直接上抛）；上游还有防御：模型产出的工具参数 JSON 无效时先清洗控制字符、仍无效则替换为 `{}` 让修复器重建（callWithRetries 的 fillResult，:455-464）；
  4. `executionMonitor`→mentor（:374-389，默认关，`EXECUTION_MONITOR_ENABLED`）：同工具连续 5 次或总调用 10 次触发 mentor 评审，评审结果以 `<enhanced_response><original_result>…<mentor_analysis>…` 格式**注入工具响应本体**（performer.go:387 formatEnhancedToolResponse）。
  另有：无工具调用回合进 `performReflector`（:565-728，≤3 次，`isReflectorRetry` 上下文标记防递归 :717-723）；可选 planning 前置步（`performPlanner` performers.go:811-870，默认关 `AGENT_PLANNING_STEP_ENABLED`）。
- **reflector 的真实机制**（全读后修正此前描述）：agent 输出纯文本而非工具调用时，reflector agent（"TOOL CALL WORKFLOW ENFORCER"，reflector.tmpl）**扮演用户**用聊天口吻（无问候无落款、<500 字符）生成一条劝导消息——"系统只处理结构化工具调用，完成任务必须用这些 barrier 工具"——然后把它作为**新的 Human 消息追加进链**再调模型（performer.go:683-684）。即：把"格式纠错"伪装成"用户回话"，模型天然会响应。assistant 类型例外：它允许纯文本结束（processAssistantResult，:141-143）。
- **专家委派**：主 agent 提示词定位 "TEAM ORCHESTRATION MANAGER"（primary_agent.tmpl:1-3），六个委派工具（coder/installer/pentester/searcher/memorist/adviser，handlers.go:1004 实现），每个 handler 建独立 msgchain + 独立工具集 executor（GetCoderExecutor tools.go:1175 / GetPentesterExecutor :1296 等 13 个），**递归复用 performAgentChain**（如 performers.go:434）——专家还能再委派。**委派权限表写进 adviser 模板**：谁可用什么完成工具、可委派给谁（adviser.tmpl:13-20 的六行表格），使 mentor 能给出"建议调用 X 完成工具/建议委派给 Y"的准确指引。barrier 工具 `done`/`ask` 触发链终止（provider.go:802-901 Barrier 回调）。
- **状态机**：FlowStatus/TaskStatus/SubtaskStatus/ToolcallStatus 枚举（database/models.go:149/567/522/697）+ `ErrFlowStateGuard`（tools/flow_manager.go:27-34）防对运行中 flow 的非法操作；assistant 聊天模式可 stop_flow/submit_flow_input 人工介入。
- **历史管理**：每轮工具后 `summarizer.SummarizeChain`（performer.go:236，csum/chain_summary.go:105）压缩历史；**摘要失败被吞掉**（仅记 langfuse 警告事件，链继续不压缩，:237-251）——可用性优先于优化的取舍；完整链 JSON 持久化 `msgchains` 表（updateMsgChain :872-896，含 usage/cost）。

### 4.3 工具层（shell 执行、工具封装、搜索、浏览器）

- **工具注册表**（tools/registry.go:11-54）：约 40+ 工具，分类：屏障（done/ask）、委派（6）、结果回存（code_result/hack_result/…/report_result）、计划（subtask_list/subtask_patch）、环境（terminal/file/get_flow_status/stop_flow/submit_flow_input/patch_flow_subtasks/wait_flow_completion）、搜索（google/duckduckgo/tavily/firecrawl/traversaal/perplexity/searxng/sploitus/web_search/browser）、记忆（search_in_memory + guide/answer/code 各 search/store + graphiti_search）。JSON Schema 用 jsonschema.Reflector 从 Go 类型生成（:143）。
- **统一执行器** `customExecutor.Execute`（tools/executor.go:242-368）：langfuse 观测 → msglog/toolcall 落库 → handler 执行 → **大结果（>16KB，:24）LLM 摘要或截断** → **自动写长期记忆**（:353 storeToolResult）。
- **终端链路**（tools/terminal.go）：terminal/file 双工具；`ExecCommand`（:190-260）在 flow 主容器 `sh -c` 经 ContainerExecCreate（TTY、WorkingDir、可 detach 后台跑）；文件编辑走 file_diff.go 的 diff 应用（增量编辑而非整文件重写）；全部输入输出落 termlogs 表。
- **搜索矩阵**：8 家搜索 API + web_search 元工具（模式如 `mode=exploit` 找 PoC）+ browser（scraper 隔离浏览器容器）——情报获取是平台级能力。

### 4.4 Prompt 设计（39+2 模板已全文亲读，2026-08-24 补读升级）

模板定义 `pkg/templates/templates.go:28-69`，模板体 `pkg/templates/prompts/*.tmpl`（39 个，共 4431 行）+ `graphiti/*.tmpl`（2 个）；渲染 `templates.Prompter.RenderTemplate`；**用户可在 prompts 表运行时覆盖任意模板**（controller/prompter.go:15-32）。

**A. 通用骨架**（专家模板共享，读 pentester/coder/primary/generator/refiner 五份全文后归纳）：
`# 角色定义` → `授权框架`（反拒答块）→ **语言政策**（双通道：见下）→ 记忆协议（含**匿名化规则**）→ Graphiti 检索协议（可选）→ 容器约束（镜像/端口/超时/四禁令：无 GUI、无 Docker host、无 UDP 扫描、不经 Docker 镜像装软件）→ 终端协议（每命令显式 cd、绝对路径、同命令 ≤3 次、detach 语义）→ **摘要感知协议** → 团队专家表 → 委派规则（"先自己解，再委派"）→ 执行上下文（XML 注入 Flow/Task/Subtask）→ 任务材料（uploads/resources 只读）→ **导师监督**（增强响应格式说明）→ 完成要求（必须用 barrier 工具收尾）→ `{{.ToolPlaceholder}}`。

**B. 关键设计逐条**：

1. **双语言通道（字段级 i18n）**：每个工具参数的频道由其 JSON-schema description 钉死——`message` 字段是 engagement log（用户语言，1-2 句旁白）；`question/query/input/result/代码/注释/标识符`是技术通道（强制英文）。理由也写明："向量库/图谱/搜索引擎按英文索引、跨 engagement 共享，非英文查询检索不到、非英文存储永远捞不回"（pentester.tmpl:32）。reporter 是"收尾抄写员"：只消费英文技术材料、产出用户语言的结案记录，技术标识符（CVE/IP/端口/CLI 名）保持字面不译（reporter.tmpl:12-18）。
2. **记忆匿名化协议**：入向量库的 guide/code 必须匿名化——IP→`{target_ip}`、域名→`{target_domain}`、凭证→`{username}/{password}`、密钥→`{api_key}/{token}`，非标端口→`{port}`（80/443 保留）（pentester.tmpl:44-52；coder 版 :44-52 另有 `{remote_host}/{callback_domain}/{api_endpoint}`）。**跨目标可复用性与敏感数据不留存，在写入端强制。**
3. **Graphiti 检索协议**（pentester.tmpl:56-145）：受控分类法——17 个节点标签（Host/Port/Service/Vulnerability/Credential/ValidAccess/PrivChange/AttackTechnique…）+ 边类型含**漏洞生命周期三级**：`DETECTED_VULNERABILITY（扫描器命中未验证）→ CONFIRMED_VULNERABILITY（已验证）→ HAS_VULNERABILITY（已利用）`；禁造新标签；6 种检索类型各配用法/示例（recent_context 为默认起点、successful_tools 带 min_mentions、entity_relationships 要求 center_node_uuid **逐字复制自上次结果的 UUID 字段、绝不许编造**）；查询构造给了好/坏例（"nmap -sV scan results showing open ports on 192.168.1.100" 好，"vulnerabilities" 坏）。**"Graphiti=发生过什么（情景记忆），guide 库=该怎么做（方法论）"**的双记忆定位（:134-141）。
4. **摘要感知协议**（所有 agent 通用，pentester.tmpl:187-221）：教模型**识别**历史中的压缩标记（两种形态：summarization 工具调用对、前缀标记的 Completion），把它们**当历史事实读但绝不模仿**——禁止复用前缀、禁止调用该系统工具、禁止用纯文本模拟工具调用。这是"上下文压缩"与"模型模仿污染"的对抗设计：压缩器在历史里留了系统标记，就必须教模型别把它当模板。
5. **OOB 攻击基础设施教学**（adviser.tmpl:64-73）：容器端口专门绑定用于接收回调（反弹 shell/DNS 外带/XXE OOB/SSRF 验证）；公网 IP 未知时教 `curl -s https://api.ipify.org` 探测；"agent 必须只用分配端口——其他端口不转发（bridge）或与宿主冲突（host 网络）"。summarizer 模板还要求**摘要时必须显式保留公网 IP/OOB 回调配置**（full_execution_context.tmpl 指令第 5 条）——压缩不能丢 OOB 基础设施信息。
6. **CLI 幻觉旗标纪律**（pentester.tmpl:332-339）："同一字母在不同工具含义不同（-p 在 nmap 是端口、在 hydra 是密码）"、"绝不发明 --help 里没有的输出旗标"、"要保存/丢弃输出用 shell 重定向而不是猜旗标"、"要解析输出就显式请求结构化格式（nmap -oX、-json）"、"payload 含 shell 元字符必须引号包裹——否则是 shell 而不是目标工具在解释它们"。**把 LLM 用 CLI 工具的五大坑写成军规。**
7. **msfconsole 工作流协议**（pentester.tmpl:294-351）："永不裸跑 msfconsole（必挂 -x）"、单命令全链 `exploit; sleep 20; sessions -l; exit`（每进程隔离，session 不跨进程）、启动前 `netstat -tulnp` 查端口、孤儿清理 `pkill -f msfconsole`、复杂流程走 msfrpcd 常驻（detach=true）+ connect 复用。adviser 模板还带"常见错误识别清单"（六大错误模式）用于 mentor 评审时对照。
8. **detach 双模式语义**（pentester.tmpl:171-183）：detach=true=500ms 后返回"后台已启动"（守护进程类：msfrpcd/nc -l/http.server/tcpdump，timeout 600-1200）；detach=false=等完成返回输出（扫描器类：nmap/gobuster/curl，必须预估准超时）。**每命令显式 cd（容器执行无持久状态）**。
9. **导师增强响应格式**（全模板统一）：工具响应可能是 `<original_result>`+`<mentor_analysis>`（进度评估/发现问题/替代方案/下一步）的双段结构，"mentor 可判定任务不可行应终止"；mentor 评审由 executionMonitor 阈值触发或 agent 主动 advice。
10. **adviser 三模式**（adviser.tmpl:135-162）：直接技术咨询 / Planner（子任务前 3-7 步清单，question_task_planner 是"我接到任务请帮我列检查单"的第一人称请求）/ Mentor（执行监控）；**咨询语气军规**：只用 "Recommend/Suggest/Consider"，禁祈使句（好坏例对照：BAD "STOP NOW" / GOOD "Recommend stopping…"，:172-178）——建议权在 agent。
11. **enricher——顾问前置事实检索员**（enricher.tmpl，258 行，此前审计遗漏的角色）：adviser 收到问题前，enricher 先跑一遍记忆/文件系统/终端/浏览器**只收集 adviser 还没有的事实**——"只给事实不给答案（回答是 adviser 的事）、不重复问题/代码/输出/执行上下文（adviser 已有）、没有增量信息就返回空"；好/坏例明确（好："知识图谱显示此前 pentester 在该目标发现 8080 端口 Apache 2.4.49"；坏："我建议你…"）。**检索与建议分离的角色设计**——RAG 的检索阶段独立成 agent，防止顾问被检索噪声带偏。
12. **工具调用 ID 探测器对**（tool_call_id_collector/detector，此前一句话带过，机制现已亲读）：collector 让模型**并行调某函数 3 次**（值 42、随机上下文干扰）以采集该 provider 真实的工具调用 ID 样本；detector 把样本交给 LLM 推断**模式模板**（`toolu_{r:24:b}`、`call_{r:36:x}`、`{f}:{r:1:d}`，字符集语法 d/l/u/a/x/h/H/b）——失败模板会作为 previous_attempts 回喂迭代。**运行时指纹提取 provider 的 ID 格式，用于流式函数调用重组。**
13. **辅助生成器**：image_chooser（按任务选容器镜像，渗透默认 kali、模糊回退默认镜像）、language_chooser（输出语言探测，英文词表输出）、flow/task_descriptor（{{.N}} 字符标题生成器，用户语言）——三个"小 LLM 工具调用"把元数据生成自动化。
14. **结构化输入包装**：subtasks_generator/refiner 的上下文用 XML 包装（`<user_task><input>` 反复强调"这是真实目标不是示例"——防模型把主任务当演示）；refinement_context 带 ExecutionState/ExecutionLogs；question_* 家族是各专家的"第一人称请求信"（memorist："把复杂问题拆成精确向量查询、用完整句子匹配"；searcher："内存→专用工具→通用搜索引擎，**最多 3-5 次搜索，信息够就停**"）。
15. **Graphiti 写入模板**（graphiti/agent_response/tool_execution.tmpl）：固定字段的紧凑摘要（Agent/Response/Context: Task,Subtask 与 Tool/Description/IsBarrier/Arguments/Status/Result）——图谱节点内容即结构化执行回执。

**C. 与提示词相关的运行时细节**（performer.go 亲读补充）：reasoning 保存用"通用模式"（TextPartWithReasoning，注释：靠去重对所有 provider 有效）；Gemini 的 reasoning 藏在首个工具调用里的怪癖被显式处理（callWithRetries fillResult :441-445）；streamID/thinking 只挂在**第一个**工具响应上省内容（execToolCall :277-283）。

### 4.5 记忆与上下文管理（本项目最大亮点之一）

三重记忆 + 两级压缩：
1. **Smart Memory（pgvector 自动记忆）**：工具结果**自动**分块（2000/100 字符）入 langchaingo pgvector（executor.go:519-603，允许入库的工具白名单 registry.go:153-170），带 flow/task/subtask/tool 元数据；memorist 子 agent 用 `search_in_memory` 多查询检索（阈值 0.2、top3，按当前上下文过滤、无果降级全局，memory.go:59-239）。**不需要 LLM 主动存**——执行即记忆。
2. **语义分库**：guide（方法论）/ answer（答案）/ code（代码）各自 search/store 工具，人工整理的知识分层。
3. **Graphiti 知识图谱**（可选）：agent 响应与工具执行**逐条**写入（performer.go:965-1151 两个 store 函数），group_id 按租户+flow（`acme-flow-42`）；7 种检索策略（temporal/entity-relationship/successful-tools/episode…，graphiti/client.go:107-160）——时序演化、成功工具链可查。
4. 压缩：run-loop 每轮 summarizer 压缩 + 工具结果 16KB 摘要闸（两级）；链完整 JSON 存 msgchains 可回放。**摘要器的量化预算**（config.go:97-104 亲读）：QA 分段式压缩——保留最近 51200 字节原文、每段上限 16384 字节、QA 段最多 10 段/共 65536 字节、保留最近 1 段完整 QA；assistant 模式预算更大（最近 76800 字节、7 段/76800 字节、保留 3 段——聊天历史更值钱）。summarizer 模板本体是"高保真压缩器"指令：函数名/API 端点/参数/URL/路径/版本/数值/因果链**无一例外保留**、已摘要内容**优先全保留**、输出零元评论。

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
- **配置默认值面**（config.go 亲读摘录，默认值=设计决策化石）：`TERMINAL_TOOL_TIMEOUT=1200s`（与提示词"硬限 20 分钟"一致）；`DOCKER_PORTS_BASE=28000`（OOB 端口基址）；`EXECUTION_MONITOR_ENABLED=false`+同工具 5 次/总 10 次阈值（监督默认关——省 token）；`AGENT_PLANNING_STEP_ENABLED=false`（规划步默认关）；`MAX_GENERAL/LIMITED_AGENT_TOOL_CALLS=100/20`；嵌入批 512/单文本 8192 字节/strip 换行；DuckDuckGo 默认开、Sploitus 默认关；`ASSISTANT_USE_AGENTS=false`（聊天模式默认不拉专家）；DB 连接池 25/5/向量 10。**"默认关"的两个开关正是给小模型准备的护栏，说明默认部署按强模型+成本优先配置。**

## 5. 值得借鉴的设计与技巧

1. **subtask_patch 计划修订协议**：执行中持续修订计划，补丁语义（add/remove/modify/reorder）+ `fixSubtaskPatch` 对 LLM 输出做防御性降级修复（无效 ID 的 modify→add）。比"一次性计划"和"纯反应式"都更贴近真实项目管理。
2. **run-loop 四重护栏**（reflector/repeatingDetector/fixToolCallArgs/executionMonitor）+ 全部上限常量集中定义（performer.go:28-39）——"让小模型也能用"的工程答案，可直接移植。
3. **执行即记忆**：工具结果自动分块入 pgvector，白名单控制哪些工具值得记；检索多查询+阈值+上下文过滤+降级。不依赖模型自觉调"记忆存储"。
4. **密钥 regex 脱敏**：配置里的所有密钥编译成正则、工具结果入库前替换——一行配置一层防泄漏，所有做 LLM+shell 的项目都该抄。
5. **工具调用 ID 格式探测器**（tool_call_id_collector/detector 模板，机制已亲读）：collector 诱导模型并行调函数 3 次采集真实 ID 样本 → detector 让 LLM 归纳模式模板（`toolu_{r:24:b}` 语法，8 种字符集代号）→ 失败尝试作为 previous_attempts 回喂迭代——多 provider 兼容的实测派手法。
6. **LLM 选执行环境**（image_chooser）：flow 创建时按任务选容器镜像，失败回退默认——基础设施决策也交给模型。
7. **双语言通道到字段级**：message（旁白）与 question/result（技术）分语言，理由写明（向量库按英文索引跨任务共享），reporter 作为"翻译收尾抄写员"角色——i18n 不做事后翻译。
8. **记忆写入端匿名化**：guide/code 入库前把 IP/域名/凭证/密钥替换为占位符（pentester/coder 各有一套占位符表）——跨目标复用 + 敏感数据不沉淀，一举两得。
9. **摘要感知协议 + 摘要高保真指令**：压缩器在历史里留系统标记，就同时教所有 agent"识别标记、当事实读、绝不模仿"；summarizer 本体是"技术细节无一例外保留、已摘要内容优先全保"指令 + 量化字节预算（51200/16384/65536）。
10. **reflector 的用户扮演机制**：纯文本输出→扮演用户的纠偏消息作为 Human 轮注入再调模型——比"报错重试"更贴合模型天性（响应用户）；近迭代上限时注入"我快到上限了"合成消息触发自主收尾。
11. **enricher 检索/建议分离**：顾问回答前的独立事实收集员，"只给增量事实、可返回空、绝不给建议"——RAG 检索阶段独立成角色。
12. **提示词产品化**：prompts 表运行时覆盖任意模板——运营可调优不动代码。
13. **CLI 军规库**：幻觉旗标五军规（跨工具旗标假设/禁造输出旗标/重定向优先/显式要结构化输出/payload 引号）、msfconsole 六错误模式清单、detach 双模式语义、OOB 端口纪律——**把基础设施的每个坑前置写进提示词**。
14. **专家公司隐喻 + 递归 run-loop**：六个专家是同一个 run-loop 的不同配置（提示词+工具集+迭代上限），新增专家=加一个 executor 工厂函数——架构扩展性好；adviser 里的**委派权限表**让 mentor 建议永远指名道姓（"建议调用 X 完成工具/建议委派给 Y"）。
15. **全链路可观测**：msgchains（含 usage/cost）/toolcalls/termlogs 全落库 + Langfuse trace + OTEL 栈——AI 行为审计的完整数据底座。
16. **文件 diff 编辑**（file_diff.go）：容器内文件按 diff 增量编辑而非整写——贴近真实编码 agent 行为。
17. **防御性细节三则**（亲读新增）：工具参数 JSON 无效→清洗控制字符→仍无效替换 `{}` 交修复器重建；ErrFlowStateGuard 状态错误跳过修参重试（修参救不了状态问题）；摘要失败吞掉保链继续（可用性优先）。

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
| `pkg/providers/performer.go` | ✅ 亲读 | 1-740 逐段精读；740-1151（graphiti 存储/辅助函数）经调用面+测绘确认 |
| `pkg/templates/prompts/`（39 个 .tmpl，4431 行） | ✅ 亲读 | 大模板（pentester/coder/primary/generator/refiner/adviser/enricher/reflector/reporter/summarizer/上下文×3/修复×2/探测器×2/选择器×2/descriptor×2/包装器/question×11）全文；memorist/installer/searcher/assistant 读角色头+全段清单（与已读五份骨架同构，专属段已摘） |
| `pkg/templates/graphiti/*.tmpl` | ✅ 亲读 | 2 个写入模板 |
| `pkg/config/config.go` | ✅ 部分 | 全部 envDefault 默认值面亲读；加载/租户逻辑经测绘 |
| `pkg/providers/provider.go` `performers.go` `handlers.go` `providers.go` | ⬜ 部分 | 调用契约经 performer.go 调用点亲读交叉验证；函数体靠测绘 |
| `pkg/controller/flow.go` `task.go` `subtask.go` | ⬜ 部分 | worker 循环与编排链条经测绘 |
| `pkg/tools/registry.go` `executor.go` `terminal.go` `tools.go` | ⬜ 部分 | 工具清单/执行链/记忆写入/容器加固经测绘 |
| `pkg/docker/client.go` | ⬜ 部分 | 加固参数经测绘 |
| `pkg/database/models.go` `migrations/` | ⬜ 部分 | 模型清单与状态机枚举已登记 |
| `pkg/server/` `graph/` `frontend/` | ⬜ | API/UI 层按职责登记 |
| `pkg/graphiti/` `pkg/csum/` `pkg/flowfiles/` | ⬜ 部分 | 机制经测绘登记（csum 预算已从 config 亲读） |

> **2026-08-24 补读升级说明**：本审计按新方法论标准（见 audit-template 头部）补读了提示词全文（39+2 模板）、performer.go 核心循环、config 默认值面，新增 enricher 角色、reflector 用户扮演机制、记忆匿名化协议、摘要感知协议、Graphiti 漏洞生命周期分类法、CLI 军规库、OOB 基础设施教学、委派权限表等此前遗漏的关键设计。provider.go/performers.go/handlers.go 函数体仍为测绘级（行为契约已经核心循环调用点交叉验证），需要时按表回读。

## 9. 结论

**PentAGI 的核心实现思路是：把渗透测试组织成一家"AI 公司"——编排经理先把任务分解为结构化 subtask 计划（10/30/30/30 分布黄金比），执行中每完成一步就用增量补丁协议修订计划（含失败四分类换路规则），把实际操作委派给共享同一套自研 ReAct run-loop（reflector 用户扮演纠偏/重复检测/参数修复/mentor 增强响应四重护栏）的六个专家，顾问背后还有独立的事实检索员（enricher）与三模式身份（咨询/规划/监督）；所有工具执行自动沉淀为**匿名化的** pgvector 向量记忆与带漏洞生命周期分类法的 Graphiti 知识图谱，提示词层用双语言通道、摘要感知协议、CLI 军规库把工程纪律压进每个字段，全过程消息链/工具调用/成本落库可审计。** 它是"平台派"代表作：验证闸门弱于 shannon、灵活性弱于 strix，但记忆系统、多租户、可观测性和"小模型也能跑"的工程化最彻底。

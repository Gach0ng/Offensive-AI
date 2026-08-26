# zakirkun/guardian-cli 逐行代码审计

> 审计对象：Guardian —— Python CLI 渗透测试自动化框架："企业级 AI 驱动渗透平台"。多 agent（Planner/Tool Selector/Analyst/Reporter + 红蓝法官辩论分诊 + 视觉分诊）× 50 工具 × 8 AI 提供商（含插件契约）+ RAG 知识库 + 学习型工具排序。值得注意：**已审计过的 garak/pyrit 在这里是它的 B12 工具**——景观内项目开始互相引用。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/zakirkun/guardian-cli |
| 本地路径 | `repos/agents/guardian-cli/` |
| 审计基线 commit | `51864a8`（merge PR #21 feat/add-litellm-provider） |
| 语言 / 规模 | Python 3.11+，~18.8k 行（core/cli/ai/tools/workflows+tests）；带 CLAUDE.md（AI 协作开发痕迹） |
| Landscape 定位 | 类型：渗透 Agent / Stars：中 / 一句话：多提供商多 agent 渗透 CLI（辩论分诊+RAG 防幻觉+学习型选工具） |
| License | MIT |
| 关联论文 | 无（README 声明 F1≥基线+5pp 等内部验收指标） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：授权渗透的全流程 CLI 自动化——威胁建模→规划→选工具→执行→分析→辩论去误报→报告；YAML 工作流可编排或自主模式。
- **差异化定位**：**防幻觉与去误报作为一等公民**——RAG 接地（"只用精确 ID"）、辩论分诊（红/蓝/法官三角色）、学习型工具排序（低置信弃权回退 LLM）、廉价法官选轮（~10x 成本降）。工程纪律罕见地好（类型注解/black/pre-commit/CI/测试）。

## 2. 架构总览

```
CLI（typer：scan/recon/analyze/report/kb/models/workflow/ai_explain/telemetry）
   ▼
WorkflowEngine（run_workflow YAML 步骤并发 / run_autonomous 主循环 / _execute_ai_decision）
   ├─ PlannerAgent（威胁建模先行；五段 schema 决策；PTES/OWASP/NIST/ATT&CK）
   ├─ ToolAgent（离线排序器预筛→低置信弃权→LLM 选择器；50 工具/10 类；隐身分层）
   ├─ AnalystAgent（证据先行解读；KB 接地引用；FP 概率标注）
   ├─ DebateTriage（仅 FP=MEDIUM 触发：红辩真/蓝辩假/法官裁决）
   ├─ VisualTriage（截图+视觉 LLM 富化） + ReporterAgent（报告）
   └─ PentestMemory（findings/technologies/thinking steps/token 台账）+ KnowledgeBase（SQLite+FTS5：CVE/CWE/ATT&CK）
AI 层：8 提供商（openai/claude/gemini/openrouter/requesty/ollama/litellm/openai_compatible）+ entry-points 插件契约
安全层：scope_validator + utils/sanitize（不可信内容包裹）+ safe_mode/stealth 约束
```

## 3. 目录结构逐层解读

```
ai/ prompt_templates/（planner 216/tool_selector 172/analyst 288/reporter 288/debate 132/visual_triage）
   providers/（base 320 + 7 家 + 插件契约）
core/ agent.py(326 ★) planner(246) tool_agent(505 ★含排序器接线) analyst(300) reporter(404)
      workflow.py(892 ★引擎) workflow_schema(296) memory(374) knowledge_base(431)
      learners/tool_ranker.py(203 ★) agents/(debate_triage 241 ★/visual_triage 248)
tools/（50 工具 10 类） utils/（sanitize ★/scope_validator 243） workflows/ cli/ tests/
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 提示词层（planner/tool_selector/debate/analyst 全文或主体亲读）

- **UNTRUSTED_CONTENT_RULE 共享注入**（utils/sanitize）：模块 docstring 直陈威胁模型——目标 HTTP 服务器可返回任意字节，可**伪造 Guardian 自己的决策 schema（`NEXT_ACTION:`）骗规划器正则解析器**、注入提示覆盖、ANSI 污染控制台；对策=控制字符剥离 + `<UNTRUSTED_TOOL_OUTPUT>` 定界包裹 + 系统提示声明 DATA-ONLY——**把"工具输出污染决策 schema"当作具体攻击面处理**（全景观少见的针对性注入防御）。
- **Planner**：会话先建结构化威胁模型（资产/威胁行为者/攻击面/前五高价值路径/测试优先级/禁区六节，存 memory 供全部后续 agent 引用）；风险公式 `CVSS×0.4+业务影响×0.4+易发现性×0.2`；**强制 CoT 顺序 HYPOTHESIS→EVIDENCE→TEST→RISK_SCORE→DECISION**；五段输出 schema（REASONING/NEXT_ACTION/PARAMETERS/EXPECTED_OUTCOME/MITRE_TECHNIQUE）；决策提示注入"前 3 步推理链"防短视；人设收尾"持证渗透 tester，同时对客户 CISO 负责"。
- **Tool Selector**：19 工具×关键旗标表内嵌提示词；**隐身四档**（PASSIVE/STEALTHY/NORMAL/AGGRESSIVE）+ 安全模式规则（sqlmap --dbs/--dump 须显式确认；safe_mode 跳过 level>1）；只推荐 installed_tools 列表内工具；输出含 ALTERNATIVE_TOOL。
- **Analyst**：证据先行（"每个 finding 必须引用工具输出原文"）+ CVSS 分段 + **FP 启发式四问**（第二来源确认横幅？模板通用还是目标特异？证据描述漏洞还是只描述攻击面？人工测试者会得出同结论吗）+ 技术栈上下文过滤（"不要对 Node.js 报 PHP 漏洞"）+ **KB 接地引用节（"use exact IDs only"）**——RAG 引用只准用检索到的精确 ID，堵幻觉 CVE 引用；输出 schema 含 `False_Positive: LOW|MEDIUM|HIGH` 概率行（辩论触发器）。
- **Debate**（红/蓝/法官）：律师各 ≤250 词、只对法官发言不互怼、**双方都被要求诚实**（"证据真不支持就明说，别编造"——防止对抗性辩护退化为说服竞赛）；法官"只用律师见过的证据、不引入新证据"、**降级保守**（"只有 BLUE 给出具体 FP 指标才降 severity，不能只凭 plausibility"）。

### 4.2 BaseAgent 与 think_deeply（core/agent.py 326 行全文亲读）

- think() 单轮；**think_deeply() 自批改多轮**：第 2+ 轮把上一轮答案附回 + "批判与改进任务"（逻辑缺口/需强化事实/可更精确结论三问；"上轮已最优就明说并重复"）。
- **廉价法官选轮**：judge_model 配置后，便宜模型读全 transcript 从 N 轮候选中选最佳轮——**换模-调用-恢复三段式**（同客户端临时改 model_name + _initialize 失效缓存，finally 恢复）；judge 以 round_number=99 入审计痕；失败静默回退末轮（"Never raises"）；README 声称 gpt-4o 轮 + gpt-4o-mini 法官 ≈ **10x 成本降**。落选轮保留在 thinking_chain 供审计。
- **每次 AI 调用四路记录**：TokenUsage（逐调用 token/成本台账）+ ThinkingStep（prompt 摘要/推理/结论/轮次）+ AIDecision + 结构化审计日志——决策可回放性的数据基础。

### 4.3 辩论分诊实现（core/agents/debate_triage.py 241 行全文亲读）

- **廉价路径门控**：FP=LOW→直接 REAL、HIGH→直接 FALSE_POSITIVE 跳过辩论（成本有界）；MEDIUM 或不可解析（默认 MEDIUM）才触发。
- **二阶注入防御**：证据/技术栈包裹 untrusted 之外，**红蓝律师的输出在喂给法官前再包一层**（"它们来自更早的 LLM 调用，其结构不受信"）——把 LLM 输出也当不可信内容的纵深做法。
- 解析容错一致保守：法官 JSON 不可解析 → 默认 **VERIFY_MANUALLY**（"宁可升级人工也不要运出一个猜的结论"）——与 T3MP3ST 引文核验降级同哲学（不确定即不自动定论）。
- 律师 JSON 提取失败→回退原文截断，辩论继续。

### 4.4 学习型工具排序器（core/learners/tool_ranker.py 203 行全文亲读）

- **手写朴素贝叶斯式计数表**而非 sklearn——设计理由明文："在 N=20 样本（单操作者首月现实量）上确定性工作，sklearn 会开心地过拟合"。
- **产出加权训练**：仅计入成功或有产出的行；权重=发现数（"找到 5 个发现的工具得权重 5"）；失败行以"不计数"编码负信号。
- 评分 `3.0×(phase,target)联合 + 1.5×单特征×2 + 0.1×先验`，softmax 归一；**min_confidence=0.7 弃权线**——低于则 predict_with_fallback 返回 None，ToolAgent 回退 LLM 选择器（"离线排序器快速预筛，弃权时交还 LLM"）；telemetry JSONL 训练、pickle 持久化、惰性加载不自动更新。
- 这是全景观第一个**从自身遥测闭环学习的选工具组件**（对照：其他项目的工具选择全靠提示词或规则）。

### 4.5 工作流引擎与执行层（结构+关键方法亲读）

- WorkflowEngine：YAML 工作流（步骤级并发 _run_one）+ run_autonomous 自主主循环 + _execute_ai_decision（规划器决策的分派执行）+ 编译步骤路径。
- ToolAgent：available_tools（内置+插件发现 entry-points）→ 排序器 → LLM 选择 → configure_tool 参数工程 → execute_tool；_detect_target_type 四分（ip/domain/url/unknown）。
- providers：8 家 + `[project.entry-points."guardian.providers"]` 插件契约（第三方提供商免 fork）——与工具插件同构的生态位设计。

## 5. 值得借鉴的设计与技巧

1. **决策 schema 伪造作为显式攻击面**：sanitize 模块针对"工具输出伪造 NEXT_ACTION 骗规划器"建模 + 定界包裹 + DATA-ONLY 声明——LLM CLI 工具输出注入防御的具体化范本（多数项目只防"忽略指令"类注入，这里连**自己输出格式的伪造**都防）。
2. **辩论分诊的三重成本设计**：FP 概率门控（只有 MEDIUM 辩论）+ 双律师诚实条款 + 法官不引入新证据且降级保守；F1≥单 agent+5pp 的验收指标写进 docstring。
3. **廉价法官选轮**（think_deeply+judge_model）：大模型思考多轮、小模型选轮、swap-and-restore 兼容实现、落选轮留审计——推理成本工程的参考。
4. **小数据学习器**：手写计数表 + 产出加权 + 0.7 弃权线回退 LLM——"什么时候不该用 ML"的教科书答案。
5. **KB 接地引用防幻觉**（"use exact IDs only"）+ RAG over CVE/CWE/ATT&CK。
6. 分析员 FP 四问启发式 + 技术栈上下文过滤——去误报的提示词层落法。
7. 每调用四路记录（token 台账/思考步/决策/审计）——回放友好的可观测性。

## 6. 局限与改进点

- 规划器输出靠正则解析五段 schema（依赖模型服从格式；对抗输入已防但格式漂移仍会解析失败）；辩论结论无源码级核验（对照 T3MP3ST 的引文核验——这里是"律师引用+法官保守"，无确定性校验）。
- 排序器特征只有 4 维（target_type/phase/两个计数），无目标技术栈特征；pickle 持久化有反序列化信任前提。
- workflow.py 892 行单文件；README 的 F1/10x 声明未见提交的评测工件（对照 T3MP3ST verify-claims 可重推导——此处只在 docstring 声明验收口径）。
- 无容器隔离；safe_mode/stealth 约束在提示词与配置层。
- visual_triage/reporter/memory/knowledge_base/50 工具未逐行（结构确认）。

## 7. 与其他已审计项目的对比

| 维度 | guardian-cli（本项目） | T3MP3ST | garak | hackingBuddyGPT |
|---|---|---|---|---|
| 形态 | CLI 框架 | keyless 框架 | 扫描器 | 实验框架 |
| 去误报 | **红蓝法官辩论+FP 门控** | 引文核验面板 | Se/Sp 校准 CI | 基准 ground truth |
| 注入防御 | **schema 伪造显式建模+二阶包裹** | 教义层（当证据） | — | — |
| 成本工程 | **廉价法官选轮+辩论门控** | — | — | 层级 Limits |
| 学习 | **遥测训练排序器** | self-improvement 记录 | 校准资产 | — |
| LLM 红队 | **garak/pyrit 当工具用** | 盲匠分解 | 本体 | — |

它是"防御性设计密度"最高的渗透框架之一：注入防御/辩论去误报/弃权式学习/成本路由四个方向都有可抄的具体实现；验证层缺确定性核验（对照 T3MP3ST）与声明不可重推导（对照 verify-claims）是主要差距。景观内它还标志一个转折点——**已审计项目开始互为工具**（garak/pyrit 是其 B12 类工具）。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `ai/prompt_templates/` planner/tool_selector/debate | ✅ 亲读全文 | 216+172+132 |
| `ai/prompt_templates/analyst.py` | ✅ 亲读主体 | 系统+解读提示 120/288 |
| `core/agent.py` | ✅ 亲读全文 | 326/326（think/think_deeply/法官） |
| `core/agents/debate_triage.py` | ✅ 亲读全文 | 241/241 |
| `core/learners/tool_ranker.py` | ✅ 亲读全文 | 203/203 |
| `utils/sanitize.py` | ✅ 亲读主体 | 头 60 行（规则+正则） |
| `core/tool_agent.py` `workflow.py` | ✅ 结构+关键方法 | 函数清单/排序器接线/引擎路径 |
| `ai/prompt_templates/` reporter/visual_triage | ✅ 结构登记 | 未逐行 |
| `core/` 其余（planner/analyst/reporter/memory/knowledge_base/visual_triage/workflow_schema） | ✅ 部分/结构 | 按调用面确认 |
| `tools/`（50 工具） `workflows/` `cli/` `providers/` `tests/` | ⬜ | 未读/清单登记 |

## 9. 结论

**Guardian 的核心实现思路是：把"可信输出"当作渗透自动化的一等工程目标——规划器以威胁建模先行、五段 schema 与固定 CoT 顺序约束决策，工具选择走"遥测训练的手写贝叶斯排序器（0.7 弃权）→ LLM 选择器"两级，分析员强制证据引用+KB 精确 ID 接地+FP 概率标注，歧义发现交红/蓝/法官三角色辩论（廉价路径门控+二阶 untrusted 包裹+不可解析即人工），think_deeply 用廉价法官从自批改多轮中选轮（~10x 成本降），且每次 AI 调用四路入账可回放。** 它是已审 22 项中防御性设计密度最高的框架：注入防御具体到"伪造自家决策 schema"、去误报有辩论结构与保守默认、学习组件知道何时弃权；对照 T3MP3ST 的差距同样清晰——验证停在"律师引用+法官保守"，无源码级确定性核验，head-line 声明亦不可重推导。其"garak/pyrit 作为工具"的引用关系标志着本景观开始出现内生的工具层级。

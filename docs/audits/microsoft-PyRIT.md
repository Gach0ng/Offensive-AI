# microsoft/PyRIT 逐行代码审计

> 审计对象：PyRIT（Python Risk Identification Toolkit）—— 微软的 AI 红队自动化框架：攻击编排器（多轮对抗/树搜索/渐进式）× 目标抽象 × 评分器库 × DB 记忆后端 × FastAPI+React 前端。
>
> 审计方法注记：仓库 1,362 个 .py 文件约 35.7 万行（含 backend/frontend/tests）。核心攻击链（对抗会话管理器/RedTeaming 循环/TAP 结构/评分器模式/记忆接口/目标能力协商/裁判提示词）亲读；backend/frontend/UI 层按职责登记，需专项时回读。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/microsoft/PyRIT |
| 本地路径 | `repos/agents/PyRIT/` |
| 审计基线 commit | `76b321f791180f4914666953cb9a81db42136ae2`（2026-08-22，reject non-finite score_value） |
| 语言 / 规模 | Python，约 357,500 行（pyrit 核心 + FastAPI backend + React frontend + 全量测试） |
| Landscape 定位 | 类型：渗透 Agent（实为 LLM 红队框架）/ 微软官方、与 garak 并列的领域双标准 / 一句话：编排式 AI 红队 SDK——把攻击做成可组合策略，全程落库 |
| License | MIT |
| 关联论文 | 无单篇（TAP/Crescendo/PAIR 等攻击各自有论文，实现内嵌） |
| 审计日期 / 人 | 2026-08-24 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：对 LLM/多模态/AI 应用做**自动化红队评估**——不是扫描器式探针矩阵（garak 路线），而是**编排器路线**：攻击者 LLM 与目标多轮博弈，直到 objective scorer 判定达成目标或耗尽轮次。
- **输入输出**：Python SDK 组装（attack config + objective + targets + scorers）或 CLI/前端；输出 AttackResult + 全量对话/评分入库（SQLite/Azure SQL）+ 树可视化（TAP）。
- **差异化定位**：**库/框架形态**（供安全团队编程式构建攻击），与 garak 的"工具形态"互补；一切对话、转换、评分、请求全部持久化到中央记忆——**红队过程的第一等公民是数据**。

## 2. 架构总览

```
SDK 使用者 / CLI / React 前端 (frontend/) → FastAPI backend (pyrit/backend: routes/services/models/alembic)
   ▼
executor/attack/（编排核心）
   ├─ core: AttackExecutor/AttackConfig/AttackStrategy 基类 + 结果归因
   ├─ component: _AdversarialConversationManager（★ 共享对抗会话引擎，871 行亲读）
   │             ConversationManager / ModalityFeedbackRouter（多模态织入）
   ├─ multi_turn: RedTeaming（经典对抗循环 534）/ Crescendo（渐进 860）/ TAP（树搜索 2513）
   │             / PAIR / SimulatedConversation / ChunkedRequest / MultiPromptSending
   └─ compound: SequentialAttack（攻击编排攻击）
   ▼
prompt_target/（目标抽象：CapabilityName 能力协商 + TargetRequirements）
prompt_normalizer/（PromptNormalizer + send_json_with_retry）
score/（Scorer 家族：SelfAsk Likert/TrueFalse/Category、ShieldGemma、Azure 内容过滤、
        scorer_evaluation 评估器元评估）
converter/（提示变换：token smuggling、ANSI escape…）
memory/（CentralMemory：SQLite/Azure SQL + alembic 迁移 + 嵌入检索）
datasets/（种子提示/越狱模板/harm 定义/lexicons/10 族 executor YAML 管线）
```

- **编排方式**：策略类模式——`MultiTurnAttackStrategy` 基类（setup/perform 生命周期 + 上下文对象），八种多轮攻击是同一骨架的不同策略；复合层可串接。
- **LLM 层**：prompt_target 抽象两端（攻击方 adversarial chat 与目标 objective target）；**能力协商**（见 4.3）。

## 3. 目录结构逐层解读

见上文架构图各目录注释；另有 `analytics`（结果分析）、`auth`（目标认证）、`embedding`（记忆检索嵌入）、`registry`、`scenario`、`message_normalizer`、`cli`。

## 4. 核心模块逐行精读（审计主体）

### 4.1 对抗会话引擎（component/adversarial_conversation_manager.py，871 行**全文亲读**——2026-08-24 深度补读）

- **本框架最重要的抽象**：所有多轮攻击（RedTeaming/Crescendo/TAP/PAIR/SimulatedConversation）共享同一个对抗会话循环——攻击方 LLM 每轮产出"下一条攻击消息"。
- **规范化 adversarial_chat JSON schema 与单源验证**：回复解析器（_parse_adversarial_reply，213-276）从 schema 本身读 required/properties/additionalProperties（**schema 是唯一事实源，不硬编码副本**——不会与 YAML 漂移）；解析前剥 markdown 代码栅栏 + **camelCase→snake_case 键名归一**（后端漂移到 `nextMessage` 也能过，不烧重试）；`next_message` 是攻击循环消费的唯一字段、恒必填。
- **JSON 重试带历史回滚**（:805-871）：`send_json_with_retry_async` 的重试在**干净会话历史**上进行——失败的轮次先从记忆里回滚再重发，而不是把模型自己的畸形回复留在历史里重放。
- **反馈构建器四分支**（_build_adversarial_feedback_text，157-191）：目标响应 blocked→短失败通知；error→带错误码；正常→文本+（可选）scorer rationale（use_score_as_feedback）；空→"please continue" 轻推。**媒体丢失警告**（612-643）：目标回了纯媒体而攻击方无法消费时降级为轻推——这是配置错误的信号（文本攻击方配了图像目标），显式 warn 而非静默。
- **种子三分路**（get_next_message_async，645-724）：具体种子无占位符→**绕过攻击方**直接发（duplicate 给新 id，防种子被改写/双持久化）；带对抗占位符→攻击方文本填进占位槽（种子媒体与文本同行）；无种子→模态路由器构建目标消息。
- **双入口设计**：`get_next_message_async`（完整契约，返回即发消息）vs `generate_adversarial_reply_async`（只到解析回复为止）——后者专为 TAP 存在：它要先对 next_message 跑 on-topic 评分、可能带反馈重问，再决定发什么。
- 每次发送都包在 execution_context（component_role=ADVERSARIAL_CHAT 等）里——遥测按角色关联。

### 4.2 执行器与结果容器（core/attack_executor.py 481 行**全文亲读**——补读新增）

- **AttackExecutorResult 部分完成语义**：completed_results + incomplete_objectives(目标,异常) + **input_indices**（结果↔原始输入位置映射，部分失败时仍可对账）；`raise_if_incomplete()` 严格模式 vs 部分模式。
- **懒信号量+事件循环重建**（:139-167）：asyncio Semaphore 首次 await 绑定事件循环、跨 asyncio.run 复用会炸——executor 在 `_get_semaphore` 里检测循环变化重建，**一个实例可安全跨 notebook 多次运行**（注释 10 行详述缘由，:139-146）。
- **双阶段失败合并**：参数构建失败（from_seed_group_async）与执行失败分开收集，按**原始输入位置**合并回一个结果（_merge_parameter_build_failures）；致命异常（BaseException 非 Exception，如取消）**无条件立即上抛**（:445-450）。
- attribution（编排器血缘）盖到每个 context 上随结果持久化。

### 4.3 经典循环与 Crescendo 回溯协议（red_teaming.py 534 行**全文亲读** + crescendo.py 主循环与回溯**全文亲读** + 基类 157 行**全文亲读**——补读升级）

- **RedTeaming 循环**（:297-368）：`while turns < max and (score_last_turn_only or not achieved)`——**score_last_turn_only 模式跳过中间轮评分**（成本优化：中间轮不花裁判钱）；对抗会话管理器**一次构建全程复用**（注释明言其无每轮可变态）；种子 next_message **消费即清**（单轮种子语义）。
- **单轮目标会话轮换**（基类 :98-157）：目标不支持多轮时每轮换新 conversation_id；旧会话记为 **PRUNED 类型的相关会话引用**（溯源保留）；**系统消息复制进新会话**——目标不丢系统提示词。这条"无状态目标也能跑多轮攻击"的适配完全在编排层完成。
- **Crescendo 回溯协议**（crescendo.py 779-834——**原审计完全遗漏的独家机制**）：
  1. 拒答由独立的 SelfAskRefusalScorer 判定（非目标评分器）；
  2. 确认拒答→`duplicate_conversation_excluding_last_turn`——**记忆级事务回滚**，被拒轮次从目标的视角"从未发生"；
  3. **回滚轮不计入 max_turns**（回溯免费，只受 max_backtracks 预算约束）；超预算后拒答不再回滚、轮次照计；
  4. 被拒提示词文本回喂攻击方（"换个思路，这是被拒的内容"）；score-as-feedback 可选（归一化 0-1 分+rationale）；
  5. **重试种子变换**（_build_retry_seed_message）：被拒的具体种子→保留全部媒体片段+文本换成对抗占位符（攻击方重新生成文本、媒体不丢）；
  6. backtrack_count 进结果元数据。
  这是全部已审项目里唯一的**会话级事务回滚**——shannon 的回滚在文件级、theori 的压缩是截断，PyRIT 把"失败的轮次"做成可撤销事务。
- **Crescendo 多模态输入态声明**（_build_adversarial_prompt，504-577）：每轮告诉攻击方本次输入模式（seed_media/latest_response/text_only）与种子媒体是否仍attached——攻击方对"目标将收到什么形态的输入"有显式知情。

### 4.4 TAP 树搜索（tree_of_attacks.py 2,513 行，主循环+节点核心**补读亲读**）

- **配置四元**：tree_width（默认 3）/tree_depth/branching_factor/batch_size + on_topic_checking_enabled。
- **主循环**（_perform_async，1725-1790）：逐深度迭代→首轮初始化 width 个节点/后续轮按 branching_factor 分叉→**并行批量执行**所有活跃节点→按分剪枝回 width→更新最优会话→目标达成即早停/全剪光即断。
- **离题反馈重试环**（_generate_red_teaming_prompt_async，975-1050）：生成后先过 on-topic 评分器；离题→把"你的上一条提示被判离题+理由+目标重申"回喂攻击方重生成（RETRY_MAX 次上限）；仍离题→**该分支剪枝**（off_topic=True）。这正是共享引擎第二个入口存在的原因。
- **前置对话计入深度**且**每个节点各得一份拷贝**（节点独立会话 ID 并行探索）；JSON 解析错误→分支剪枝（_handle_json_error）。
- 节点 duplicate 克隆时连可视化树位置一起拷贝。

### 4.3 目标抽象与能力协商（prompt_target + TargetRequirements，red_teaming.py:53-57 亲读）

`_ADVERSARIAL_REQUIREMENTS = TargetRequirements(native_required={MULTI_TURN, SYSTEM_PROMPT})`——攻击声明"我需要目标原生支持多轮+系统提示"，注释直言理由："适配会静默改变语义（如 history-squash 归一化会把对话塌成单轮）"。**能力不满足就显式失败，不做静默适配**——多态目标（OpenAI/Azure/HF/多模态/代理）下的语义保真设计，六项目里独此一家。

### 4.4 评分器库（score/）

- `Scorer`（805 行基类）/`MessageScorer`：score() 返回 Score 模型（score_value/description/rationale）。
- **SelfAsk 家族**（LLM 裁判）：TrueFalse/Category/Likert——提示是 datasets 里的**参数化 YAML 种子提示**（亲读 red_teamer_system_prompt.yaml：task-achievement 判定框架，min/max 刻度参数化、`response_json_schema_name: scale_with_rationale` 强制 JSON 回复带 rationale、"只评是否完成任务、不评内容妥当性"的角色框定）；最新 commit 恰是"拒绝非有限 score_value 字符串"——对裁判输出数值的防御性解析在持续加固。
- **scorer_evaluation**（715+ 行）：用人工标注数据集评估评分器本身的质量——**裁判也要被审**，与 garak 的 Se/Sp 校准同一思想、更重（独立评估框架）。
- 非裁判类：ShieldGemma、Azure Content Filter、嵌入相似度。

### 4.5 记忆与数据底座（memory/）

- CentralMemory：全对话/评分/请求持久化（SQLite 或 Azure SQL，alembic 迁移），memory_embedding 支持检索；**攻击过程=数据库一等公民**——可复盘、可统计、可前端浏览（backend+frontend 把记忆库产品化）。
- 与 pentagi 的 msgchains 同思想（AI 行为审计底座），但 PyRIT 把它做成独立可部署服务。

### 4.6 结果验证与去误报

- objective scorer 门控循环终止（达成即停）；TAP 用剪枝+最优节点选择；auxiliary scores（refusal/on-topic）辅助过滤；scorer_evaluation 用元评估控裁判质量。
- 基线 commit 的"非有限分数拒绝"就是验证层的典型加固。

### 4.7 报告/HITL

React 前端（conversation 浏览/score 审阅）+ analytics；无运行中审批（SDK 库形态，HITL 由使用者代码组合）。

### 4.8 安全与隔离

攻击对象是模型/服务端点；auth 模块管目标认证凭据；无本机执行面（converter 是文本变换非命令执行）。docker/ 目录提供隔离部署。

## 5. 值得借鉴的设计与技巧

1. **共享对抗会话引擎 + 规范化 schema**：八种多轮攻击复用一个循环组件，回复按 schema 单源验证（required/allowed 键读自 schema 本身）、camelCase 归一容错、代码栅栏剥离——**结构化输出解析的防御性三件套**；提示跨攻击互换，新增攻击只做策略层。
2. **Crescendo 回溯协议**（独家）：记忆级事务回滚（被拒轮从目标视角抹除）+ 回滚不计轮次（只受 backtrack 预算）+ 被拒文本回喂 + 种子媒体保留变换——**把"失败的尝试"做成可撤销事务**，任何多轮攻击系统都可抄。
3. **JSON 重试带历史回滚**：重试前把失败轮从会话记忆回滚——不重放模型自己的畸形输出。
4. **单轮目标会话轮换**：无状态目标每轮换会话+系统消息复制+旧会话 PRUNED 溯源——适配完全在编排层，语义不损。
5. **评分器也是被评对象**（scorer_evaluation + 人工标注集）：LLM 裁判的质量度量闭环。
6. **裁判提示词的参数化 YAML 化**（min/max 刻度、JSON schema 绑定、角色框定语句）——评分提示词=数据资产，可版本可复用。
7. **能力协商拒绝静默适配**（TargetRequirements.native_required）：异构目标下"适配即语义破坏"的显式失败哲学。
8. **双阶段失败按输入位合并 + input_indices 对账**：部分失败时结果仍能映射回原始输入——批量系统的失败语义范本。
9. **懒信号量跨事件循环重建**：asyncio 原语绑定循环的坑用检测重建解决，实例可跨 asyncio.run 复用（注释详述缘由）。
10. **score_last_turn_only 成本模式**：中间轮不评分省裁判钱——成本语义进循环条件。
11. **离题反馈重试环**（TAP）：生成的攻击先过 on-topic 门，离题带理由回喂重生成、超限剪枝——攻击质量的前置闸。
12. **攻击过程全量入库为第一等公民**（CentralMemory + 前端）：红队的可复盘性产品化。
13. **ChunkedRequest/MultiPromptSending/ModalityFeedbackRouter + 媒体丢失警告**：实战组件化与配置错误显式化。
14. **SequentialAttack 复合编排**：攻击输出作为下游攻击输入——攻击流水线可编程。

## 6. 局限与改进点

- 体量与复杂度（35 万行含前后端）：上手成本高，SDK 面广；核心循环被组件层包裹较深。
- 验证依赖裁判质量（有元评估框架但默认不强制跑）。
- 与 garak 相比缺"开箱扫描"体验（是库不是工具）；无 CI/回归式跑批入口的一等地位（executors YAML 在补这个位）。
- backend/frontend 审计粒度受限（本审计未逐行，见第 8 节）。

## 7. 与其他已审计项目的对比

| 维度 | PyRIT（本项目） | garak | strix | pentagi |
|---|---|---|---|---|
| 形态 | **红队 SDK/库**（编排式） | 扫描器（探针矩阵式） | 蜂群 CLI | 平台 |
| 攻击模式 | 多轮博弈+树搜索+复合编排 | 静态探针+自适应扩展 | 动态 agent 树 | 计划修订+专家 |
| 裁判/验证 | SelfAsk 家族+裁判元评估 | Se/Sp 校准 CI | 报告校验+去重 | mentor |
| 数据底座 | **中央 DB+前端**（最强） | JSONL 报告 | SQLite 会话 | PG 全量落库 |
| 目标抽象 | 能力协商（拒绝静默适配） | 26 后端直连 | 单后端 | 多 provider |

garak 与 PyRIT 构成 LLM 红队的"工具派 vs 库派"双标准：前者赢在开箱与统计，后者赢在可编程性与数据底座。

## 8. 文件级审计进度（2026-08-24 深度补读后）

| 路径 | 状态 | 备注 |
|---|---|---|
| `executor/attack/component/adversarial_conversation_manager.py` | ✅ 亲读全文 | 871/871 行 |
| `executor/attack/core/attack_executor.py` | ✅ 亲读全文 | 481/481 行 |
| `executor/attack/multi_turn/red_teaming.py` | ✅ 亲读全文 | 534/534 行（主循环+发送+评分） |
| `executor/attack/multi_turn/multi_turn_attack_strategy.py` | ✅ 亲读全文 | 157/157 行 |
| `executor/attack/multi_turn/crescendo.py` | ✅ 亲读核心 | 主循环+回溯协议+提示构建+种子变换（约 400/860 行）；setup/发送细节待续 |
| `executor/attack/multi_turn/tree_of_attacks.py` | ✅ 亲读核心 | 主循环+节点核心+离题重试+剪枝（约 500/2513 行）；节点发送/评分细节待续 |
| `score/message_scorer.py` `scorer.py` | ✅ 部分 | score_async 主流程+ScoringExpectation+持久化语义；各 SelfAsk 家族与 scorer_evaluation 待续 |
| `datasets/score/scales/red_teamer_system_prompt.yaml` | ✅ 亲读全文 | 裁判提示词范式 |
| `executor/attack/core/`（strategy/parameters/attribution） | ⬜ 部分 | 经 executor/strategy 调用面确认 |
| `prompt_target/`（CapabilityName/TargetRequirements） | ✅ 部分 | 协商机制经 red_teaming/crescendo 亲读 |
| `pair.py` `simulated_conversation.py` `chunked_request.py` `multi_prompt_sending.py` | ⬜ | 同构骨架（共享引擎消费方），清单登记 |
| `memory/` `pyrit/backend/` `frontend/` `cli/` | ⬜ | 服务/存储层登记 |

> 补读方法注记：本文件按"核心链文件逐行读完"标准于 2026-08-24 重审，新增 Crescendo 回溯协议、JSON 重试历史回滚、单轮目标会话轮换、双阶段失败合并、离题反馈重试环、score_last_turn_only 成本模式等此前遗漏的关键设计；crescendo 剩余细节、pair/其余策略、scorer 家族为后续回读项。

## 9. 结论

**PyRIT 的核心实现思路是：把 AI 红队做成可编程的编排器库——八种多轮攻击策略共享一个带规范化 JSON schema（单源验证+camelCase 容错+失败轮历史回滚重试）的对抗会话引擎，目标端用能力协商显式拒绝会改变语义的静默适配、单轮目标靠编排层会话轮换接入，objective scorer（参数化 YAML 裁判提示词 + 裁判元评估 + ScoringExpectation 携带目标）门控终止；Crescendo 的回溯协议把被拒轮次做成记忆级可撤销事务（回滚不计轮次、种子媒体保留、被拒文本回喂），TAP 用宽度/分支/剪枝加离题反馈重试环做树搜索，执行层以双阶段失败合并与输入位对账管理批量部分失败，全部对话/评分/请求作为第一等公民落入中央数据库并可前端复盘。** 它与 garak 分别代表 LLM 红队的"库派"与"工具派"双标准；其共享对抗引擎、回溯协议、能力协商、裁判也是资产这四个设计对任何红队框架都是直接可移植的。

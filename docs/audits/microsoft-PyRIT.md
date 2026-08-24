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

### 4.1 对抗会话引擎（component/adversarial_conversation_manager.py，871 行亲读头 120+结构）

- **本框架最重要的抽象**：所有多轮攻击（RedTeaming/Crescendo/TAP/PAIR/SimulatedConversation）共享同一个对抗会话循环——攻击方 LLM 每轮产出"下一条攻击消息"。
- **规范化 adversarial_chat JSON schema**：攻击方回复强制走共享 schema（`next_message` + `rationale` + `last_response_summary`），除非提示自带 schema——**回复结构化校验而非裸文本信任**（文件头注释原文："always structurally validated instead of silently trusted"）；各攻击的对抗提示因此**可互换**。
- `_ResolvedAdversarialConfig`：对抗提示解析单一所有者；Crescendo/TAP/Simulated 走 override 模式（自供提示文本，仅解析系统提示）。
- `AdversarialTurn`：目标消息 + 解析回复 + bypassed 标志（调用方可直接种消息绕过攻击方）；`_ModalityFeedbackRouter` 把先前/种子媒体织进消息——多模态攻击的统一通道。
- 空文本目标回复有专门 feedback 字符串处理（文件尾段）。

### 4.2 经典循环与树搜索

- **RedTeamingAttack**（red_teaming.py 亲读）：`while executed_turns < max_turns and not achieved`（默认 10 轮）；每轮=攻击方生成→发目标→**objective scorer 判定**（可 score_last_turn_only）；能力要求声明式校验（见 4.3）。
- **TAP**（tree_of_attacks.py 2513 行，结构亲读）：树节点 `_TreeOfAttacksNode` 各自持有会话与状态，带 nodes_explored/nodes_pruned/max_depth_reached 统计与 `tree_visualization`（rich Tree 可视化）；`TAPAttackScoringConfig` 强制校验 objective scorer 与 refusal scorer 的**类型正确**；threshold 参数化剪枝。
- **Crescendo/PAIR/SimulatedConversation**：同骨架的渐进式/迭代提问/双角色模拟变体；**ChunkedRequest**（把长请求分块发送绕长度限制）；**MultiPromptSending**（多提示并行）；**SequentialAttack** 复合编排（前攻输出作后攻输入）。

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

1. **共享对抗会话引擎 + 规范化 schema**：八种多轮攻击复用一个循环组件，攻击方回复结构化校验、提示跨攻击互换——新增攻击策略只需差异化策略层。
2. **能力协商拒绝静默适配**（TargetRequirements.native_required）：异构目标下"适配即语义破坏"的显式失败哲学。
3. **评分器也是被评对象**（scorer_evaluation + 人工标注集）：LLM 裁判的质量度量闭环。
4. **裁判提示词的参数化 YAML 化**（min/max 刻度、JSON schema 绑定、角色框定语句）——评分提示词=数据资产，可版本可复用。
5. **攻击过程全量入库为第一等公民**（CentralMemory + 前端）：红队的可复盘性产品化。
6. **ChunkedRequest/MultiPromptSending/ModalityFeedbackRouter**：绕长限/并行/多模态织入等实战组件化。
7. **SequentialAttack 复合编排**：攻击输出作为下游攻击输入——攻击流水线可编程。
8. TAP 的树统计（explored/pruned/depth）与 rich 可视化内建。

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

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `executor/attack/component/adversarial_conversation_manager.py` | ✅ 亲读 | 头 120+结构精读 |
| `executor/attack/multi_turn/red_teaming.py` | ✅ 亲读 | 头 60+结构+循环段 |
| `executor/attack/multi_turn/tree_of_attacks.py` | ✅ 部分 | 结构与配置类精读（2513 行） |
| `datasets/score/scales/red_teamer_system_prompt.yaml` | ✅ 亲读 | 裁判提示词范式 |
| `executor/attack/core/`（executor/config/strategy/attribution） | ⬜ 部分 | 经调用面确认 |
| `prompt_target/`（CapabilityName/TargetRequirements） | ✅ 部分 | 协商机制经 red_teaming 亲读 |
| `score/`（scorer/message_scorer/SelfAsk 家族/scorer_evaluation） | ✅ 部分 | 基类结构+裁判家族模式 |
| `memory/`（central/sqlite/azure） | ⬜ 部分 | 机制登记 |
| `pyrit/backend/` `frontend/` `cli/` | ⬜ | 服务/UI 层未读 |
| `datasets/executors/`（10 族 YAML 管线） | ⬜ 部分 | 清单已读（crescendo×5 变体等） |

## 9. 结论

**PyRIT 的核心实现思路是：把 AI 红队做成可编程的编排器库——八种多轮攻击策略（经典对抗/渐进/PAIR/树搜索/模拟对话/分块/多提示/串接复合）共享一个带规范化 JSON schema 的对抗会话引擎，目标端用能力协商显式拒绝会改变语义的静默适配，objective scorer（参数化 YAML 裁判提示词 + 裁判元评估）门控终止，全部对话/评分/请求作为第一等公民落入中央数据库并可前端复盘。** 它与 garak 分别代表 LLM 红队的"库派"与"工具派"双标准；其共享对抗引擎、能力协商、裁判也是资产这三个设计对任何红队框架都是直接可移植的。

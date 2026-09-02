# 进攻性 AI Agent 技术栈选型调研报告：接入层、编排底座与可靠性工程

> **日期**：2026-09-02
> **语料**：本仓库 60 份逐行审计（`docs/audits/`，覆盖 Yeti landscape 主列表 56 个进攻性 Agent + 4 个相关项；TRACKER 进度 61/96，其中 1 项审计结论并入本表）
> **方法**：三路证据交叉——① 60 份审计文档的代码级事实抽取（每份均含核心链路亲读与提示词全文）；② 全仓 import 普查（`repos/agents` + `repos/aixcc` 共 62 个克隆，按文件数统计 openai/anthropic/langchain/langgraph/litellm/strands/MCP SDK 的 py+ts import，排除 node_modules/.venv/vendored fork）；③ 13 个关键项目的客户端构造代码抽验（strix/cai/cochise/mapta/vulnhuntr/pentest-ai/pentagi/artiphishell/Cyber-AutoAgent/ctf-agent/tinyctfer/Cairn/shannon）。
> **回答的问题**：现有成熟方案在 LLM 接入层、agent 编排底座、工具调用、可靠性工程上到底怎么选；一个已有自研引擎和多套 LLM 客户端的平台（如本报告委托方场景）是否应迁移到 OpenAI SDK 开发。

---

## 0. 一页结论

1. **"迁移到 OpenAI SDK"这个问题的正确问法是两问拆一问**：把 OpenAI SDK 当**协议**还是当**架构**。证据给的答案是：**当协议，收编所有客户端；不当架构，不绑定它的专属特性**。全语料 23+ 仓直接 import openai SDK，另有 17 仓 import litellm；生产级系统（atlantis/artiphishell/buttercup/strix/pentagi）的公约数是"**openai 客户端（或 langchain 消息层）→ LiteLLM 网关 → 多厂商**"，没有一家生产系统用 openai SDK 裸连厂商并把它当架构核心。
2. **编排底座：通用框架在这个领域接近集体缺席，自研决策循环是主流**。62 仓中运行时真正用 LangGraph 的 4 家、Strands 1 家、OpenAI Agents SDK 3 家、Eino 1 家、langchaingo 1 家——"没一家超过两个用户"基本成立（LangGraph 唯一破例）。但 LangGraph 的 4 家全是"确定性骨架 + 图状态机"形态（CRS 管线/桌面工作台），与渗透智能体需要的"双车道"形态吻合。
3. **宿主 CLI 派（Claude Code/Codex/Pi/OpenCode）战绩最强但不可产品化**：TCH 唯一 AK（Cairn）、BSidesSF 52/52（ctf-agent）、104/104（communitytools）、99 行第 4 名（tinyctfer）全在此派。代价是把会话、工具、计费、沙箱全部外包给宿主——多租户产品平台的预算治理/审计/安全边界做不到，Cairn 文档自认"换后端需重做会话层"。
4. **成熟度的分水岭不在 SDK 选型，在四件事**：解析失败回喂重试、上报走 schema 校验的工具（submit-tool 形态）、成本/预算硬闸、断点续跑。这四件与 13 条共性（`docs/blog/2026-08-27-blackbox-pentest-agent-methodology.md`）的验证文化/证据军规互相印证。
5. **弱模型适配是被低估的必修课**：hackingBuddyGPT 的三级调用规约降级、strix 的 strict schema 自动降级与 CustomTool 包装、T3MP3ST 的本地模型文本协议适配——要接国产模型（GLM/Kimi/DeepSeek，全部 OpenAI 兼容但 function calling 质量参差）的平台，这层不可省。

---

## 1. 定量普查：SDK 采用面（62 克隆，按 import 文件数）

### 1.1 接入层五派（互有重叠，按主形态归类）

| 路线 | 数量 | 代表项目（import 文件数） |
|---|---|---|
| **宿主 CLI / agent harness**（自身零 LLM 客户端） | 10 | Cairn（claudecode/codex/pi 适配器）、tinyctfer、communitytools、pentest-ai-agents（纯提示词资产）、Dark-Moon（OpenCode）、PentestGPT（claude-agent-sdk+codex 归一）、shannon（pi harness）、BreachWeave/LuaN1aoAgent（Pi）、BugTrace-AI（浏览器 fetch→OpenRouter） |
| **LiteLLM 统一**（import litellm 或网关部署） | 13 | cochise(3 文件·630 行拿域管)、AI-OPS(18)、hackingBuddyGPT、pentestagent(3)、buttercup、atlantis(29+完整 fork 网关)、artiphishell(5 网关)、strix(12)、cai(21)、pentest-ai(2)、guardian-cli(8 provider 之一)、PyRIT/agentic_security(1) |
| **openai SDK 直连为主** | 8 | mapta(AsyncOpenAI+Responses API)、vulnhuntr、HackSynth、agentic-radar、nyuctf(5)、PyRIT(27)、garak(6，26 种 generator 之一)、seclab(3) |
| **自写多后端客户端** | 9 | EVA(6 后端 1,055 行)、guardian-cli(8 provider+插件 entry-points)、promptmap(6 后端单文件)、theori(4 家·aixcc 冠军)、Cyber-Zero、Zen、redamon、BoxPwnr(llm_manager 2,428 行)、T3MP3ST(API+本地 CLI+本地模型三轨) |
| **框架自带接入** | 5 | pentagi(langchaingo+自研 10+ provider 注册)、CyberStrikeAI(Eino·openai_compatible+claude 双通道)、Cyber-AutoAgent(Strands·bedrock/ollama/litellm 三通道)、ctf-agent(pydantic-ai+Claude SDK+Codex)、pentest-copilot(TS providers.ts 1,589 行) |

anthropic SDK 单独统计：仅 12 仓少量使用（多为多客户端之一）；TS 侧 @anthropic-ai/sdk 只有 promptfoo(16 文件) 成规模。**Anthropic 协议的真实阵地在宿主 CLI 派**——Claude Code 讲 Anthropic 方言，tinyctfer 实测用 GLM-4.6/kimi k2 的 Anthropic 兼容端点驱动。两种方言（OpenAI 协议=API 派、Anthropic 协议=宿主派）并存，LiteLLM 两种都讲。

### 1.2 编排底座（运行时真用，非 vendored/非被分析对象）

| 底座 | 运行时用户数 | 谁 |
|---|---|---|
| 自研 agent loop / 决策循环 | ~20 | theori（512 行泛型微内核·冠军）、strix、pentestagent、redamon、deadend-cli（ADaPT）、guardian-cli、cochise、VulnBot、EVA、HackSynth、nyuctf(D-CIPHER)、ctf-agent(Coordinator)、BugTrace-AI(无 loop)、pentest-copilot(AgentService 1,345 行)、BoxPwnr(求解器矩阵) 等 |
| LangGraph | 4 | atlantis(81 文件·llm-poc-gen 状态图)、buttercup(19·11 节点状态机)、nebula(2·Supervisor/Specialist)、Zen(2)。（agentic-radar 的 13 处 langgraph import 是**扫描别人代码**的 AST 反演，不算运行时用户） |
| OpenAI Agents SDK | 3 | cai（vendored 深改 4,653 行 chatcompletions）、strix（agents SDK 风格工厂）、seclab |
| 宿主 harness | 10 | 同上宿主派 |
| 其它单例框架 | 5 | Strands(Cyber-AutoAgent)、Eino(CyberStrikeAI)、langchaingo(pentagi)、Temporal(shannon·确定性 DAG)、pydantic-ai(ctf-agent) |
| LangChain AgentExecutor | 2 | artiphishell(agentlib 封装)、redamon(5 文件混用) |
| 纯流水线无 loop | 12+ | vulnhuntr、promptmap、agentic_security、deepteam、Nettacker、AutoPentestX、AutoPentest-DRL、Cyber-Zero、garak、promptfoo、PyRIT、AI-VAPT 等考官/零AI/扫描器 |

MCP SDK（py/ts）作为工具面：13 仓（promptfoo 26 文件、BreachWeave 9、cai 7、CyberStrike 5、agentic-radar 4、Zen 8、pentestagent 既是 client 又是 server、hexstrike 纯工具服务器、Dark-Moon、CyberStrikeAI、T3MP3ST、communitytools、pentest-copilot）。

---

## 2. 接入层：成熟方案的四种形态与适用边界

### 形态 A：LiteLLM 统一 + OpenAI 方言（生产系统的公约数）

三个重量级样本把这个形态做到了三档：

- **cochise（最轻档）**：630 行拿 GOAD 三域域管，LLM 调用就是 `litellm.completion()` + `function_to_dict` 反射生成工具 schema。一个文件三处 import，模型随便换。**结论：LiteLLM 的性价比下限极高，630 行足够打穿一个复杂域。**
- **buttercup（中档·Trail of Bits）**：`common/llm.py` 统一封装 ButtercupLLM 枚举 20+ 模型 + `with_fallbacks` 多模型回退链（GPT-4.1 主 + Claude-4.5-Sonnet + Gemini）+ LangChain SQLiteCache 零成本复放 + Langfuse/OTel 全链路遥测。
- **atlantis（最重档·AIxCC 决赛）**：把 LiteLLM 整个 fork 成网关：`usage-based-routing-v2` 路由 + Redis 共享路由状态 + `/user/new` 虚拟 key（max_budget 硬顶）+ `/key/info` 回读实耗，配 Redis 分布式预算池形成"分配-回收-再分配"闭环——LLM 预算与 vCPU 同构治理，全语料唯一。配套 tenacity（429/5xx 重试 10 次）+ SQLite/Redis 两级缓存 + tokencost 逐调用计费 + OTel 全量 prompt/completion 落盘。

artiphishell 的用法补充一个生产细节：**多 LLM 轮换**——programmer 角色挂 `programmer_llms` 列表，budget/rate-limit 异常自动切下一个；外加"预算小睡"（nap_mode 睡到下个配额窗口）和 PatchCache sha256 缓存重放。

**适用边界**：需要多模型路由、预算治理、缓存复放、多租户——即任何要长期跑、要管钱的产品系统。

### 形态 B：openai SDK 直连（含 OpenAI 兼容 base_url）

- **mapta**：`AsyncOpenAI().responses.create(model="gpt-5", reasoning={"effort":"high"})`，直连单模型，UsageTracker 双轨记账。
- **vulnhuntr**：三个原生客户端（anthropic SDK / openai SDK+json_object / Ollama），4 文件 1,334 行出 22 个 0-day——证明小工具不在乎接入层优雅。
- **strix（混合形态的样板）**：模型层 StrixProvider 走 LiteLLM（`STRIX_LLM=openai/gpt-5.4` 任意 provider/model ID），同时给 Codex 订阅通道单独留 `build_openai_client()` 构造 AsyncOpenAI——**订阅制通道和 API 通道并存时，openai SDK 是给特殊通道留的那扇门，不是主干**。

**适用边界**：单模型工具、原型、或作为 LiteLLM 之下的特殊通道适配器。直连多厂商会把重试/计费/切换逻辑撒进每个调用点——62 仓里这么做的无一长成了生产系统。

### 形态 C：自写多后端客户端（历史最常见，正在被 LiteLLM 吞掉）

EVA 六后端、guardian-cli 八 provider（含插件 entry-points 契约）、theori 四家适配、BoxPwnr llm_manager 2,428 行、promptmap 六后端。共性成本：每加一家厂商写一遍重试/流式/计费。**theori 值得单读**：它的自研不在接入层而在编排——512 行 `AgentGeneric[T]` 手写微内核（msgs+工具注册表+max_iters 循环），多模型三用法（失败回退 model_idx+=1 / 并行竞速先到先得 / 按角色分档 13 份 models-*.toml）全部长在自家循环上。guardian-cli 的独有贡献是**廉价法官选轮**（同客户端临时换 model_name 调 gpt-4o-mini 当裁判，成本降 ~10x，finally 恢复）——成本工程可以做到 provider 层。

**适用边界**：需要 hackingBuddyGPT 式深度弱模型适配（三级降级：原生 tools→Action union→纯文本空格切分）或 theori 式模型竞速时，自研一层值得；否则是重复造 LiteLLM。

### 形态 D：宿主 CLI / agent harness（战绩极值，产品化禁区）

把会话连续性、子代理 spawn、工具执行、（常常连计费）全部委托给宿主：Cairn 的 worker 就是 `claude --session-id <uuid> --dangerously-skip-permissions -p`，健康检查直接 HTTP 打 Anthropic /v1/messages；PentestGPT v1.0 把 claude-agent-sdk 与 openai-codex SDK 归一成同一事件流，自定义工具经 stdio MCP 注入两侧统一 `mcp__<server>__<tool>`；shannon 包 @earendil-works/pi-coding-agent，策展 provider 四家 + 任意 OpenAI/Anthropic 兼容网关经 `SHANNON_AI_BASE_URL` 直通。

这一派的工程上限就是 shannon：Temporal 工作流 DAG 做确定性骨架、每节点一个自由 pi 会话、submit-tool 调用即终结、TypeBox schema 校验失败返回 retryable 结构化错误当场补、一次性 Wolfi 容器只读挂载、resume 断点续跑逐一核对交付物——**"AI pentester 当软件工程产品造"的全语料范本**。

**适用边界（为什么产品平台不能走）**：预算与审计做不进宿主（tinyctfer 实测 Claude Code key 失效会无限重试挂起）；执行边界与多租户隔离依赖宿主权限 UI；换后端=重做会话层（Cairn 自认）。适合个人武器、比赛、内部实验分支。

---

## 3. 编排底座：通用框架缺席的事实与"确定性骨架"形态

### 3.1 事实

LangGraph 4 家、Strands 1 家、OpenAI Agents SDK 3 家、Eino/langchaingo/Temporal/pydantic-ai 各 1 家——**渗透域没有"事实标准框架"**。13 条共性第 13 条的结论（"33 个本体大多自研决策循环，通用框架没一家超过两个用户"）在 import 普查下成立，LangGraph 是唯一接近破例的（4 家）。

### 3.2 为什么：这类系统的 loop 都长在业务约束上

strix 的 tool_use_behavior 生命周期协议（只有 finish_scan/agent_finish 成功返回才许结束）、pentestagent 的循环级强制规划（loop-enforced, not prompt-based）、PentestGPT 的确定性状态机（LLM 只在 Supervisor 决策/Executor 执行两个接缝出现，compile_plan/compile_execution 是确定性校验）、theori 的 max_iters 微内核——**决策循环本身就是验证协议的一部分**，通用框架的通用 loop 装不下这些约束，所以每家都自己写。自己写的成本被 theori 证明可以只有 512 行。

### 3.3 LangGraph 的 4 家用户给的正确用法

不是"用它跑自由 agent"，而是**确定性骨架 + 图状态机**：atlantis 的 PoV 生产线（prepare→generate_blob→localize→extend→external，调试器实测行号喂回模型定位）、buttercup 的 11 节点补丁状态机（recursion_limit=200 + remaining_steps=25 双保险，反思路由可回任意上游）、nebula 的 Supervisor/Specialist/Verifier 三协议（analysis-only 模型返回 tool_calls 即抛错——工具必须经 broker）。共同点：**图的拓扑是领域知识，LLM 只在节点内活动**。

### 3.4 提炼：本语料最高级的编排形态

**"确定性骨架 + LLM 决策接缝 + 上报即工具"**，四件套样板：
- 骨架：Temporal DAG（shannon）/ 确定性状态机（PentestGPT）/ 图状态机（buttercup）/ 微内核循环（theori）
- 接缝：LLM 只出现在规划/裁决/生成三类节点，其余全确定性代码
- 上报：shannon 的 submit-tool（TypeBox 校验+terminate:true）、strix 的 create_vulnerability_report（10 必填+CVSS 服务端算分不许模型自报）、nyuctf 的 finish_task（提交权单点）
- 恢复：断点续跑四式——strix SQLite 会话重放、shannon Temporal resume+交付物核对、theori agent 序列化（jsonpickle+gzip 整态落盘可 fork）、PentestGPT trace episode 期刊（崩溃恢复从不重放 LLM，副作用感知重试：trace 有 action receipts 即不重试）

---

## 4. 工具调用与结构化输出：分水岭特征

1. **原生 function calling 已是默认**（strix/pentestagent/cochise/mapta/seclab/nyuctf/ctf-agent/pentagi…），但两条兜底路线仍然必要：XML/标签协议（BoxPwnr single_loop_xmltag、VulnBot `<execute>`/`<json>`、HackSynth `<CMD>`）面向无原生调用的模型；hackingBuddyGPT 把降级做成了三级阶梯（原生 tools→Action union 结构化输出→空格切分纯文本）+ OptimizedSchemaGenerator（$ref 递归内联拍平，弱模型友好）。
2. **解析/校验失败回喂重试是成熟度分水岭**：BoxPwnr（Pydantic 错误+常见问题清单回喂）、PentestGPT（exact-keys 严格解析+validation_feedback 截断 1000 字符回喂+从 trace 打捞被吞字段）、shannon（retryable 结构化错误当场补）、strix（结构化 errors 可修后重交）、theori（工具不存在/JSON 坏时回注 ERROR+可用工具清单）、atlantis（`_retry_parse` 异常文本回喂自修复）、BugTrace-AI（parseJsonWithCorrection 浏览器端自修复环）、PyRIT（失败轮先从记忆回滚再重发，不重放畸形输出）。一次性解析无纠错（EVA/VulnBot/HackSynth）全部集中在轻量/学术档。
3. **上报即工具（submit-tool 形态）**：把"最终发现"设计成带 schema 的工具调用而非自由文本——shannon（调用即终结会话）、strix（服务端 CVSS 算分+10 必填+去重法官）、nyuctf（提交权单点防多代理谎报）。这与 13 条共性 02（"上报必须走带 schema 校验的工具调用"）完全一致。
4. **多实例投票/竞速**：atlantis dictgen（parsing detector 双实例多数投票+flaky-token 两次自一致性过滤）、theori（每模型一个 agent 并行、先到先得其余取消）、ctf-agent（五模型同题竞速+逐模型递增冷却提交闸 [0,30,120,300,600]s）、Cyber-Zero（质量评审多模型投票任一否决即终止）。

---

## 5. 可靠性五件套（生产必配清单）

| 件 | 最佳实践 | 出处 |
|---|---|---|
| 重试 | tenacity 429/5xx 指数退避+抖动；重试判定借 `litellm._should_retry`；ContentPolicyViolation 专门错误路径 | atlantis、strix、deadend-cli |
| 缓存 | SQLite+Redis 两级（统计 saved）；dev_mode LangChain SQLiteCache 零成本复放；PatchCache sha256 缓存重放 | atlantis、buttercup、artiphishell |
| 成本 | tokencost/litellm `cost_per_token` 逐调用记账；TokenUsage 台账沿 parent 链归账；廉价法官选轮（~10x 降本） | atlantis、pentest-ai、theori、guardian-cli |
| 预算 | LiteLLM 虚拟 key max_budget 硬顶 + /key/info 回读实耗；Redis 预算池分配-回收；max_budget/max_turns 钩子超支优雅停可续；预算小睡睡到配额窗口；hackingBuddyGPT rounds/tokens/cost/duration 四维层级预算（花费记账到父链） | atlantis、strix、artiphishell、hackingBuddyGPT |
| 续跑 | SQLite 会话重放 / Temporal resume+交付物核对 / agent 整态序列化可 fork / trace 期刊+副作用感知重试（有 receipts 不重试） | strix、shannon、theori、PentestGPT |

观测件：Langfuse（pentagi/Cyber-AutoAgent/buttercup；Cyber-AutoAgent 用 Langfuse 托管提示词版本——本地 seed 远端+TTL 缓存+静默回退，全语料唯一）+ OTel（atlantis/artiphishell/pentagi）。

**上下文治理配套**（与五件套同档重要）：cai 两段式 auto-compaction（Phase 1 工具输出截断零 LLM 成本省 40-60%、Phase 2 超阈值才 LLM 摘要）；strix 工具输出三重闸（截断→溢写沙箱文件只留路径→压缩再截）；pentagi 工具结果 16KB LLM 摘要闸+量化字节预算链式摘要；PyRIT Crescendo 记忆级事务回滚（回滚不计轮次只受 max_backtracks 预算）。

---

## 6. 执行与沙箱（速览，详见 13 条共性 08）

一次性容器+只读挂载（shannon Wolfi 非 root、strix 每 scan 一个 Kali 容器、Cairn 每项目一容器）> rootless OCI+审批暂停（nebula，审批期间保留已耗成本记账）> 常驻容器（BoxPwnr/ctf-agent）> 本机直执行（多数，靠提示词兜底——反面）。平台级必配四件：容器隔离、出网白名单 fail-closed（T3MP3ST scopeViolation）、审批暂停（nebula）、密钥 regex 脱敏入库（pentagi）。

---

## 7. 对既有平台的迁移建议（回答"是否迁移 OpenAI SDK 开发"）

场景设定：一个已有确定性扫描引擎、≥6 套独立 LLM 客户端、对话 Agent 已在 LangGraph 上的渗透平台（即"双车道"改造的委托场景）。结论按层给：

### 7.1 接入层：收编到"openai-python 单一客户端 + LiteLLM 网关"，一步到位

- **openai SDK 当协议用**：全平台只留一种客户端类型 `openai.AsyncOpenAI(base_url=LiteLLM网关)`。不 import openai 之外的任何厂商 SDK、不写自研 http 客户端。这与 23+ 仓的公约数一致，且 GLM/Kimi/DeepSeek/OpenRouter/vLLM 全讲 OpenAI 方言，国产模型接入零额外成本。
- **LiteLLM 当治理层用**（atlantis 全套照抄）：虚拟 key（每任务/每租户 max_budget 硬顶）+ usage-based 路由 + 多模型 fallback（buttercup with_fallbacks）+ /key/info 回读实耗。预算池与任务生命周期绑定：分配-回收-再分配。
- **不给 openai SDK 的专属特性留位置**：Responses API/Agents SDK/线程托管一律不用——mapta 是唯一用 Responses API 的，代价是锁死单厂商。特殊订阅通道（如有）按 strix 样板单独留一扇门，不进主干。
- **弱模型降级阶梯预置**（hackingBuddyGPT 三级 + strix strict schema 自动降级）：工具调用统一经一层 adapter，原生 function calling 失败率高的模型自动降到 Action union/标签协议。

### 7.2 编排层：LangGraph 保留，不换框架，不自研通用 loop

- 对话 Agent（aibot）继续 LangGraph——语料中该框架 4 家用户全是"确定性骨架+图状态机"形态，与平台场景一致，且迁移成本为零。
- 战术 Agent（双车道领航员）**不引入新框架**：按 theori 样板自写薄决策循环（500 行量级的 msgs+工具注册表+max_iters+停滞检测），决策约束（预算耗尽/覆盖率平台/审批门）长在循环里——这正是"通用框架装不下业务约束"的结论。LangGraph 只用于多节点管线（如 PoC 生成回流生产线，buttercup 样板）。
- **明确不走宿主 CLI 路线**（Claude Code/Codex 当执行底座）：可作为内部实验分支评估（战绩最强），但产品主干上预算/审计/多租户/执行边界必须平台掌控。若未来引入，按 PentestGPT 样板把它归一成可互换后端事件流+stdio MCP 注入工具，而非让它当架构中心。

### 7.3 工具面：MCP 已是对的选择，补三件事

mcp_server 保留并扩展为唯一工具面（13 仓同款选择）：① 上报类工具全部 schema 校验+必填（strix 10 必填+CVSS 服务端算分——分数永远不让模型自报）；② 解析/校验失败错误回喂（分水岭特征）；③ 工具输出三重闸（截断→溢写文件→压缩）+ 密钥 regex 脱敏（pentagi）。

### 7.4 可靠性：按第 5 节五件套配齐，优先级为预算>续跑>缓存>成本>重试

对一个要长期跑多任务的产品平台，**预算硬闸和断点续跑是第一天就要有的**（ atlantis 虚拟 key + strix 会话重放是最短路径），缓存/成本/重试随规模补。

### 7.5 迁移顺序（与双车道改造 Phase 2 对齐）

1. 部署 LiteLLM 网关 + 虚拟 key 预算池（不动业务代码，先立治理）
2. 六套客户端逐个改为 openai SDK + base_url（行为等价替换，每替换一套跑对照）
3. 对话/战术 Agent 的 LLM 边界统一走网关，接 Langfuse 提示托管+OTel
4. 工具面补 schema 校验/回喂/三重闸
5. 预算/续跑接入任务生命周期

---

## 8. 附录：60 项目技术栈速查矩阵

（SDK=接入层主形态；编排=运行时底座；"宿主"=委托 CLI/harness；"—"=零 LLM 或不适用）

| 项目 | SDK | 编排 | 路由 | 结构化输出 | 沙箱 | 一句话定性 |
|---|---|---|---|---|---|---|
| BoxPwnr | 自研 llm_manager（LangChain 风格消息层） | 求解器矩阵（原生/XML/CLI/HTTP 四类驱动） | 多模型管理 | Pydantic 回喂 | Docker Kali+VPN | 透明度最高的基准 harness |
| hexstrike-ai | 零 LLM | MCP 工具服务器 | — | — | 本机 shell=True | "AI-powered"名不副实，错误恢复知识库可移植 |
| pentest-ai-agents | 零代码（宿主执行） | Claude Code 宿主 | frontmatter 定 model | 发现库 schema | 宿主权限 UI | "agent 即文件"纯粹样本 |
| pentest-ai | litellm（工厂四 provider） | 自研 16 专科代理+oracle 引擎 | anthropic/openai/ollama/litellm | oracle 协议 N/N 重放 | safe 分级+throwaway | L3 验证文化天花板 |
| EVA | 自写六后端 | 自研单步循环 | 菜单切换 | 严格 JSON 无自修复 | 无（人在环） | 人在环最小实现 |
| Dark-Moon | OpenCode 宿主侧 | 宿主+MCP 受控接口 | 宿主 | 三态状态资格块 | Docker+PrivacyVault 令牌化 | LLM 数据主权机制化唯一样本 |
| Pentest-Swarm-AI | 自写三后端 | 自研事件驱动群体+信息素黑板 | Claude/OpenAI 兼容/Ollama | 类型化发现+半衰期 | 未见 | 信息素二代（Ed25519 溯源+MemoryGraft） |
| Cyber-Zero | 自写客户端 | 数据合成流水线 | 多模型投票 | markdown true/false | 无（模拟环境） | 唯一数据生产者（SFT 轨迹合成） |
| CyberStrike | TS 自研（150+ provider 声明） | 自研 TUI 编排+MCP | 多模型 | 3-gate 差分（提示层） | Bolt 远程+本机 | 知识资产规模极点（7,656 SKILL.md） |
| CyberStrikeAI | openai_compatible+claude 双通道 | Eino ADK 三编排 | 默认 qwen3-max | 黑板结构化工具 | RBAC+HITL 无容器 | 平台形态先行者（反面教义也在） |
| pentestagent | litellm | 自研 loop+Crew 编排（既是 MCP client 又是 server） | litellm 全家 | finish 协议+notes 三类硬校验 | local/Docker+scope 门 | 图算法战略建议独有样本 |
| seclab-taskflow | OpenAI Agents SDK+3 后端 | 声明式 YAML 工作流引擎 | 多模型并行/竞速语义 | Pydantic v2+lint | 无治理 | 声明式编排完成度最高 |
| AutoPentestX | 零 LLM | 六阶段固定流水线 | — | — | 本机 | 虚构型零 AI（Neural Core 横幅） |
| PentestGPT | claude-agent-sdk+codex（归一） | 确定性状态机+两接缝 | 双后端互换+并发对照 | exact-keys+trace 打捞 | CLI 原生三档沙箱 | 验证纪律最严的重写范本 |
| VulnBot | 自写统一入口 | 自研三角色串行 | 单模型 | 标签协议无纠错 | SSH 远程 Kali | 团队协作最小诚实实现 |
| shannon | pi harness（策展四 provider+兼容网关直通） | Temporal DAG+12 agent | 直连单模型 | submit-tool+TypeBox | 一次性 Wolfi 只读挂载 | "当产品造"的全语料范本 |
| garak | 26 种 generator | 探针×检测器扫描器 | 裁判/目标分离 | 评分三值+校准 | 无执行面 | "攻击模型"事实标准 |
| CTFTiny | 零 LLM | 纯基准资产 | — | challenge.json | 附 Docker 资产 | 自足判分轻量基准 |
| nyuctf_agents | 自写三后端（openai/together/vLLM） | D-CIPHER 双会话 | 三后端 | finish_task 提交权单点 | 共享 docker | 基准官方教科书基座 |
| Nettacker | 零 LLM | YAML DSL 引擎 | — | 证据导向 regex | 本机 | 老牌零 AI 对照基线 |
| PentesterFlow | openai/gemini/ollama 三后端 | 自研 1,508 行主循环 | 三后端直连 | 提示层契约 | 本地 shell+三态审批 | 提示词知识密度天花板 |
| Zen-Ai-Pentest | 自写 agent 族（Kimi OAuth 桥） | 蜂群主控+四专员 | Kimi 直连 | JSON 状态机自报 | guardrails 沙箱 | 212k 行蔓延警示样本 |
| LuaN1aoAgent | Pi SDK | P-E-O 三角色+图调度 | 未见 | Projector 校验拒稿重交 | Docker+网络沙箱镜像 | 认识论最严格（科学方法契约） |
| atlantis | litellm 网关 fork+langchain+openai+vLLM/LoRA/GRPO | LangGraph 状态图+K8s 分布式 | usage-based-routing-v2+多模型竞赛+ban 熔断 | FDP 白名单+投票+回喂 | K8s+timeout 沙箱执行 | 工程密度之最、预算治理唯一 |
| HackSynth | openai/transformers | 自研 Planner+Summarizer | 双管线 | `<CMD>` 标签无纠错 | Docker attackbox/vulnbox | 论文即仓库极简样本 |
| cai | vendored OpenAI Agents SDK 深改+litellm | Agents SDK 风格 25+ agent+patterns | litellm 全家+无过滤端点开关 | TRACE 七段合同 | 五级执行路由 | 研究味最重的史料级参考 |
| cochise | litellm（3 文件） | Planner-Executor 双层 | 直连 | 无（军规在提示层） | SSH Kali | 630 行拿域管的极简极值 |
| AI-OPS | litellm(349 行 llm.py) | 自研 runner+ReAct 提示 | litellm BYO | 白板三字段提示层 | 本地+白名单准入 | 白板=检查点的激励相容设计 |
| mapta | openai SDK（Responses API） | 自研三层代理 | gpt-5 硬编码 | 工具参数层结构化 | env 工厂注入沙箱 | 单文件高密度+XBOW 对照 |
| nebula | 多适配器（可拆卸） | LangGraph Supervisor/Specialist/Verifier | provider 费率显式算 | pydantic DAG 校验+三态 | rootless OCI+审批暂停 | "人在权威位"最彻底 |
| pentest-copilot | TS providers.ts 1,589 行 | 自研 AgentService+Swarm 竞速 | 多 provider+racer 竞速 | engagement state 持久 | SSH Kali+Mythic 同意门 | 工具链集成深度之最 |
| tinyctfer | Claude Code 宿主 | 宿主+MCP（代码即工具） | Anthropic 兼容直连 | 无 | Docker 沙盒+VNC | 99 行第 4 名的极简哲学 |
| deepteam | DeepEval 抽象 | 纯函数流水线 | 生成/判定双模型 | JSON confinement | 无执行 | 37 类红队分类学（判定薄） |
| AutoPentest-DRL | 零 LLM（PyTorch DQN） | Nmap→MulVAL→DQN | — | — | 逻辑/真实双模式 | 前 LLM 范式化石 |
| T3MP3ST | 三轨（API/本地 CLI keyless/本地模型） | 自研 ReAct+盲匠主从 | 按角色分工多模型 | OpPlan JSON+反驳面板 | egress fail-closed 收口 | "可复现的诚实"产品级机制 |
| reaper | 零 LLM | MITM 代理+检索 | — | — | scope 门在 CONNECT 前 | AI 相邻工具（agent 生态周边） |
| hackingBuddyGPT | litellm 单上游(154 行) | UseCase 轮循环骨架 | litellm | pydantic 反射 schema+三级降级 | SSH/本地 | 实验框架+四维层级预算 |
| BreachWeave | Pi 框架 | Pi 宿主+三角色 | frontmatter 定 model | Observer 看板协议（提示层） | 未见（scope-guard 未读） | TCH 二期冠军实战样本 |
| PyRIT | 自写 prompt_target 多态 | 红队编排 SDK | 双端抽象+能力协商 | schema 单源+回滚重发 | docker/ 部署 | 红队"库派"标准（回溯协议可移植） |
| agentic_security | 自写 httpx+provider 目录 | SSE 流水线 fuzzer | OpenAI 兼容 spec | 无 | 无执行 | 轻量 UI 派+贝叶斯早停 |
| Cairn | 宿主（claudecode/codex/pi 适配器） | 黑板+轮询调度循环 | 多 worker 可配+公平调度 | 信封嗅探+不变量校验 | 每项目 Docker+skip-permissions | TCH 唯一 AK 的"少即是多" |
| promptfoo | 自研 100+ provider 注册表 | 评测矩阵穷举 | 云端/本地双模式 | 断言 50+ 类型 | 无执行 | 红队产品化平台代表作 |
| vulnhuntr | 三客户端（anthropic/openai/ollama） | 固定两层循环×7 轮 | CLI 三选 | prefill JSON+pydantic | 无执行 | 1,334 行 22 个 0-day |
| redamon | 未见明示（400+ 声明） | 自研 ReAct 1,468 行+Fireteam | 未见 | Cypher 九查询零 LLM+LLM 关联 | Kali 沙箱+mitmproxy | 链路最长+OPSEC 提示词最细 |
| artiphishell | litellm 网关+langchain(agentlib) | 声明式数据流 YAML 56 组件 | 网关+多 LLM 轮换+预算小睡 | IJON 单行插入契约+`<YELL>` 纠错 | 56 容器+Tailscale | 预算/反馈工程极深（复杂度爆炸） |
| LLM4Pentest | 零代码资源库 | — | — | — | — | 文献地图+第三方评测锚点 |
| agentic-radar | openai/Azure SDK | AST 静态分析三段 | gpt-4o 硬编码 | 分类器 JSON | 无执行 | "AST 干重活 LLM 当分类器" |
| aixcc-afc-archive | 自写四家适配 | 自研 512 行微内核 | 回退/竞速/分档三用法 | 工具文档单源校验 | Docker 全容器化 | 冠军微内核+模型多样性武器化 |
| buttercup | litellm 统一+LangGraph | LangGraph 11 节点状态机 | with_fallbacks 回退链 | AI-prefill XML+模糊解析 | Docker OSS-Fuzz | ToB 级可靠性+三重机器闸 |
| communitytools | Claude Code 宿主 SDK | 宿主三角色+44 技能 | 宿主 | 五项 all-or-nothing 检查 | Docker Kali | 失败喂知识唯一双满分 |
| strix | litellm+openai SDK（codex 通道） | agents SDK 风格蜂群 | litellm 任意 ID+strict 降级 | 10 必填+服务端 CVSS | 每 scan 一次性 Kali 容器 | 蜂笼协议+多模型兼容投资之最 |
| promptmap | 自写六后端 | 规则×迭代流水线 | 双模型分离（目标/裁判） | 单词契约+确定性 n-gram | 无执行 | "能确定性判的不用 LLM"范本 |
| ctf-agent | pydantic-ai+Claude SDK+Codex | Coordinator 蜂群+五模型竞速 | QUOTA_FALLBACK 回退表 | 提交闸+旗去重 | 每题 Docker | 战绩/行数比之最（52/52） |
| AI-VAPT | 零 LLM 零后端 | 无 | — | 硬编码假数据 | 无 | 纯 UI 原型（声实落差极值） |
| pentagi | langchaingo+自研 10+ provider | HTN 计划+自研 run-loop 六专家 | provider 注册表+ID 格式探测 | subtask_patch 增量协议 | Kali 容器 CapDrop 白名单 | 平台派：三重记忆+多租户之最 |
| Cyber-AutoAgent | Strands（bedrock/ollama/litellm） | Strands 框架+声明式插件 | 三通道 | Proof Pack 七要素（提示层） | Docker | Langfuse 提示托管唯一+置信度算术 |
| xalgorix | Go internal/llm（未逐行） | 自研平台+受限验证器 | 未见 | submit_verdict 不对称裁决 | provision 起靶+scopeguard | 验证工程完成度最高 |
| deadend-cli | 自研 core_agent+litellm 痕迹 | ADaPT 按需分解+supervisor | Kimi K2.5 为主 | 置信度五档+反伪造块 | Docker/WASM 双后端 | 置信度驱动决策主轴 |
| BugTrace-AI | 浏览器 fetch→OpenRouter | ~20 单功能组件单遍 | OpenRouter 回退表 | JSON 自修复环 | 无执行 | "AI 辅助非 agent"基准样本 |
| guardian-cli | 自写 8 provider+插件契约 | WorkflowEngine+多 agent | 廉价法官选轮 | 五段 schema 正则 | 本地 shell | 防御性设计密度之最 |

---

## 9. 结语

62 个仓库读下来，接入层和编排层其实只回答了一个问题：**哪些东西是 Commodities，哪些是 Moats**。

OpenAI 协议、LiteLLM、MCP、原生 function calling、pydantic 校验回喂——这些是 Commodities，直接采用，一行都不要自己发明。决策循环、验证协议、预算账本、事实图——这些是 Moats，语料里每一家值得记住的项目，自己的代码都只写在这四样上，theori 甚至把 loop 写到只有 512 行，把省下的全部篇幅给了 oracle 和模型竞速。

迁移到 OpenAI SDK 开发的正确姿势因此很朴素：**把它当电源插头，不要当发动机**。插头上省下来的每一行，都该花在裁决权和记忆上。

*本报告全部结论可回溯：60 份审计见 `docs/audits/`；13 条共性总结见 `docs/blog/2026-08-27-blackbox-pentest-agent-methodology.md`；import 普查命令与原始输出存于本次审计会话记录。*

# ipa-lab/hackingBuddyGPT 逐行代码审计

> 审计对象：HackingBuddyGPT —— TU Wien IPA-Lab（GitHub Accelerator 2024 成员）的学术研究框架："帮助伦理黑客用 50 行代码玩转 LLM"。FSE'23 论文《Getting pwn'd by AI》+ arXiv 2310.11409 LLM 对比研究的载体。与此前审计的所有系统不同，这是**实验框架**形态：一切设计为"假设—变量—基准"服务。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/ipa-lab/hackingBuddyGPT |
| 本地路径 | `repos/agents/hackingBuddyGPT/` |
| 审计基线 commit | `b265377`（merge PR #156 from development） |
| 语言 / 规模 | Python，~15,786 行（不含测试）；src 包 + benchmark_privesc.py 独立基准harness |
| Landscape 定位 | 类型：渗透 Agent / Stars：高（GH Accelerator）/ 一句话：50 行代码起步的 LLM 渗透实验框架（SSH/local shell + privesc/web/web-api 三线） |
| License | MIT |
| 关联论文 | Getting pwn'd by AI（FSE'23，arXiv:2308.00121）；LLM 对比研究（arXiv:2310.11409） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：让安全研究者以最小代码量实验"LLM 能否做 X"——Linux 提权（SSH/local shell）、Web 渗透（WIP）、REST API 文档化+测试（WIP）。旗舰产出是**可复现的 privesc 基准**（配套 benchmark-privesc-linux 靶机库）。
- **输入输出**：usecase（dataclass + perform_round）→ OpenTelemetry/GenAI JSONL 逐 run trace（也是评分数据源）+ 控制台记录。
- **差异化定位**：**框架而非产品**——不给"最优 agent"，给"可配置变量空间"（模型/历史策略/提示策略/RAG/CoT 开关全是实验参数）。50 LoC 最小用例的可达性是核心卖点。

## 2. 架构总览

```
wintermute CLI（use_cases 注册表发现 + configurable 参数注入：CLI/env/.env）
   ▼
UseCase（dataclass）：AutonomousUseCase 轮循环（before_run→perform_round×N→after_run）
   ├─ 线 A（privesc，论文线，最成熟）：
   │    CommandStrategy（模板渲染 + simple-text 命令解析）或 ChatAgent（真聊天史+函数调用）
   │    → Capability（反射式工具模式）→ SSHConnection / LocalShell
   ├─ 线 B（web/web-api，研究前沿，粗糙）：
   │    SimpleStrategy + PromptGenerationHelper（确定性提示编排）
   │    + PenTestingInformation（OpenAPI 规格驱动的 14 阶段场景工厂）+ 三种提示策略（ICL/CoT/ToT）
   └─ Limits（层级预算：rounds/tokens/cost/duration，父子链传播）+ Logger（OTel JSONL）
LiteLLM 上游（统一 get_response：聊天史+tools / Mako 模板 两种风格一个入口）
```

- **两条产品线的成熟度天差地别**（亲读确认）：privesc 线是论文级（变量开关齐整、双孪生对比设计）；web-api 线仍在快速演化（提示生成器里烘焙基准目标特判，见 §6）。
- **执行环境**：SSH 远程或本地 shell（README 明示危险）；无容器隔离（对比 Cairn 的每项目容器）。

## 3. 目录结构逐层解读

```
src/hackingBuddyGPT/
├── usecases/        # ★ usecase.py(171 基类+注册表) linux_privesc(264) minimal×2 strategies.py(201)
│   │                  agents.py(356 ChatAgent+SubAgent) web×3 web_api_testing/ web_api_documentation/
├── capability.py(355) # ★ 反射式工具系统（三级调用规约）
├── capabilities/    # 15 个具体能力（SSH/local shell/http_request/submit_flag/…，薄实现）
├── utils/
│   ├── llm.py(154)  # ★ LiteLLM 上游（亲读全文）
│   ├── limits.py(197)# ★ 层级预算（亲读全文）
│   ├── histories.py(46) # 三档历史（亲读全文）
│   ├── configurable.py(837) # 参数注入框架（结构亲读）
│   ├── prompt_generation/ # ★ web 线提示工程：helper(591)+information 七混入(~3k 行知识库)
│   │                        + prompts 三策略（ICL/CoT/ToT）
│   └── connectors/ (ssh/psexec/local_shell)
├── analysis/log_model.py # JSONL trace 读取模型（基准评分用）
└── cli/ wintermute（入口）log_viewer log_analyze
benchmark_privesc.py(585) # 独立基准 harness：privesc_* 容器舰队 × usecase × LLM
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 UseCase 体系与主循环（usecase.py + strategies.py 全文亲读）

- **UseCase 基类**：dataclass + `@use_case` 装饰器注册（重名即 IndexError）；AutonomousUseCase 固化轮循环骨架（log.section("round N") 包每轮；异常→run_was_failure(traceback) 后 re-raise）。
- **AutonomousAgentUseCase[T]**：`__class_getitem__` 泛型订阅把任意 Agent 类包成 usecase——init/before/after/perform_round 全委托，agent 以 Transparent 字段注入。用类订阅语法做组合，全景观仅见。
- **CommandStrategy**（文本线主循环）：`get_next_command` 做**历史 token 预算数学**（context − SAFETY_MARGIN − 模板 token − overhead → trim_result_front 截历史**保尾部**）→ Mako 渲染（能力块/历史/状态/指导全内联）→ LLM 裸命令字符串 → `postprocess_commands`（CoT 模式 `<command>` 标签正则、无匹配 assert 假）→ simple-text 解析执行 → check_success。
- **SimpleStrategy**：web 线骨架，`_got_root` 布尔循环。
- 三档历史（histories.py）：**HistoryNone / HistoryCmdOnly（压缩）/ HistoryFull**——本身就是论文变量（"历史保留多少"）。

### 4.2 Capability 系统（capability.py 355 行全文亲读）——本项目最精巧处

- **反射式工具模式生成**：`to_model()` 用 inspect 抓 `__call__` 签名 → pydantic `create_model`（describe() 当 `__doc__`）→ JSON schema。工具定义零重复：实现即文档即 schema。
- **三级调用规约降级阶梯**（为不同模型能力准备）：
  1. `capabilities_to_tools`：OpenAI/litellm 工具调用，配 **OptimizedSchemaGenerator**（递归内联全部 `$ref` + 剥 `_` 前缀字段 + 环引用守卫——把 schema 拍平给弱模型）；
  2. `capabilities_to_action_model`：全部能力并成一个 Action union 模型（结构化输出模式）；
  3. `capabilities_to_simple_text_handler`：**零函数调用**——"capability_name p1 p2" 空格切分 + 类型转换 + **默认能力兜底解析**（未知命令先整串当默认能力参数试、再剥首词重试）。`function_call_capability` 用签名手术（注入 self、wraps+`__signature__` 覆写）把任意异步函数变能力。
- 15 个具体能力是薄实现（SSHRunCommand/SSHTestCredential/HTTPRequest/SubmitFlag/RecordNote/PsExec×2/PythonTestCase/YamlFile/EndRun…），真正的机制在基类。

### 4.3 Agent 层与 SubAgentCapability（agents.py 356 行全文亲读）

- Agent → TemplatedAgent（AgentWorldview 状态机：to_template/update）→ **ChatAgent**（真聊天史：system 消息 + assistant/tool 消息累积于 `_prompt_history`；**run_tool_calls 用 asyncio.gather 并行执行一轮内的多个工具调用**）。
- **每轮注入限额消息**（"Your limits are: remaining_rounds=…, remaining_cost=…"）——预算对 LLM 可见，让它自己规划收缩。
- **SubAgentCapability（agent 即工具）**——父代理调用签名 `(system_prompt, max_rounds, max_cost, capabilities: list[str])`：
  - **能力委托白名单**：父代理选择把哪些能力下放给子代理（describe 里教学"子代理只知道你系统提示里给的信息，务必具体"）；
  - **层级限额**：`parent_limits.sub_limit()` 从父预算切割（超额直接 ValueError）；register_round/register_message **向父链传播**——子代理花费记在父账上（limits.py 亲读确认 parent_limited=min 语义）；
  - **自动注入 complete 能力**（闭包捕获结果）——唯一回传通道；
  - **限额耗尽的强制总结**：剥光子代理能力只留 complete + "THIS IS YOUR LAST ROUND… DO NOT DO ANY OTHER TOOL CALLS"——与 Cairn conclude 兜底同精神（防僵尸的收口），TODO 注释诚实承认"白送了一轮"。
- **minimal 双孪生对比设计**：MinimalPrivEscLinux（模板线）vs MinimalToolCallPrivEscLinux（tool-calling 线）——同一任务的两种驱动方式并排可跑，系统提示里预教"每命令独立 shell 无状态保持，须单命令内自证（sudo id）"；**task_solved 工具**让 agent 携证据自报成功（"Do not call it on a guess"）→ limits.complete()。验证姿态：策略线是机器判（got_root 正则检末行+ANSI 剥离），孪生线是自报+证据。

### 4.4 LLM 上游与预算（llm.py + limits.py 全文亲读）

- **LiteLLM 单上游双风格一个入口**：list → 原样发送+capabilities 转 tools；str/Template → Mako 渲染包成单 user 消息。LLMResult 携带全观测（reasoning_tokens/completion_cost/finish_reason/provider/usage JSON）。**代理支持带显式 TLS 关闭开关**（注释明说为 Burp/mitmproxy 拦截代理准备——渗透工作流原生支持）。
- **Limits 层级预算**：四维（rounds/tokens/cost/duration）+ RunState(COMPLETED/CANCELLED) + reason 字符串；`reached()` 先查父（"Parent limit reached"原因透传）；remaining 全部 parent_limited(min)；sub_limit 四维校验防超额；`__str__` 输出剩余量（正是注入提示的那个串）。

### 4.5 提示词（privesc 线全文亲读——内嵌 linux_privesc.py）

- **default_template**：低权用户+目标用户 + ${cot} + 能力块 + 已试命令历史（"Do not repeat"）+ 可选状态 + 指导 + 上轮分析；结尾"State your command. … Do not add any explanation or add an initial `$`"——输出契约押在措辞上。
- **template_cot**：经典 CoT 尾巴 + `<command>` 标签包裹要求。
- **template_update_state**（事实列表合并）："统一旧事实与新命令输出，尽量精简"——每命令后的状态压缩循环。
- **template_analyze / template_rag**：结果分析（带可选 RAG 背景）与"生成向量库检索句"。
- **结构化指导开关**：经典 privesc 五连查硬编码（SUID/sudo -l/crontab/世界可写/内核版本）。
- **web 线提示体系**（结构+CoT 版亲读，ICL/ToT 与知识混入未全读）：BasicPrompt→TaskPlanningPrompt→CoT/ToT；文档化六步端点探索课程（root→instance /id→subresource→related /id/x→multi-level→query params）；"Let's think step by step" 插在目标之后；PenTestingInformation 七混入（core/auth/authz/injection/session/ratelimit/misc）按 **14 个 PromptPurpose 阶段**（SETUP→认证→授权→输入校验→信息泄漏→会话→XSS→CSRF→业务逻辑→限流→错误配置→日志）从 OpenAPI 规格生成确定性场景清单（faker 造账户、CSV 凭据、分类端点：public/protected/refresh/login/account/sensitive-action…）。

### 4.6 基准与评测（benchmark_privesc.py 头部亲读）

- privesc_* Docker 靶机舰队 × usecase × LLM 的批量 harness；**每 run 的 OTel/GenAI JSONL 是唯一事实源**（`state == "got root"` 即得分），harness 复用项目自己的 log_model 读取——产出即评测的自洽闭环；Markdown 报告含逐靶机命令日志/成本/trace 链接。

### 4.7 结果验证与去误报

- privesc 线：got_root（对 conn.hostname 的目标特定末行检测）或 SSHTestCredential 精确串匹配（"Login as root was successful\n"）；tool-calling 线靠 task_solved 自报（提示词要求证据）。**无独立验证代理/裁判**——验证是最薄的一层（研究框架把验证交给基准靶机的 ground truth）。
- web 线：expected_response_code + RecordNote 记录，无机器判分。

### 4.8 安全与隔离

- local shell 模式明示无沙箱危险；SSH 线在目标机执行；密钥经 configurable 的 Secret 参数（repr 脱敏）；MIT 协议无使用限制条款（README 有伦理定位但无 Disclaimer 段）。

## 5. 值得借鉴的设计与技巧

1. **反射式工具定义**（实现即文档即 schema）：inspect 签名→pydantic 模型→JSON schema 一条龙，工具三处定义零重复。
2. **三级调用规约降级**（tools/Action-union/simple-text+默认能力兜底）：同一能力集适配从强到弱的模型——多模发布/模型对比研究的实用件。
3. **SubAgentCapability**：能力委托白名单 + 层级预算（花费记账到父链、sub_limit 四维校验）+ complete 注入 + 耗尽强制总结——agent 即工具的最完整学术实现。
4. **限额消息每轮注入**（剩余轮次/成本对 LLM 可见）：让模型自己做预算规划——prompt 与预算系统的耦合点。
5. **minimal 双孪生**（模板线 vs tool-calling 线同任务并排）：变量控制式架构——框架为对比实验而生的明证。
6. **JSONL trace 即评分源**：基准 harness 读自己产出的遥测判分，无第二事实源。
7. **OptimizedSchemaGenerator**（$ref 全内联+私字段剥离）：弱模型的工具 schema 拍平器。
8. **历史三档（None/CmdOnly/Full）+ 历史预算数学**（保尾截断）：把上下文管理本身做成实验变量。
9. **拦截代理友好的 LLM 客户端**（proxy+显式 TLS opt-out）：渗透工作流细节。

## 6. 局限与改进点（亲读发现，按线分）

- **web/web-api 线粗糙且有过拟合痕迹**：prompt_generation_helper 里**烘焙基准目标特判**（"coin"/"reqres"/ballardtide/brew 风格 ID 的端点怪癖、`season_averages\general` 硬替换）——通用帮助器与基准靶机耦合；实现级 bug 至少一处（`path.join(part)` 把字符串当分隔符用）；`_check_prompt` 的 validate_prompt 是直通空壳（max_tokens 参数已死）。
- 验证层最薄：got_root 的末行正则与精确串匹配易被输出噪声干扰；task_solved 自报依赖提示词自律。
- privesc 提示把 SSH 密码内联进模板（benchmark 靶机语境可接受，复用需注意）。
- 知识库（~3k 行 _pentesting_* 混入）与提示策略类未全文亲读（同构推定+入口/调度亲读）。
- 无容器隔离（对比 Cairn/artiphishell），安全边界全靠使用者的授权纪律。

## 7. 与其他已审计项目的对比

| 维度 | hackingBuddyGPT（本项目） | Cairn | PentestGPT | garak |
|---|---|---|---|---|
| 形态 | **实验框架** | 黑板搜索引擎 | 确定性内核 | 扫描器 |
| 目标 | 假设检验（变量空间） | 通用问题求解 | 交互式渗透 | 模型弱点普查 |
| 工具调用 | **三级降级阶梯** | CLI 进程包装 | 提示内嵌 TODO | 无（探针即数据） |
| 预算 | **层级 Limits（记账到父）** | 轮次上限 | 无 | run 级 |
| 子代理 | **能力委托+强制总结** | 无（同构 worker） | 无 | 无 |
| 评测 | **JSONL 即事实源+靶机舰队** | 比赛裁判 | 人工 | Se/Sp CI |

它补上景观里的"学术实验框架"一极：pentest-agent 们给**答案**，hackingBuddyGPT 给**做实验的台子**——其 50 LoC 可达性、变量开关密度（模型×历史×提示策略×RAG×CoT×子代理）与配套靶机基准，是所有已审项目里最接近"LLM 安全研究方法论"本体的。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `usecases/usecase.py` `minimal_linux_privesc_tool_calling.py` | ✅ 亲读全文 | 171+89 |
| `usecases/linux_privesc.py` `strategies.py` | ✅ 亲读全文 | 264+201（含全部 privesc 提示词） |
| `usecases/agents.py` | ✅ 亲读全文 | 356（ChatAgent+SubAgentCapability） |
| `capability.py` `utils/capability_manager.py` | ✅ 亲读全文 | 355+67（三级调用规约） |
| `utils/llm.py` `limits.py` `histories.py` | ✅ 亲读全文 | 154+197+46 |
| `utils/prompt_generation/prompt_generation_helper.py` | ✅ 亲读全文 | 591（含基准特判与 bug 记录） |
| `prompt_generation/information/` pentesting_information+prompt_information | ✅ 亲读全文 | 28+88（调度与枚举体系） |
| `information/_pentesting_core.py` | ✅ 部分 | 450/816（初始化/调度/setup/verify 亲读；其余生成器同构） |
| `prompts/basic_prompt.py` `task_planning/chain_of_thought_prompt.py` | ✅ 部分 | 200/361 + 120/249（课程与组合机制亲读） |
| `capabilities/` 15 个具体能力 | ✅ 部分 | 经 capability 基类与调用面确认（薄实现） |
| `utils/configurable.py` | ✅ 部分 | 结构亲读（parameter/Global/Secret/Transparent+嵌套注入） |
| `benchmark_privesc.py` | ✅ 部分 | 头部 50/585（设计文档级 docstring 亲读） |
| `usecases/web_api_testing/` `web_api_documentation/` `web/` | ✅ 部分 | simple_web_api_testing 结构亲读（方法清单+流程） |
| `information/` 其余五混入（auth/authz/injection/session/ratelimit/misc ~2.7k 行） | ⬜ | 场景内容同构推定 |
| `prompts/state_learning/`（ICL 427/状态规划）`tree_of_thought_prompt.py` | ⬜ | 结构确认未逐行 |
| `utils/openapi/` `web_api/`（response_handler 661 等） `connectors/` `logging.py` `cli/` `analysis/` `tests/` | ⬜ | 未读/结构登记 |

## 9. 结论

**HackingBuddyGPT 的核心实现思路是：把"LLM 渗透"降维成可实验的变量空间——UseCase 轮循环骨架上，privesc 线以模板渲染/真聊天史双孪生驱动反射式 Capability 系统（三级调用规约适配强弱模型），层级 Limits 把预算做成记账到父链的一等公民并可注入提示让模型自管，SubAgentCapability 用能力委托白名单+强制总结把"子代理"本身变成一个工具；web-api 线则以 OpenAPI 规格驱动的 14 阶段确定性场景工厂+三提示策略探索 API 安全测试；一切以 OTel JSONL trace 落盘，基准 harness 读同一事实源判分。** 它是已审 19 项中唯一以"研究者要什么"而非"攻击者要什么"为中心设计的系统——工程深度集中在能力抽象与预算层级（这两处达到产品级），场景内容与验证层则刻意保持薄（交给基准靶机）；web 线的基准特判痕迹也如实提醒：学术代码的"通用性"要按论文贡献而非代码声明来读。

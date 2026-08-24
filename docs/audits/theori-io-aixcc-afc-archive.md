# theori-io/aixcc-afc-archive 逐行代码审计

> 审计对象：Theori "Robo Duck" —— **AIxCC 决赛冠军 CRS**（2025 年 7-8 月决赛提交版本的完整快照，2024-08 至 2025-06 写成）。
>
> 审计方法注记：约 30k 行 Python + Rust 辅助（src/*.rs）。核心链（agent 框架全文、提示词 YAML 关键段、模型配置、架构图、app 驱动结构）亲读；agents/modules 各文件按职责登记。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/theori-io/aixcc-afc-archive |
| 本地路径 | `repos/aixcc/aixcc-afc-archive/` |
| 审计基线 commit | `3144be4f1e524040a3451335c0463998a90f4bee`（2025-08-05，决赛归档态，明示不再维护） |
| 语言 / 规模 | Python ~29.7k 行（crs/ 24k + main/eval/utils）+ Rust 辅助（log/http/patch/metrics）+ prompts/default.yaml 2,684 行 |
| Landscape 定位 | 类型：AIxCC CRS / **决赛冠军** / 一句话：全自动化模糊测试+LLM 漏洞分析与 PoV 产出+补丁的冠军系统，决赛环境 1 小时可烧 $1,000+ |
| License | 见仓库（归档发布） |
| 关联论文 | 无（有公开博客与 agent traces：theori-io.github.io/aixcc-public） |
| 审计日期 / 人 | 2026-08-24 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：AIxCC AFC 决赛——自动找漏洞（PoV+SARIF）并打补丁，在竞赛 API 上与其它 CRS 同台。
- **差异化定位**（对照已审的 buttercup/artiphishell）：冠军系统的答案是**"少即是多"的自研 agent 微内核**——不依赖 LangChain/LangGraph，512 行手写 agent 循环 + 2,684 行单文件提示词 YAML + 13 份模型配置 TOML；核心创新在**多模型竞速**、**PoV 调试 agent 即工具**、**分支翻转引导 fuzzing**。

## 2. 架构总览（docs/crs-architecture.md 亲读）

```
CRS/竞赛 API → TaskDB → build → fuzz ─┬─ minset → Corpus → CoverageDB → Frontier → BranchFlip(agent) → 新种子回 Corpus
                                        └─ crash → LLMTriage(agent)
Task 全量模式: Infer(静态)+AInalyze(LLM) → VulnReport → Score(阈值) → VulnAnalyze(agent)
Task 增量模式: Diff(agent 分析 diff) → AnalyzedVuln
AnalyzedVuln → DedupeVuln(LLM 分类器去重) ─┬→ POVProduce(agent, 失败→close_pov 提示重试) → Corpus 试跑 → LLMTriage
                                            └→ GenPatch(PatcherAgent)
Products(POV/Patch/SARIF) → Bundle → 竞赛 API
```

- **编排方式**：`crs/app/app.py`（2,022 行）的 `CRS` 类是中枢——asyncio 后台 worker（BackgroundWorker + WorkType 队列 + WorkDB 持久化）驱动上述数据流；agent 是被动组件（被 worker 调用）。
- **LLM 层**：`crs/common/llm_api.py` 自研多 provider 适配（Anthropic/OpenAI/Azure/Google），`priority_completion` **带优先级的补全调度**（工作队列里高优先级任务先得模型配额）；13 份 `configs/models-*.toml` 按决赛日期/强度分档（best/final/weak/very-weak/none），**每个 agent 类可配模型列表**（首选+回退+竞速成员）。
- **执行环境**：Rust 辅助层（日志/metrics/补丁应用）+ Docker 全容器化；README 明示"为决赛大预算调优，1 小时 $1,000+"。

## 3. 目录结构逐层解读

```
├── crs/agents/       # ★ 18 个 agent：agent.py(框架512行) triage vuln_analyzer diff_analyzer
│                     #   pov_producer produce_patch dynamic_debug branch_flipper classifier
│                     #   func_summarizer generate_kaitai harness_input_decoder source_questions
│                     #   xml_agent tool_required_agent
├── crs/modules/      # 工具后端：fuzzing/project/search_code(1063行)/coverage/debugger/
│                     #   kaitai/python_sandbox/source_editor/static_analysis/testing/graph
├── crs/app/          # app.py(中枢) products_db
├── crs/common/       # llm_api/prompts(PromptManager) workdb docker sarif_model(2389行) fuzzy_patch
├── crs/analysis/     # full.py 全量静态分析编排
├── prompts/default.yaml  # ★ 2,684 行：agents(system/user/tools) + tools(24个) + custom 片段
├── configs/models-*.toml # ★ 13 份模型分档配置
└── src/*.rs          # Rust 辅助（log/http/patch/path_suffix/metrics）
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 Agent 微内核（crs/agents/agent.py 全文亲读——本系统最精华处）

- **不依赖任何 agent 框架**：512 行手写泛型基类 `AgentGeneric[T]`——msgs 列表 + 工具注册表 + `_iter` 循环（completion→tool_calls 并发执行→`get_result` 判终止），max_iters 默认 40。工具结果超长统一替换为"too large, try another approach"（MAX_TOOL_CALL_RESULT_LENGTH）。
- **工具文档单源**：工具的 docstring **从提示词 YAML 生成**（`_tools_api`：YAML 里有 tools 段则拼 summary/params/returns 成 docstring，代码有 docstring 且 YAML 也有则报错——**提示词与代码谁是唯一事实源被强制裁决**）。
- **多模型三用法**（一个机制三种价值）：MODEL_MAP 每类 agent 配模型列表——①回退（completion 失败 `model_idx += 1` 换下一个模型重试，agent.py:342-346）；②**竞速**（`run_default_batch`：每模型起一个 agent 并行跑，带 stop_condition，一个出结果其余取消——PoV/补丁这类"多解问题"用模型多样性对冲单模型失败，agent.py:410-435）；③按 agent 角色配不同模型（分类器只配 GPT-4.1，注释"classifiers only work with openai"）。
- **上下文压缩=诚实截断**：超窗时保留头 2 条（system+user）+ 尾 1/3，中间插占位消息 `[some messages were removed due to context size constraints]`，并保证从 assistant 边界开始（agent.py:301-314；TODO 自问"能不能真摘要而不是截断"——冠军也没做，值得注意）。
- **agent 可序列化**：jsonpickle+gzip 序列化整个 agent 状态（含 msgs），`fork()` 克隆、日志里嵌压缩态——**agent 状态是一等公民，可暂停/恢复/克隆**；成本与工具错误沿 parent 链向上累计（子 agent 花费自动归账到父）。
- **MsgHistoryAgent**：拿别人的历史消息换一套新工具继续跑——"同一上下文、不同工具面"的复用模式。
- 防御性细节：o3-mini 会生成无名 kwargs（`kwargs.pop('')`，:243 注释点名模型）；工具不存在/JSON 坏时回注 ERROR 消息并附可用工具清单；AgentAction 支持 stop/append/rewind（rewind 未实现）。
- reasoning_effort 按模型名自动映射（o4/o3-mini→high、claude-thinking→low/medium/high）。

### 4.2 提示词体系（prompts/default.yaml，关键段亲读）

单 YAML 双层结构：`agents:`（18 个 agent 的 system[Jinja2]/user/tools 覆盖）+ `tools:`（24 个工具的 summary/params/returns 文档）+ `custom:`（共享片段：prompt_intro/vuln_location_advice/c_vulnerability_descriptions/jazzer_sanitizer 文档）。PromptManager 按模型绑定（`bind(*类名继承链, kwargs={"agent": self})`——**提示词按 agent 继承链与模型双维度解析**）。

关键 agent 提示词（亲读）：
- **CRSPovProducerAgent**（255-380）："产出**并测试** PoV"；流程钉死：先 `source_questions` 理解漏洞→拿 `get_harness_input_encoder`（**明令"不许假设你懂 harness 输入格式"**）→写 python 产 input.bin→失败则 `reachability`+`debug_pov` 定位；python 在隔离环境跑、"影响 fuzzer 的唯一途径是产出 input.bin"（能力边界写进 important）；**close_pov 机制**：若有已验证接近目标函数的 PoV，注入为起点（"把它改造成触发漏洞"）——把 frontier/coverage 的"接近"资产喂给 PoV agent；无 close_pov 则强制规则"不准没试就终止"。其 `debug_pov` 工具本身就是**一个动态调试 agent**（"AI 助手运行你的 PoV 并回答关于变量值/代码路径的具体问题"），带使用军规（先问 harness 行为再问深层代码、禁问"为什么不行"这类模糊问题、附 additional_info 传上下文）。
- **PatcherAgent**（956-1040）：补丁军规——"禁用 deny/allow 字符串清单过滤，必须修根因"；**后门豁免条款**："预期功能不包括后门——补的若是后门，应当整个移除"（AIxCC 特有：目标里埋的故意漏洞可以激进删）；"只许改 C/C++/Java 源文件、禁改 harness"；补丁将被测试套件+已知 PoV 双重验证；先列多策略再择优。
- **QueryJoernAgent**：给另一个 agent 生成 Joern 静态分析查询的**助手 agent**（"他们无法与你交互，问题自答；缺关键信息就返回错误让他们重问"；"完成前必须真的跑一遍查询"）——**agent 即工具**的又一形态（source_questions 同理）。
- **BranchFlipperAgent**（1-89）：给定"当前种子到达的函数"与"目标函数"，改造种子到达相邻函数（**分支翻转到新代码** 的 fuzzer 引导）；军规"DO NOT GUESS 常量值——用工具查"；"没验证 query_coverage 就不准声称成功"。

### 4.3 模型配置面（configs/ 亲读）

- `models-anthropic.toml`：15 个 agent 类各配模型（PovProducer=claude-3.7+3.5 回退、Patcher=3.7、分类器=azure/gpt-4.1[只兼容 openai 系]、Triage=3.5、BranchFlipper=3.7…）；13 份分档（best/final/round-3/jun22/jun23[按日期迭代]/weak/very-weak/none/openai-only）——**模型选择是配置文件级实验变量**，决赛配置独立成档。
- 环境默认值：MODEL 默认兜底、LOG_LEVEL=INFO、CACHE_DIR=/tmp、密钥支持 tokens_etc/ 文件或环境变量双通道。

### 4.4 中枢与验证（app.py 结构亲读）

CRS 类按 WorkType 派发后台 worker：patch_vuln（带 stop_condition 的补丁竞速，:343）、process_crash→LLMTriage、process_coverage→Frontier→BranchFlip、launch_fuzzers、launch_ainalysis（**多模型并行全量分析** run_model）、launch_infer（静态）。全量模式 Infer+AInalyze 双源出 VulnReport、Score 阈值过滤后才进 VulnAnalyze——**便宜信号先筛再上贵 agent**。

### 4.5 结果验证与去误报

- PoV：必须真跑（Corpus 试跑→崩溃→Triage agent 确认）；debug_pov/reachability 工具闭环定位失败原因。
- 补丁：测试套件 + 已知 PoV 双重机器验证（提示词明示）；fuzzy_patch 做补丁容错应用。
- 漏洞：多源报告（Infer 静态/AInalyze/Diff）→ Score 阈值 → VulnAnalyze 深析 → **DedupClassifier（LLM 分类器）去重**。
- BranchFlip 产出必须 query_coverage 验证（提示词军规）。

## 5. 值得借鉴的设计与技巧

1. **多模型竞速**（run_default_batch）：每模型一个 agent 并行、先到先得、其余取消——用模型多样性对冲"某模型就是搞不定"的失败模式，且与"回退"共用一套配置格式。**冠军系统对模型不可靠性的核心答案。**
2. **agent 即工具**：debug_pov（动态调试问答）、source_questions（源码问答）、QueryJoern（查询生成）都是完整 agent 被当工具暴露——工具面按"能力"而非"函数"划分。
3. **提示词 YAML 单源**：工具文档、agent 提示、共享片段同文件；代码 docstring 与 YAML 冲突即报错——文档漂移在编译期被拦截。
4. **close_pov 提示机制**：把覆盖 frontier 的"最接近输入"作为起点注入 PoV agent——**模糊测试资产直接变成 agent 上下文**。
5. **agent 序列化/fork**：整个 agent 状态可 gzip 序列化进日志、可克隆重跑——调试与复现的一等支持。
6. **带优先级的 LLM 调度**（priority_completion）：多任务共享模型配额时高优先级先走——竞赛时限下的资源调度。
7. **诚实截断 + 占位消息**的上下文压缩：不装摘要、明说删了消息——比假摘要更可预测。
8. **后门豁免补丁条款**：区分"预期功能的漏洞"与"后门"，后者允许整体移除——竞赛语义进提示词。
9. **模型配置文件化分档**（13 份 TOML 按日期/强度）：模型选型变成可 diff 的实验资产。
10. o3-mini 无名 kwargs 防御、ERROR 回注带可用工具清单等模型怪癖实战处理。

## 6. 局限与改进点

- 归档不再维护；决赛环境假设（大预算、Tailscale/竞赛 API）外复用成本高（README 自警 $1,000/小时）。
- 上下文压缩是真截断（TODO 自认）；无记忆/无跨任务学习。
- 自研微内核意味着生态零复用（对照 buttercup 用 LangGraph、artiphishell 用 agentlib）——但也因此零依赖漂移。
- prompts 单文件 2,684 行的可维护性临界；部分工具/agent 未逐行审计（见第 8 节）。

## 7. 与其他已审计项目的对比

| 维度 | theori 冠军 CRS（本项目） | buttercup | artiphishell |
|---|---|---|---|
| 形态 | **自研 agent 微内核** | LangGraph 单体 | 56 组件动物园 |
| 模型策略 | **多模型竞速+回退+按角色分档** | 默认+回退链 | 逐 agent 直配 |
| fuzzer 引导 | BranchFlip agent+close_pov | LLM 写种子 | **LLM 插桩（IJON）** |
| PoV 支持 | **debug_pov 调试 agent 即工具** | QE 机器 pass | povguy 确定性 |
| 补丁验证 | 测试套件+PoV 双验+后门豁免条款 | 三重机器闸 | 8 pass |
| 上下文 | 诚实截断 | 全量进提示 | 全量进提示 |
| 成本治理 | 优先级调度+序列化审计+分档配置 | 预算设置 | 预算小睡 |

三个 AIxCC 系统恰好构成谱系：**theori=微内核+模型竞速（冠军答案）、buttercup=图状态机+反思路由、artiphishell=分布式数据流+LLM 插桩**。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `crs/agents/agent.py` | ✅ 亲读全文 | 512 行微内核 |
| `prompts/default.yaml` | ✅ 亲读关键段 | BranchFlipper/PovProducer(全文)/Patcher(系统)/QueryJoern + tools/custom 清单 |
| `configs/models-anthropic.toml` | ✅ 亲读 | 15 agent 模型映射 |
| `docs/crs-architecture.md` | ✅ 亲读 | 全流程图 |
| `crs/app/app.py` | ✅ 部分 | 类/worker 结构（2022 行） |
| `crs/agents/`（triage/vuln_analyzer/diff_analyzer/pov_producer 等 17 个） | ⬜ 部分 | 职责经架构图+提示词确认 |
| `crs/modules/`（search_code/debugger/python_sandbox 等 13 个） | ⬜ | 工具后端，清单登记 |
| `src/*.rs` `crs/common/` | ⬜ 部分 | llm_api 机制经 agent.py 调用面亲读 |

## 9. 结论

**Theori 冠军 CRS 的核心实现思路是：用一个 512 行的自研 agent 微内核（提示词 YAML 单源、agent 可序列化、成本沿父链归账）驱动"静态双源分析→评分过滤→深度分析→LLM 去重→PoV 产出（close_pov 起点注入+debug_pov 调试 agent 即工具）→补丁（测试+PoV 双验）"的数据流，模型不可靠性用三招对冲——按角色分档配模型、失败回退、以及最重要的多模型竞速（每模型一个 agent 并行、先到先得）；模糊测试侧用 BranchFlip agent 与覆盖 frontier 资产反哺种子。** 它是三个 AIxCC 系统里最"少即是多"的：零框架依赖却把模型多样性当一等武器——这是决赛冠军对"LLM 不可靠怎么办"的最终回答。

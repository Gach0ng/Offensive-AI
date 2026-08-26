# trailofbits/buttercup 逐行代码审计

> 审计对象：Buttercup —— Trail of Bits 为 DARPA AIxCC 开发的 Cyber Reasoning System（决赛 CRS）：AI 辅助模糊测试发现漏洞 + LangGraph 多代理补丁团队修复漏洞。
>
> 审计方法注记：仓库约 76k 行 Python（多组件 monorepo）。核心链（patcher 服务/Leader 图/状态模型/反思路由器/根因代理/种子生成提示/LLM 清单/调度器结构）亲读；fuzzer 内核、program-model、competition-server 等外围组件按结构登记。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/trailofbits/buttercup |
| 本地路径 | `repos/agents/buttercup/` |
| 审计基线 commit | `8da7be9efcb3d857bbba236b322249b9a0c2843b`（2026-08-10，AIxCC 决赛级维护中） |
| 语言 / 规模 | Python 多组件 monorepo，约 76,700 行（orchestrator 27k/patcher 11k/common/fuzzer/seed-gen/program-model/…） |
| Landscape 定位 | 类型：AIxCC CRS（aixcc 组，但登记于 agents）/ Stars：约 1k+ / 一句话：oss-fuzz 模糊测试发现漏洞 → LangGraph 多代理写补丁 → 验证后提交竞赛 API 的全自动 CRS |
| License | MIT（头部 SPDX） |
| 关联论文 | 无（竞赛系统） |
| 审计日期 / 人 | 2026-08-24 初审 / 2026-08-26 深度补读（context_retriever 1378 + swe 840 + qe 586 全文）/ ZCode |

## 1. 项目解决什么问题

- **目标场景**：DARPA AIxCC 竞赛任务——对 C/Java 开源项目（OSS-Fuzz 兼容）**全 autonomously 找漏洞（PoV）并写补丁**，经竞赛 API 提交评分。
- **输入输出**：输入 challenge 项目（含 fuzzing harness）；输出 PoV（崩溃输入）与 patch（补丁+证明不破坏测试）。
- **差异化定位**：十个已审项目中的**第一个"模糊测试+修复"CRS 形态**——LLM 不直接攻击目标，而是①写种子函数引导 fuzzer、②分析崩溃找根因、③写补丁并用**确定性验证**（build + PoV 不再崩 + 测试全过）闭环。工程质量是 Trail of Bits 级（可靠队列/遥测/多 provider 回退/预算控制）。

## 2. 架构总览

```
orchestrator（竞赛 API 客户端[生成代码] + scheduler/submissions.py 提交状态机）
   ▲ PoV/patch 提交          │ Redis ReliableQueue（CONFIRMED_VULNERABILITIES → PATCHES）
   │                         ▼
fuzzer/fuzzer_runner ──崩溃──▶ 去重/确认 ──▶ patcher（服务循环：serve_loop 弹队列）
（oss-fuzz 战役，                                │ 每个漏洞起一个 LangGraph 补丁团队
 AI/ML 辅助）                                    ▼
                                    PatcherLeaderAgent（StateGraph 11 节点）
   seed-gen（LLM 写 def gen_test()->bytes 引导种子；探索/漏洞发现提示；沙箱执行）
   program-model（代码结构语义分析）      litellm（多 provider 封装）
   common（ChallengeTask/ClusterFuzz 解析/队列/遥测）   Langfuse + OpenTelemetry 全链路观测
```

- **编排方式**：**LangGraph StateGraph 状态机**（patcher/agents/leader.py:40-77 亲读）：INPUT_PROCESSING(入口) → FIND_TESTS / INITIAL_CODE_SNIPPET_REQUESTS → ROOT_CAUSE_ANALYSIS → PATCH_STRATEGY → CREATE_PATCH → BUILD_PATCH → RUN_POV → RUN_TESTS → **REFLECTION（路由回任意上游）**；`recursion_limit=200`、`remaining_steps=25` 双保险。
- **LLM 层**：ButtercupLLM 枚举 20+ 模型（Azure/OpenAI GPT-4o→5.5、Claude 3.7/4/4.5 Sonnet/Haiku、Gemini，common/llm.py:18-39 亲读）；**默认+回退链**模式（GPT-4.1 主 + Claude-4.5-Sonnet + Gemini-Pro fallback，`with_fallbacks`）贯穿各代理；litellm 统一封装；**LLM 预算设置**内建（README 明示成本管理）。
- **执行环境**：Docker 化的 OSS-Fuzz 基建（目标项目容器化构建/运行）；patcher 在沙箱构建 ChallengeTask、跑 PoV 与测试。

## 3. 目录结构逐层解读

```
buttercup/
├── orchestrator/   # 竞赛 API 生成客户端 + scheduler/submissions.py（1813 行提交状态机：
│                   #   PoV/patch 提交尝试计数、ERRORED 重试资格、按 build_output 匹配）
├── patcher/        # ★ LangGraph 多代理补丁（11k 行）：patcher.py 服务循环、agents/
│                   #   leader(图装配) common(状态模型) rootcause swe qe reflection
│                   #   context_retriever(1378 行，含 FindTests/CodeSnippetManager) input_processing
├── seed-gen/       # ★ LLM 种子生成：prompt/(seed_init/seed_explore/vuln_discovery)
│                   #   sandbox/(execute_llm_code/runner/sandbox)
├── fuzzer/ fuzzer_runner/   # OSS-Fuzz 战役管理
├── program-model/  # 代码结构语义分析（供上下文检索）
├── common/         # ChallengeTask、ClusterFuzz 崩溃解析/比较、可靠队列、遥测、LLM 封装
├── litellm/ redis/ competition-server/ deployment/   # 基建
└── .claude/skills/ # ★ 调试 Buttercup/Langfuse 的开发代理技能（dev 体验投入）
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 Patcher 服务层（patcher.py 全文亲读）

- Redis ReliableQueue 消费循环（CONFIRMED_VULNERABILITIES→PATCHES），ack/异常不丢消息；TaskRegistry 检查任务过期/取消即跳过（竞赛时限感知）。
- **多 PoV 聚合**：一个 ConfirmedVulnerability 携带全部同类崩溃，PatchInput 收齐（crash 输入本地化、token、sanitizer、引擎、harness、tracer 栈）。
- dev_mode 下挂 **LangChain SQLiteCache**（同输入零成本复放——调试与回归利器）。

### 4.2 状态模型（agents/common.py 亲读）——本项目最精巧处

- `PatchAttempt`：一次补丁尝试的全生命周期记录（strategy/description/patch_str/patch_review/build 三元组/pov 三元组/tests 三元组/built_challenges 缓存/status 九态枚举 PENDING→SUCCESS/FAILED×N/analysis）。
- **两个自定义 reducer**（LangGraph 状态合并语义）：
  - `add_or_mod_patch`：按 id 原位更新尝试列表，**替换前清理旧尝试的构建目录**（磁盘卫生进状态迁移）；
  - `add_code_snippet`：代码片段集去重——**新片段是已有片段子集则丢、是超集则吞并旧片段**（区间包含关系的集合收敛，防上下文膨胀）。
- `ExecutionInfo`：各节点尝试计数 + 反思决策/指引 + prev_node——循环检测的数据基础。
- **成功判据是纯机器的**：`get_successful_patch() = build_succeeded && pov_fixed && tests_passed`（common.py:248-257）——LLM 说"修好了"不算数。

### 4.3 六代理团队

- **RootCauseAgent**（亲读装配段）："PatchGen-LLM，端到端安全补丁流水线的自主组件"系统提示；GPT-4.1(temp=1, max_tokens=20000)+双回退；带 `understand_code_snippet` 等工具按需索取代码。
- **ContextRetrieverAgent**（1378 行全文亲读）——FindTests + 初始片段 + 按需检索三节点：
  - **双层 LLM 经济**：片段检索 ReAct/重复判定/初始请求/相关性过滤全用 GPT-4.1-mini（cheap_llm），找测试用 GPT-4.1；各自挂 [Claude-4.5-Sonnet, Gemini-Pro] 回退阶梯——按代理角色做成本分层。
  - 片段检索 ReAct（ls/grep/get_lines/cat/get_function/get_type/get_callers/get_callees/track_snippet/think 十工具）：系统提示是 SWE-agent 式"没解决别停"+"每次工具调用前必须规划、事后必须反思"，且明确**反工具依赖偏置**（"不要全程只靠函数调用，这会损害你的洞察力"）；`track_snippet` 契约是"记录已验证的代码——不是用来发现或搜索"；**行号请求自动 ±5 行缓冲**（容忍 LLM 小错）；`think` 工具是无操作回声（把推理弹回去并催促调 get_function/track_snippet——thinking scratchpad 做成工具）。
  - **初始上下文两波引导**：第一波**项目感知的栈帧过滤**（跳过 __libc_start_main/__gmon_start__/_start；compiler-rt 帧除非项目就是 llvm-project 否则跳过；glibc 动态库帧除非项目就是 glibc 否则跳过）→ 每栈前 n_initial_stackframes 帧 → 按 (函数,文件) 分组去重行号 → 生成自然语言请求并行检索；第二波 cheap-LLM 从"栈+已得片段"补充请求，提示词是**极简主义负面清单**（只准要"漏洞确切发生点/确切失败的安全检查/确切被破坏的变量"，明文禁止辅助函数/调用方/背景/程序流代码），先 1-10 打相关度再只输出 essentials 的 `<request>`。
  - **片段级去重闸**：每次检索前先过 `<is_satisfied>` 判定（四准则：精确包含/等价或超集/完全可见/"要求全部版本时部分满足不算"），解析异常偏向"未满足"（宁可重查）；检索后每个片段再过并行 `<is_relevant>` 过滤（"不确定视为相关"）。retrieve_context 完成后 `goto=state.prev_node`——**返回调用方路由**，谁要的上下文还给谁。
  - **FindTests 三级查找**：oss-fuzz `projects/<name>/test.sh` 存在即用 → **Redis custom_test_map 哈希（task_id→指令，发现一次跨 run 永久复用——机构记忆）** → 找测试代理。代理带**自验证工具 `test_instructions`**：在干净副本上实际执行构建+测试指令，**双重验证**（进程成功 且 LLM 裁判 `<are_valid>`，输出从**头部截断保留末尾**——测试结果通常在最后几行），失败则工具返回"你不能停在这，必须修好再调我"；外层最多 10 轮、每轮追加"你还没成功调过 test_instructions，请更努力"的加压 HumanMessage；整体 30 分钟墙钟超时（future.result(timeout)）优雅降级（无测试继续跑）。`sh` 工具把命令写成临时 bash 文件 docker 挂载执行（文件挂载而非字符串注入）。
- **SWEAgent**（840 行全文亲读）——PATCH_STRATEGY 与 CREATE_PATCH 两节点：
  - **AI-prefill 强制格式**：两个提示模板都以 `("ai", "<patch_planning>")` / `("ai", "<patch_development_process>")` 预填助手消息开头——与 vulnhuntr 的 JSON prefill 同一技巧的 XML 版，迫使模型在预期标签内续写。
  - 策略提示（ReAct，带 understand_code_snippet 工具）：强制列 2-4 个备选方案带 pros/cons、"优先最简但可靠的方案（例如能拿到引入该漏洞的补丁就直接 revert）"、**只出策略不出 diff**；`<request_information>` 索取上下文协议（解析后经 reflection 路由回 context_retriever）。
  - 补丁提示：old_code/new_code 各带**前后至少 5 行上下文锚**；只准改 `<can_patch>true</can_patch>` 片段；禁止 TODO/占位符；"只用你确认存在于代码库的代码"。重试提示仅在**上次部分成功**时注入（description+patch+status+failure_category+failure_analysis 五元组，"不要照抄上个补丁"）。
  - **物化管道**（LLM 文本→可应用 diff）：XML 解析（patch 块→file_path/identifier+old/new 对）→ CodeSnippetKey 模糊解析（先精确 identifier 匹配，再 difflib.SequenceMatcher 对路径相似度≥0.8）→ 双重包含校验（片段在文件中、old_code 在片段中；TODO 注释承认缺模糊匹配）→ 字符串替换 → **临时文件跑 `git diff --no-index --binary` 生成标准 diff 再改写路径**（git 本身当 diff 引擎）→ 多补丁拼接。CREATION_FAILED / **DUPLICATED（与历史补丁逐字比对显式去重）** 双失败态进反思。
  - 模型阶梯 GPT-4.1(temp=1, 20k)→Claude-4.5→Gemini（ReAct 版逐模型构建再 with_fallbacks）；GraphRecursionError/ValidationError/空消息一律优雅转反思；摘要链失败回退全文。
- **QEAgent**（586 行全文亲读）——**零 LLM 调用的纯确定性验证节点**（"QE"是 AIxCC 角色命名，非智能体）：
  - **sanitizer 并行构建 + 首败即撤**：get_executor_for_config 并行各 sanitizer 构建，任一失败→取消剩余 future + **清理所有已成功构建的挑战目录**（磁盘产物随状态回滚）；**AArch64 豁免**（该架构部分 sanitizer 天然构建失败，放行）；成功目录按 sanitizer 缓存复用给 PoV 阶段。
  - **PoV 变体放大（防过拟合）**：从 CrashDir 按 (pov_token × sanitizer) 拉取崩溃语料库变体（上限 max_pov_variants_per_token_sanitizer，get_remote=True 拉远端），**原始 PoV 移到队首优先测**——补丁必须扛住同 token 的变体崩溃。
  - run_pov：并行执行、**任一崩溃即短路失败**；墙钟预算带 run_once 细则（超时但已有≥1 个 PoV 成功跑过→乐观收尾继续）；ChallengeTaskError 一律按 did_crash=True 保守处理（基建故障≠已修复）；**一个 PoV 都没跑成→路由回 ROOT_CAUSE_ANALYSIS 而非反思**（根因可能本身就错）。
  - run_tests：测试指令以 /tmp/test.sh 挂载进 docker 在干净副本执行；**无测试指令时 tests_passed=True（"直接接受补丁"——文档化的宽松闸）**。
- **ReflectionAgent**（亲读提示词全文+装配+解析）——**系统的路由大脑**：
  - 提示词定位"安全聚焦的反思引擎，任务是分析补丁为何失败并决定下一步由谁接手"；**第一分析步骤就是 Loop Detection**："数每个组件近期被调次数、同一失败类型 ≥3 次=循环风险、组件间振荡无进展——检测到循环必须换组件"（防死循环写进第一条）；
  - 12 步分析清单（失败上下文摘要/失败分类/部分成功识别/跨尝试模式…）+ `<analysis_breakdown>` 思考区 + `<reflection_result>` 结构化输出（decision+result）；
  - **组件路由表**（亲读）：四个去向各带"何时选我"与"给指引的三条模板"（CREATE_PATCH→"指定改哪个片段怎么改"；ROOT_CAUSE→"识别代码模式、跨函数关系"；CONTEXT_RETRIEVER→"给出确切文件/函数与检索模式"；PATCH_STRATEGY→"列安全机制与改动范围"）——**反思输出是给下游代理的作战指令**；
  - 解析器容错（缺闭合标签自动补）；SUCCESS 状态短路不再反思。
- **InputProcessingAgent**：入口节点，PoV/栈信息预处理。

### 4.4 提示词与配置要点

- 反思提示（reflection.py:47-215 亲读）：步骤化分析强制、循环检测优先、组件路由说明内嵌；ROOT_CAUSE 系统/用户消息分层 + MessagesPlaceholder（多轮工具对话）。
- **seed-gen 提示**（prompt/seed_init.py 亲读）："专家安全工程师经 harness 模糊测试"人设，**让 LLM 写 N 个 `def gen_test() -> bytes` 的确定性 Python 函数**作引导种子（FTP 示例：USER/PASS 命令编码），一个 markdown 块交付；另有 seed_explore/vuln_discovery 变体与 sandbox/execute_llm_code（LLM 代码在沙箱执行验证）。
- 默认模型矩阵：反思/根因=GPT-4.1 主 + Claude-4.5-Sonnet + Gemini-Pro 回退；temp=1/max_tokens=20000（根因）；recursion_limit=200/remaining_steps=25。
- 可观测性：Langfuse callbacks 挂链（tags 带 task_id/internal_patch_id）+ OpenTelemetry span（crs_action_category=PATCH_GENERATION、gen_ai.request.model）——每个补丁全程可追溯；.claude/skills 提供 debug-buttercup/langfuse 技能给开发代理——**运维与开发体验同级投入**。

### 4.5 结果验证与去误报（CRS 形态的精髓）

- **三重机器闸**：补丁必须构建成功 + **PoV 不再触发崩溃** + 项目测试全过——反射路由器只在机器闸失败时介入归因；LLM 的"成功声明"无权重。
- 尝试历史全量留在状态里供反思做模式识别；DUPLICATED 状态显式去重（同一补丁重复生成算失败类别）。

### 4.6 安全与隔离

- LLM 代码（种子/补丁）在 Docker 沙箱构建执行；竞赛 API 客户端生成代码隔离；密钥经 env/.env（cli_load_dotenv）；预算控制防失控成本。

## 5. 值得借鉴的设计与技巧

1. **LangGraph 状态机 + 反射路由器**：确定性流水线（根因→策略→写补丁→机器验证）+ 一个专门"分析失败并路由回正确上游"的反思代理，其**第一职责是循环检测**（同失败≥3 次必换路）——多代理系统防打转的教科书实现。
2. **成功判据纯机器化**（build+PoV 不崩+测试过）：LLM 全程无权宣布成功。
3. **状态 reducer 语义**：补丁列表原位更新（替换即清理构建产物）、代码片段区间包含收敛（子集丢/超集吞）——上下文与磁盘卫生做进状态迁移层。
4. **策略与实施分离**（PATCH_STRATEGY 只出方案、CREATE_PATCH 落代码）+ 反思指引按组件定制模板。
5. **LLM 写种子引导 fuzzer**（`def gen_test() -> bytes` 函数集）：把语义理解注入模糊测试冷启动。
6. **多 provider 回退链**（GPT→Claude→Gemini）+ 20+ 模型枚举 + 预算控制 + dev 模式 LangChain 缓存零成本复放。
7. **可靠队列服务化**：Redis 队列 + ack + 任务过期感知 + 服务循环——竞赛时限下的工程可靠性。
8. Langfuse+OTel 全链路遥测与 .claude/skills 开发技能——**生产与开发两端的可观测性同权**。
9. **Redis 跨 run 测试指令记忆**（custom_test_map：task_id→指令）：发现一次永久复用——慢资产的一次性发现成本摊销到整个竞赛周期。
10. **PoV 变体放大**：按 token×sanitizer 从崩溃语料库拉变体、原始 PoV 排队首优先——防补丁对单一崩溃过拟合。
11. **AI-prefill XML**（提示模板以 `("ai","<patch_planning>")` 预填助手消息）：vulnhuntr JSON prefill 的 XML 版。
12. **git diff --no-index 当 diff 引擎** + 行号请求 ±5 行缓冲 + 0.8 路径相似度模糊键解析——LLM 文本到可应用 patch 的完整落地管道。
13. **双层 LLM 经济**（mini 干检索/判定、4.1 干重活、QE 零 LLM）——按角色做成本与可靠性分层；`<request_information>` 上下文索取协议让策略代理能主动要代码。

## 6. 局限与改进点

- 上下文策略朴素（整片段集+全尝试历史进提示，无摘要压缩——靠 recursion_limit 截断而非智能裁剪）。
- 复杂度重（76k 行、十余组件、Redis/Docker/竞赛 API 依赖链），脱离 AIxCC 场景复用成本高。
- fuzzer/program-model 组件未逐行审计（见第 8 节）；反思提示的组件路由表是硬编码四选一，扩展新代理需同步多处。
- LLM 集中在 OpenAI 系默认（GPT-4.1），Claude/Gemini 仅回退——模型角色分工不如 strix/pentagi 细。
- 补读发现的宽松点：old_code 与片段的匹配是纯字符串包含（代码内 TODO 承认需模糊匹配）；无测试指令时直接接受补丁；找测试代理 30 分钟超时后无测试继续——三处都是"验证闸在信息缺失时向通过方向倾斜"。

## 7. 与其他已审计项目的对比

| 维度 | buttercup（本项目） | PentestGPT | shannon | vulnhuntr |
|---|---|---|---|---|
| 形态 | **模糊测试+补丁 CRS** | 确定性渗透内核 | 白盒渗透流水线 | LLM SAST |
| 目标 | C/Java 源码漏洞 | CTF 目标 | 运行中 Web 应用 | Python 源码 |
| 编排 | LangGraph 状态图+反思路由 | 确定性循环双接缝 | Temporal DAG | 固定两级循环 |
| 验证 | **build+PoV+测试三重机器闸** | 形式校验+证据摘录 | 五道闸 | 置信度军规 |
| LLM 用途 | 种子/根因/补丁/反思 | 决策+执行 | 分析+利用 | 分析 |
| 修复能力 | **核心能力**（带验证） | 无 | 无（商业版） | 无 |

它是"**防御侧 AI**"首次入列：前九项都在找漏洞，buttercup 找完还要**修好并证明没修坏**——验证哲学从"证明可利用"翻转为"证明已修复"。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `patcher/src/.../patcher.py` | ✅ 亲读全文 | 服务循环 |
| `patcher/src/.../agents/leader.py` | ✅ 亲读全文 | 图装配 |
| `patcher/src/.../agents/common.py` | ✅ 亲读 | 状态模型/reducer/九态枚举（1-260 精读） |
| `patcher/src/.../agents/reflection.py` | ✅ 亲读 | 提示词全文+路由表+解析器 |
| `patcher/src/.../agents/rootcause.py` | ✅ 部分 | 提示词头+装配+工具签名 |
| `patcher/src/.../agents/context_retriever.py` | ✅ 亲读全文 | 1378/1378（补读）：两波初始引导/去重闸/FindTests 三级+自验证工具/双层 LLM 经济 |
| `patcher/src/.../agents/swe.py` | ✅ 亲读全文 | 840/840（补读）：AI-prefill XML/策略-实施分离/物化管道/DUPLICATED 去重 |
| `patcher/src/.../agents/qe.py` | ✅ 亲读全文 | 586/586（补读）：sanitizer 并行+首败撤/AArch64 豁免/PoV 变体放大/run_once 细则 |
| `patcher/src/.../agents/input_processing.py` | ⬜ 部分 | 结构与职责经 leader/common 调用面亲读确认 |
| `seed-gen/src/.../prompt/seed_init.py` | ✅ 亲读 | 种子生成提示 |
| `common/src/.../llm.py` | ✅ 亲读 | 20+ 模型枚举 |
| `orchestrator/src/.../scheduler/submissions.py` | ✅ 部分 | 提交状态机结构（1813 行） |
| `fuzzer/` `program-model/` `competition-server/` `deployment/` | ⬜ | 按结构登记 |

## 9. 结论

**Buttercup 的核心实现思路是：把"AI 修漏洞"组织成一条确定性流水线加一个反思路由器——oss-fuzz 战役产出的确认漏洞经 Redis 可靠队列进入 LangGraph 补丁团队（上下文检索→根因→策略→写补丁→build/PoV/测试三重机器验证），任何一环失败都交给"以循环检测为第一职责"的反思代理归因并路由回正确上游（带按组件定制的指引模板），成功判据完全机器化（PoV 不再崩溃且测试全过）；LLM 的另一战场是给 fuzzer 写引导种子。** 它是已审项目中唯一的"防御侧 CRS"形态：Trail of Bits 级工程可靠性（可靠队列/多模型回退/预算/全链路遥测）配上"LLM 无权宣布成功"的验证哲学，与 shannon 的"LLM 无权定义漏洞"形成攻防两端的镜像。

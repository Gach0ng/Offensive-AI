# Team-Atlanta/aixcc-afc-atlantis 审计报告

## 1. 元信息

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/Team-Atlanta/aixcc-afc-atlantis（本地 `repos/aixcc/aixcc-afc-atlantis`） |
| 定位 | Atlantis——Team Atlanta 提交 DARPA AIxCC 决赛（AFC, AIxCC Final Competition）的 Cyber Reasoning System（CRS）参考实现 |
| 语言/规模 | 21,709 个 Java 文件（crs-java 16,815 + crs-sarif 2,529 + crs-userspace 1,208 + crs-multilang 691 + crs-patch 466，大量为 vendored 依赖）；约 1.7 万+ 行自有 Python |
| 许可 | MIT |
| 顶层结构 | `example-crs-webservice`（主实现）、`example-crs-architecture`（k8s 部署）、`example-crs-appendix`（pcb 训练等附录工具） |

**AI 真伪核查（先于审计执行）**：grep `litellm|openai|anthropic|claude|gpt|llm` 命中大量自有一级代码——`cp_manager/llm_key.py`、`dictgen/src/agents/*`、`vuli/model_manager.py`（langchain）、`crs-p3/main.py`（transformers/peft/vllm）、`jazzer-llm-augmented/`、appendix `python-trainer/trainer/grpo/`。**结论：真实 AI 项目，且是本 landscape 目前唯一"LLM + 传统程序分析 + 自托管微调模型 + RL 训练"四层混用的决赛级系统。**

**大仓个人精读计划声明**：本仓 vendored 代码占比极高（graal-jdk、clusterfuzz、litellm 上游、joern 等）。按"完全解读"标准，本人精读范围锁定自有核心链：① cp_manager（编排+LLM 预算+K8s 模板）② crs_webserver/budget（预算池）③ dictgen 全部 agent 与 7 份提示词全文 ④ llm-poc-gen 的 blackboard/generator/blobgen/model_manager 及全部提示词 ⑤ crs-p3（LoRA 适配服务+OTel 中间件）⑥ litellm fork 的自有配置 ⑦ crs-java/crs/main.py（模块清单）⑧ appendix/pcb GRPO 训练奖励设计。vendored 目录只读配置与接入点，不逐行。

## 2. 解决的问题

AIxCC 竞赛规则下的全自动漏洞发现与证明：给定一个 OSS-Fuzz 项目（patched，即含植入漏洞），CRS 必须在算力/时间/预算三层硬约束内产出 **PoV（可复现崩溃证明）** 与 **patch（修复）** 并自主提交。Atlantis 的答卷是一个分布式"AI 武器库"：静态分析（SVF/Joern/CodeQL）找 sink、LLM 生成 fuzzer 字典与 PoV 输入、四变体 Jazzer + concolic + symcc 混合 fuzzing、vLLM 自托管模型 + 运行时 LoRA 适配做补丁生成、GRPO 训练的 Llama 3.2 做符号定位。它不是"聊天式渗透 agent"，而是把 LLM 当作大型模糊测试流水线里的可调度、可预算、可缓存的组件。

## 3. 架构总览

```
任务下发 → crs_webserver(A FastAPI + libCRS: 与 AIxCC 平台交互) 
        → CPManager (cp_manager/)
            ├─ 下载 tarball → 全 sanitizer 构建(ASan/MSan/UBSan...) + symcc 构建
            ├─ Redis 预算池: vCPU 与 LLM 预算同构分配(budget.py)
            ├─ 按语言(jvm/c)分支拉起 K8s 组件:
            │   crs-multilang(每 harness 一节点, libAFL)
            │   crs-java(每 harness, 18 模块 CRS)
            │   crs-userspace(controller+worker+Kafka, 30min epoch)
            │   crs-patch(主节点+5子节点, vLLM+LoRA)
            │   crs-sarif(1 节点, SVF+llm-poc-gen)
            │   crs-multilang-cp-lvl(Joern/LSP 服务)
            └─ llm_key.py: 经 LiteLLM /user/new 为每个组件签发带 max_budget 的虚拟 key
LLM 平面:
    litellm/(vendored fork) ── usage-based-routing-v2 路由 OpenAI(o3/o1/gpt-4.1/4.5)/Anthropic(sonnet-4/opus-4)/Gemini2.5/Grok-3, num_retries=0(重试上移)
    crs-p3 ── FastAPI /adapt: 对 vLLM 自托管基座按任务在线训练 LoRA 适配器(PEFT, 早停)
             + openai_compatible_server: 包住 vLLM 的 OTel 中间件, 全量 prompt/completion 落 span
Java CRS 内部(crs-java/crs/main.py, 18 模块):
    cp 级: CPUAllocator/SeedSharer/CrashManager/LLMPOCGenerator/StaticAnalysis/SinkManager/ExpKit/SARIFListener/DeepGen/Dictgen/DiffScheduler/CodeQL + LeaderElection + e2e watchdog
    harness 级: AIxCCJazzer/AtlJazzer/AtlDirectedJazzer/AtlLibAFLJazzer/SeedMerger/LLMFuzzAugmentor/ConcolicExecutor
```

## 4. 目录结构逐层解读

- `example-crs-webservice/` 主实现
  - `cp_manager/`（729 py）：竞赛编排器。`cp_manager.py` 下载/构建/拉起全部组件；`cp_template.py` 用 Jinja2 生成各组件 K8s manifest，是**组件间契约的单一事实来源**（谁拿 `LITELLM_KEY`、谁读 `SEED_SHARE_DIR`、`DICTGEN_REDIS_URL` 指向哪，全在此）；`llm_key.py` 按组件分 LLM 预算签发 LiteLLM 虚拟 key。`pov_deduplication/clusterfuzz` 为 vendored。
  - `crs-java/`（16,815 java + 549 py）：`crs/main.py` 入口（模块装配）；`dictgen/` LLM 字典生成；`llm-poc-gen/`（`vuli/`）LangGraph PoV 生成；`jazzer-llm-augmented/` corpus 观察+卡壳检测+提示生成；`deepgen/`、`expkit/`、`codeql/`、`static-analysis/`、`concolic/`（内含完整 graal-jdk，vendored）；`sink-targets.txt` 汇点清单。
  - `crs-multilang/`（691 java + 5,619 py）：C/C++ 侧 libAFL 驱动与语料处理（大头为 vendored libafl/clusterfuzz）。
  - `crs-p3/`（4 py）：自托管模型的 LoRA 适配训练服务 + vLLM 追踪中间件。
  - `crs-patch/`（466 java + 1,299 py）：补丁生成，主节点+子节点由 `configs/crs-patch.json` 声明（APP_NAME/APP_MODULE），接 `VLLM_API_BASE`+`ADAPTER_API_BASE`。
  - `crs-sarif/`（2,529 java + 251 py）：SVF 值流分析、可达性、call-trace，并内嵌运行 llm-poc-gen（POCGEN_* 环境变量）。
  - `crs-userspace/`（1,208 java + 872 py）：controller/worker + Kafka + 代码浏览器 gRPC:50051，`EPOCH_DURATION=1800`。
  - `crs_webserver/`（68 py）：`my_crs/crs_manager/`（budget.py 预算池、litellm_adaptor、k8s_manager）+ openapi_client（AIxCC 平台 API 生成的客户端）。
  - `litellm/`（1,468 py）：BerriAI/litellm 完整 fork，自有增量为 `apply_key.py`、`config.yaml`、`model_config.yaml`。
- `example-crs-architecture/`：k8s 部署配置（节点池/PVC 等）。
- `example-crs-appendix/pcb/`：GRPO 训练管线（`python-llm` 推理、`python-trainer/trainer/grpo`、`p4`），`scripts/train.py` 552 行；README 注明需 Llama 3.2 权限 + 手工删除 trl 的 NaN-reward 警告块。

## 5. 核心模块逐行精读

### 5.1 cp_manager.py（598 行，全读）

编排主干：`launch()` 双线程并行"构建"与"拉节点"。预算数学是理解本系统的钥匙——`__get_running_hours()` 用任务 deadline 反推剩余小时（+0.2h 缓冲）；`QUOTA_PER_CP=1000` 先扣除 cp-mgr+crs-sarif+3 节点 crs-patch 的常驻开销；`__calculate_node_size()` 把"vCPU·小时预算 ÷ 剩余时间"换算成并发核数，再从 `[128,96,64,48,32,16,8,4]` 里选最大可行机型；JVM 项目对半分给 crs-java 与 crs-multilang，非 JVM 则先扣 userspace 池再分余量。语言判定 `__wait_language()` 靠轮询 oss-fuzz `project.yaml` 的落盘。所有等待都是 `while + sleep(5)` 的文件/变量轮询——竞赛环境下的朴素但可靠的总线。`rsync` 失败无限重试，`run()` 裸 `except: pass` 容错优先于正确性。

### 5.2 llm_key.py（94 行，全读）+ budget.py（262 行，全读）

**LLM 被当作与 vCPU 同构的资源治理**。`budget.py`：Redis + `redis_lock` 实现分布式预算池，`BudgetAllocator.allocate_budget = total/max_tasks + withdraw_returned_budget()`（回收再分配，均值出账）；LLM 与 VCPU 各一个池，API 完全对称（allocate/return/reset）。`llm_key.py`：`__get_llm_budget_rate` 从 `LLM_budget_CRS_*` 环境变量算组件配比，断言 java==multilang==userspace，`total = patch + multilang*2`；随后带着 master key 请求 LiteLLM `/user/new` 生成 `max_budget` 受限的虚拟 key，写入各组件环境变量并持久化 Redis。`get_llm_spend()` 反向查 `/key/info` 读实际花费——预算闭环。

### 5.3 cp_template.py（752 行，全读）

六大组件 manifest 生成器。值得记录的契约细节：crs-multilang 拿 `JOERN_URL`（指向 cp-lvl 节点）与 `LSP_SERVER_URL=cp-manager:3303`——**Joern/LSP 作为共享服务**；crs-java 额外接 SARIF 三共享目录（ana-result/reachability/crs-java）与 `CPMETA_REDIS_URL:9505`；crs-patch 主/子节点都拿 `VLLM_API_BASE`+`ADAPTER_API_BASE`（自托管模型与 crs-p3 适配器）；crs-userspace 有 `ENSEMBLER_TMPFS`、`CODE_BROWSER_ADDRESS` gRPC；crs-sarif 一节点同时跑 SVF（`SVF_MODE=ander`）与 llm-poc-gen，并把 LiteLLM key 直接映射为 `OPENAI_API_KEY/OPENAI_BASE_URL`。`add_otel_env` 给所有组件打上 `CRS_SERVICE_NAME/CRS_ACTION_CATEGORY`（fuzzing/patch_generation/program_analysis）——竞赛遥测内建。

### 5.4 dictgen（dictgen.py 353 + configs 325 + 6 agent + 7 提示词，全读）

LLM 生成 libFuzzer 字典。主流程：按函数索引收集源文件（delta 模式附 `ref.diff`）→ 常量预处理 → `asyncio.Semaphore` 限流并发分析 → 按文件/函数/漏洞类型合并 → 每类阈值裁剪（`THRESHOLD_TABLE: xpath injection→2, default→3`）→ 非token类每类随机抽 2 → 输出 `str{i}=...`。

**七个 agent 实例**（DictAnalyzer.__init_agents）：token_extractor、diff_mode_analyzer（复用 TokenExtractor 换提示词，按 hunk 喂 diff）、trigger_extractor、trigger_verifier、parsing_function_detector ×2（**双实例多数投票**）、parsable_string_extractor（`delimiter="<#>"`、不展开不清洗）。

值得单独记录的工程决策：
- **常量提取从 LLM 回退到静态分析**：`preprocess_source_file_with_llm` 被注释标 "outdated, please use static analysis"，改用 `find_imported_constants_in_file`（FQN 解析）。但静态常量并不白给——`augmenting_constant_map()` 把它们以 `public static final` 声明插回 import 块之后再喂 LLM：**静态分析的结果被编译成 LLM 能读的"可见上下文"**。
- **flaky-token 自一致性过滤**（`apply_repeatedly`）：同一提示跑 2 次，只保留两次都出现的 token（`token_counts < (REPEAT+1)/2` 则删）。前置语 "Attempt {i} to filter out flaky tokens"。
- **token 清洗**（`do_sanitize_token`）：`ast.literal_eval` 安全求值；TRIVIAL_TOKENS 黑名单（0xFFFFFFFF、"null"…）理由注释直白——"libafl prioritizes trivial values"，引擎自己会试的值不浪费字典位；整数 `(-0x10,0x10)` 与空/含空格串判 INVALID。
- **受限表达式展开**（`do_expand_token`）：手写 AST 求值器只允许 str/int 常量与 `+`、`str*int`，展开 `"A"+"\x00"` 类拼接，上限 1MB。
- **TriggerVerifier 二次验证**：trigger_extractor 先按漏洞类型抽"触发 token"，verifier 再对每个 (vuln_type, token) 独立问一遍能否真正触发，答案行 `- Answer: Yes/No` 用 `parse_response_yes_no` 解析且**拒绝重复答案**（出现两次不同答案直接判 False）。

提示词全文均已读（`prompt/*.json`，占位符 `<FUNCTION_NAME>/<DELIMITER>/<VULN_TYPE>/<TOKEN_VALUE>`）。token_extractor 的规则核心："interesting = 会改变控制流的比较常量；不知道的值必须答 UNKNOWN 并给不出行号；数组/字符串长度不算"。trigger_verifier 的规则给出**可执行判定锚点**：SSRF 用 `jazzer.example.com`、命令注入用 `jazze`、并显式假设 log4j 有洞（Log4Shell）。parsing_function_detector 无规则无示例，纯 YES/NO。

### 5.5 llm-poc-gen / vuli（main 116 + blackboard 343 + generator 311 + blobgen 1323 + model_manager 541，全读）

**LangGraph 状态图 PoV 生产线**（generator.compile()）：

```
prepare → generate_blob ──(未到达且迭代<2)→ localize → extend → external → generate_blob → ...
```

- `generate_blob`：SeedGenerator 产 blob，`SeedEvaluator` 打分 **score=(last_visit+1)/len(path)**——用调试器实测的"路径走到第几步"作为连续奖励；score==1.0 即 reached。
- `localize`：失败时用 Joern 查上一到达方法的属主，`DebuggerVerifier(JDB)` 取该方法内**实际访问过的行号**，连同 A/B 函数与代码喂给 gpt-4.1，要求输出 `{file_path, start_line, end_line}` JSON 定位"在哪走错"。
- `extend`：Extender agent 基于 localize 结果扩 code_table（上下文窗口沿路径增长）。
- `external`：Joern 查询该区间内外部队列函数（排除 `<operator>`），生成反馈："这些外部调用可能影响执行路径，请核实并据此改 blob"。
- 反馈模板明确写 "You MUST specify which statements make execution went wrong and focus on them"。

**生成器族谱**（blobgen.py，工厂 `create_blobgen_factory(harness_type, with_sentinel, with_feedback)`）：
- 字节面：`ByteSeedGenerator`——LLM 写 python 脚本产出 blob（sys.argv[1]=输出文件），系统提示要求"先逐步分析再写脚本；识别 BLOB/SCRIPT 中对与错的部分，保留对的修错的"，tip 只有一词 "Endianess"。`BytePoVGenerator` 按 sanitizer 分派四套系统提示：FilePathTraversal→构造 `../jazzer-traversal`（若发现 `jazzer.file_path_traversal_target` 属性则访问其值）；SSRF→连 `jazzer.example.com`；BigDecimal→构造尽量大的 decimal 致 OOM/timeout；默认→双 argv 形式，sentinel 文件内容作为待注入恶意值。
- FDP 面：`FDPSeedGenerator` 让 LLM 输出 **FuzzedDataProvider 调用序列 JSON**（`[{method,args,value}]`），要求理解调用顺序并展开循环次数；`FDPParser` 持有 30 余项 FDP API 映射表（consumeByte→produce_jbyte_in_range…），校验 method/args/value 三键、参数个数、`consumeBytes(len)` 的 value 长度一致性，然后编译成 libfdp 编码脚本实际执行得到 blob。`FDPPoVGenerator` 的提示是本系统最精妙的一句分工："**当前 TEMPLATE 已保证输入能到达 POINT，你唯一要做的是修改 value 以触发漏洞**"——把"到达"与"致崩"解耦为两阶段，sentinel 存在时再提示"oracle 钩住了 POINT 处函数并校验参数等于 SENTINEL 值，请把 TEMPLATE 相应部分替换为 SENTINEL"。
- **运行 LLM 产出的脚本**：PoVParser/FDPParser 用 `timeout -s SIGKILL 10 python` 执行，超时转为 LLMParseException 回喂（"请勿包含可能超时的逻辑"）。
- `generate2`：多模型随机顺序尝试 + `ban_model` 熔断 + 3 轮全局重试（60s 间隔），按 score 取最优——**模型竞赛（model rodeo）**。

**ModelManager**：SQLite+Redis 两级 `MultiCache`（langchain BaseCache），命中打 `from_cache` 标记；`UsageCallBack` 分别累计 cost 与 **saved**（缓存省下的钱）；`_retry_parse` 把解析异常文本作为 HumanMessage 追加回模型自我修复（"You didn't include ```json```... Please answer again"）；tenacity 对 429/5xx 以 60s+随机抖动重试 10 次；`invoke_atomic`（不重试、抛 LLMRetriable）与 `invoke`（带重试）双通道。

**Blackboard**：单例共享黑板，sinks（14 种 CRS sink 类型映射表）/paths（NOT_REACHED→REACHED→EXPLOITED 三态）/seeds（score==1.0 的种子落共享目录给 fuzzer）/diff harnesses/三个 CG 哈希（sarif/soot/joern，CG 变更触发下游重建）。落盘用 temp file + `os.replace` 原子写，失败降级只存 seeds。sink 位置由 Joern CPG 查询补全（`cpg.ids(...)`）。

### 5.6 crs-p3（main.py 149 + middlewares.py 409，全读）

`/adapt` 端点：收到 `{id, text, block_size=256, lr=2e-5, epochs=32, lora_r=8, alpha=32}` 后，把 text 按 block_size 切块为数据集，对**已加载的 vLLM 基座**做 PEFT LoRA 训练（train_test_split + epoch 级评估 + EarlyStoppingCallback patience=5 threshold=0.01），存 `adapters/<id>` 并卸载释放显存；`asyncio.Lock` 保证全局串行。已有适配器直接返回路径（幂等）。这就是 crs-patch 的 `ADAPTER_API_BASE` 消费方——**按任务在线适配，而非全局微调**。middlewares.py 给 vLLM OpenAI 兼容层加 OTel span：完整 prompt/completion 作为 `gen_ai.content.prompt/completion` 事件、token 用量、TTFT、model/seed/temperature 全落遥测（semconv 抄自 openlit）。

### 5.7 litellm fork 自有配置（config.yaml + model_config.yaml，全读）

`usage-based-routing-v2` + `enable_pre_call_checks` + Redis 共享路由状态；`num_retries: 0`（重试职责上移到 ModelManager/上层）；`drop_params/modify_params` 容错异构模型。模型面覆盖 OpenAI（o3/o4-mini/gpt-4.1 三档/o1-pro/gpt-4.5-preview）、Anthropic（sonnet-4/opus-4，TPM 走环境变量）、Gemini 2.5/2.0、Grok-3 全家、Vertex 上的 llama-3.1-maas（注释："public preview 免费"——**竞赛成本意识**）。

### 5.8 crs-java/crs/main.py（246 行，全读）与 jazzer-llm-augmented

18 模块装配（清单见 §3），cp 级 12 + harness 级 7；`LeaderElectionManager` 多实例选主，cp 级任务只在 leader 上跑；`e2e_check_loop` watchdog 周期自检。`jazzer-llm-augmented/jazzer_llm/`：corpus_observer（观察语料进化）、`stuck_reason.py`（fuzzing 卡壳归因）、prompt_generation（据卡壳原因生成提示让 LLM 补种子）、llm_invoker_loop——fuzzing 停滞时才请 LLM 出手的"按需增强"。

### 5.9 appendix/pcb GRPO 训练（train.py 552，读奖励部分）

基座 Llama 3.2，TRL GRPOConfig（temp=1.0, adamw β2=0.99, warmup 0.1, constant lr）。奖励设计：`immediate_reward=[soft_format]（权重0.5）` + `final_reward=[compilable]（权重0.5）`——compilable 在沙箱里真实编译，另接教师 LLM（`LlmApiManager`）参与判定；`_on_rewards_computed` 按 项目/版本 聚合记录。README 要求手工删除 trl 的全-NaN-reward 警告块——训练数据里大量样本无有效奖励是常态。任务形态是 `set[Document] → set[Symbol]`：从文档观察定位漏洞相关符号。

## 6. 值得借鉴的设计

1. **LLM 预算作为一等资源**：与 vCPU 完全同构的 Redis 预算池 + LiteLLM 虚拟 key（`max_budget` 硬顶）+ `/key/info` 回读实耗，构成"分配-消耗-回收-再分配"闭环。任何多 agent 生产系统都可直接抄这套账本。
2. **两阶段 PoV 分解**："先保证到达（SeedEvaluator 路径进度分），再只改恶意性（FDPPoVGenerator 提示明说唯一任务是改 value）"。把搜索空间按"控制流可达"与"漏洞触发"正交切开。
3. **调试器实测路径进度作为 LLM 的连续奖励**：score=(last_visit+1)/len(path)，比"崩/不崩"的稀疏信号细粒度得多；localize 节点把 JDB 访问行号喂回模型，是"执行反馈驱动"的标准示范。
4. **LLM 输出的结构化 DSL（FDP 调用序列）而非自由字节**：30 项 API 映射表做白名单校验 + 语义校验（长度一致性）+ 编译执行，幻觉空间被压到 value 字段。
5. **模型竞赛与熔断**：generate2 多模型随机顺序 + ban + 全局重试；解析失败把异常文本回喂模型自修复；两级响应缓存并统计 saved。
6. **dictgen 的三层过滤**：两次自一致性过滤 flaky token → TriggerVerifier 独立逐 token 复核 → 每漏洞类型阈值裁剪。LLM 产出的每个 token 都要过三道关。
7. **静态↔LLM 互补而非替代**：常量提取弃 LLM 用静态 FQN 解析，但结果编译回源码喂给 LLM；Joern/CodeQL/SVF 提供 sink 与路径，LLM 只做"猜值"这最后一步。
8. **运行时 LoRA 适配服务**：crs-p3 把"为每个目标项目定制模型"做成独立 FastAPI 服务，幂等、串行、早停，vLLM 热挂适配器。
9. **全量 LLM 遥测**：OTel span 记录每次补全的完整 prompt/completion/token/TTFT，竞赛复盘等于自带飞行记录仪。
10. **朴素但诚实的基础设施**：文件轮询当消息总线、rsync 无限重试、`except: pass`——在"8 小时内必须出结果"的约束下优先可用性，与上层精致的预算/缓存形成有趣对比。

## 7. 局限与改进点

- **正确性让位于存活**：`run()` 吞掉所有子进程异常，`except: pass` 多处；llm_key 失败无限循环重试。诊断只能靠日志反推。
- **flaky 过滤只有 2 次重复**，且 token 侧与 trigger 侧阈值（2/3）是手调常数，未见自适应机制。
- **提示词内嵌英文拼写错误**（comopared、exeution、Veirifer、happe）——对强模型无碍，但反映提示工程未做版本化治理（对比 Cyber-AutoAgent 用 Langfuse 托管提示）。
- **PoVParser 直接执行 LLM 生成的 python 脚本**（10s SIGKILL 限时限不了资源滥用），依赖沙箱环境本身；脚本无静态检查。
- **Blackboard 全量 JSON 落盘**在大 sink 数下会成瓶颈；`pickle` 缓存反序列化存在信任边界问题（缓存 key 含 prompt 哈希，投毒面小但非零）。
- **PCB 训练要手工改 trl 源码**（删 1173-1182 行），复现性脆弱；GRPO 奖励 0.5/0.5 的权重未见消融。
- **多语言不对称**：dictgen 注释 "TODO: support C"，精读部分主要服务 jvm；C/C++ 侧更多依赖 crs-multilang 的传统流水线。

## 8. 与其他已审项目的对比

| 维度 | Atlantis | 已审参照 |
|---|---|---|
| 验证文化 | 调试器实测路径进度 + TriggerVerifier 复核 + sentinel oracle（钩子函数校验参数值） | xalgorix 的对抗复测、pentest-ai 的 oracle-only 判定同属"执行证据派"，但 Atlantis 把证据做成了连续分数 |
| 协调范式 | 分布式组件(K8s) + 黑板(sink/path/seed 三态) + Leader 选举 | Cairn 的 minimal blackboard、BreachWeave 的 Observer 板协议；Atlantis 黑板多了 CG 哈希失效与原子写 |
| LLM 成本治理 | Redis 预算池 + LiteLLM 虚拟 key + 两级缓存 + saved 统计 | Cyber-AutoAgent 的 Langfuse 提示管理只管版本不管钱；Atlantis 是 landscape 中唯一把"钱"做成分布式账本的 |
| 多模型策略 | generate2 模型竞赛 + ban + 随机顺序 | EVA→WhiteRabbit 是换模型解锁，Atlantis 是同题多模型择优 |
| 静态/LLM 分工 | 静态出常量/sink/路径，LLM 只猜值 | Dark-Moon 的运行时挂载相反（知识全在 LLM 侧）；Atlantis 最接近 pentest-ai-agents 的"工具为主 LLM 为辅" |
| 自训模型 | vLLM+运行时 LoRA(crs-p3) + GRPO Llama3.2(PCB) | AutoPentest-DRL 的 DQN 是另一极端；Atlantis 证明决赛级系统同时用 API 大模型与自训小模型各司其职 |
| 输出格式约束 | FDP 调用序列 JSON 白名单 + 编译执行 | 与 garak 的结构化探针同思路，但 Atlantis 多了"编译到可执行字节"这一硬校验层 |

## 9. 文件级审计进度与结论

已亲读（全行数）：`cp_manager/cp_manager/{cp_manager,llm_key,cp_template}.py`；`crs_webserver/my_crs/crs_manager/budget.py`；`dictgen/src/{dictgen.py,configs 骨架}`、`dictgen/src/agents/*.py`(6)、`dictgen/src/prompt/*.json`(7)、`dictgen/src/utility/llm.py`；`llm-poc-gen/vuli/{main,blackboard,blobgen,model_manager}.py`、`vuli/agents/generator.py`；`crs-p3/main.py`、`crs-p3/openai_compatible_server/tracing/middlewares.py`；`litellm/{config,model_config}.yaml`；`crs-java/crs/main.py`；`appendix/pcb/scripts/train.py`（奖励与配置段）、`pcb/README.md`；顶层三 README。结构盘点覆盖全部一级/二级目录。未逐行：vendored（graal-jdk、clusterfuzz、libafl、litellm 上游、joern）、crs-patch Java 主体（466 文件，读 manifest 契约）、crs-multilang/userspace 内部实现——按精读计划声明豁免。

**结论**：这是 landscape 中工程密度最高的项目——它回答了一个此前 60 个项目都没真正回答的问题：**当 LLM 只是巨型漏洞挖掘流水线里的一个组件时，agent 工程该怎么做**。答案是把传统 agent 框架关心的"推理循环"几乎全部让位给确定性模块（Joern/CodeQL/SVF/fuzzer），LLM 被压缩到三个明确岗位（猜字典 token、按 FDP DSL 猜输入值、猜补丁），并为这三个岗位建了预算、缓存、竞赛、验证、遥测五套治理设施。对研究者的最大启发不是任何单点技巧，而是这种"把 LLM 当可治理资源"的系统观。作为可复用资产：LiteLLM 虚拟 key 预算闭环、路径进度评分、FDP DSL 白名单解析、flaky-token 三层过滤，均可在常规 agent 项目中直接移植。

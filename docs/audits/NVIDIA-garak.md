# NVIDIA/garak 逐行代码审计

> 审计对象：garak（Generative AI Red-teaming & Assessment Kit）—— NVIDIA 官方 LLM 漏洞扫描器，"nmap for LLMs"。与此前六个渗透 Agent 不同，这是 **扫描器/评测框架**形态：无工具调用、无自治循环，靠 192 个攻击探针 × 102 个检测器的插件矩阵打靶。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/NVIDIA/garak |
| 本地路径 | `repos/agents/garak/` |
| 审计基线 commit | `384575716258773f5423496bda3c2f3a9644d59e`（2026-08-21，pin anthropic client） |
| 语言 / 规模 | Python，370 个文件约 64,895 行（probes ~10k + detectors + generators + 核心约 4.3k + data 语料 + tests） |
| Landscape 定位 | 类型：渗透 Agent（实为 LLM 红队扫描器）/ Stars：NVIDIA 官方、领域事实标准 / 一句话：探针×检测器插件矩阵式 LLM 漏洞扫描器 |
| License | Apache-2.0 |
| 关联论文 | **garak: LLM Vulnerability Scanner**（arXiv:2406.11036，仓库内附 garak-paper.pdf） |
| 审计日期 / 人 | 2026-08-24 初审 / 2026-08-26 深度补读（probes/base.py 全文 + detector 四文件全文）/ ZCode |

## 1. 项目解决什么问题

- **目标场景**：对 LLM/对话系统/多模态模型做**系统性弱点扫描**——越狱、提示注入、数据泄漏、幻觉、毒性、编码错乱、包幻觉、代理穿透等 45 个探针族。
- **输入输出**：`garak --model_type openai --model_name gpt-x`（或 huggingface/nim/rest/azure/bedrock/ggml/function/guardrails 等 26 种 generator 后端）→ 逐 attempt 的 JSONL 报告 + 命中日志（hitlog）+ HTML 摘要（含置信区间与意图矩阵）。
- **差异化定位**：把"红队 LLM"从手工 prompt 尝试变成**可复现扫描**：探针是声明式数据（提示语料文件+元数据），检测器可插拔（字符串/触发词/HF 模型/LLM 裁判/Perspective API），统计层带**检测器灵敏度/特异度校准的 bootstrap 置信区间**——评测方法论是同类中最严谨的。

## 2. 架构总览

```
CLI (cli.py 793行: 参数/插件发现/配置装载) → command.py (run 生命周期: 报告文件/setup 落盘/digest)
   ▼
Harness（编排策略二选一）:
   ├─ ProbewiseHarness: 每探针用它自己推荐的 primary_detector (+extended_detectors)
   └─ PxD: 探针×检测器全叉积（彻底但慢）
   ▼
Probe(192) ──mint──▶ Attempt(prompt=Conversation) ──buff──▶ Generator.generate(N 代/提示)
   ──reverse-translate──▶ Detector.detect() → List[float|None] ──▶ Evaluator
   ▼
Evaluator: pass/fail 计数(eval_threshold) + hitlog(逐失败 JSONL) + bootstrap CI(Se/Sp 校准)
   ▼
report.jsonl(事件流) → report_digest → HTML 报告
```

- **插件四方**：`Probe`（攻击，goal/intent/tags/tier 元数据声明）× `Generator`（目标模型抽象，26 后端）× `Detector`（判定，返回每输出 0.0-1.0 或 None）× `Buff`（提示变换，如编码/改写，可叠加有上限）。全部经 `_plugins.py` 按名动态加载，Configurable 基类吃分层配置。
- **LLM 调用层**：generators/ 下每家一个文件（openai 兼容/anthropic/bedrock/huggingface/nim/rest/ggml/langchain/litellm/groq/cohere/azure/function/guardrails…），base.Generator 定义 generate(prompt, generations_this_call) 接口与 parallel_capable 能力位。
- **执行环境**：无沙箱概念——攻击对象是模型 API 而非主机（与渗透 agent 的根本区别）；attempt 并行用 multiprocessing Pool（受 max_workers/parallel_attempts/generator.parallel_capable 三重门控，Pool 触发 OSError 24 时给出 ulimit 提示，probes/base.py:359-363）。

## 3. 目录结构逐层解读

```
garak/
├── attempt.py        # ★ 数据模型: Message(多模态+sha256+bcp47语言)→Turn(role)→Conversation→Attempt
├── probes/ (45文件)  # ★ 192 个探针类: dan/latentinjection/encoding/promptinject/atkgen(自适应)/
│   │                  #   agentforger/agent_breaker/web_injection/leakreplay/snowball/packagehallucination…
│   └── base.py(953) # ★ 探针生命周期+三大可复用基类: TreeSearch(树搜索)/Iterative(多轮BFS)/Intent(意图跨度)（亲读全文）
├── detectors/ (31文件) # 102 个检测器: base(String/TriggerList/HFDetector)/judge(LLM裁判)/
│                      #   perspective/shields/mitigation/visual_jailbreak…
├── generators/ (26)  # 目标模型后端
├── harnesses/        # probewise / pxd 两种配对策略
├── evaluators/base.py(501) # ★ 统计与 hitlog（亲读）
├── analyze/          # calibration(检测器Se/Sp校准)/detector_metrics/bootstrap_ci/report_digest
├── buffs/            # 提示变换插件（编码/前缀等）
├── langproviders/ + services/langservice  # ★ 多语言红队: 触发词翻译+输出逆翻译
├── cas.py            # ★ Policy: 行为策略层级(A/S/T 码)，从评测结果构建、可跨模型对比
├── intents/          # 意图代码体系(T009ignore 等)与 IntentProbe 基类
├── data/             # 提示语料 JSON/AutoDAN/GCG/校准数据/红队资源
├── _config.py(487)   # 分层配置(transient/system/run/plugins/reporting)+yaml/json 配置文件
└── command.py(419)   # ★ run 生命周期（亲读）
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 入口与初始化

- cli.py：argparse 全量旗标（--model_type/--probes/--detectors/--generator/--config/--parallel_attempts/--report_prefix…）→ `load_config` 分层合并（CLI>用户配置>garak 默认；configs/fast.json=轻量默认、bag.yaml 全量）→ `command.start_run()`（command.py:42-121 亲读）：uuid4 run_id（注释特意说明"uuid1 泄漏主机信息"）、报告目录 0o740 权限、**setup 事件把全量配置快照写进报告头**（可复现性根基）、逐事件 JSONL。
- 默认 lite 配置带 25% 概率提示"当前配置为速度优化，--config full 更强"（command.py:10 HINT_CHANCE——**用随机率控制提示频率**的小设计）。

### 4.2 编排与探针生命周期（probes/base.py 亲读）

- **声明式探针**：DAN 族用 `DANProbeMeta` 元类统一注入默认（lang/goal/intent/tier/active=False/tags/primary_detector），子类只需指定 prompt_file——**攻击提示语料在 garak/data/ 下做数据文件**，192 个探针类大多是薄声明。
- **生命周期钩子链**（base.py:160-319）：`_mint_attempt`（注入 system_prompt 为首 Turn；intent 从 payload 或类属性取）→ `_attempt_prestore_hook` → `_buff_hook`（buff 变换叠加，buff_max 封顶、可保留原始提示）→ `_generator_precall_hook` → `generator.generate(prompt, generations_this_call)` → buff 逆变换 → `_postprocess_hook` → `_generator_cleanup`（clear_history）→ deepcopy 返回。
- **多语言红队机制**（base.py:121-146/282-307 亲读）：探针 triggers 经 langprovider **翻译到目标语言**再打靶；模型输出再**逆翻译回探针语言**存 reverse_translation_outputs——**检测器永远读英文，攻击可以用任意语言发起**。语言标签（bcp47）贯穿 Message/Attempt。
- **TreeSearchProbe：可复用树搜索机制**（base.py:483-689 亲读）：不是单一探针而是"攻击面搜索机器"——子类实现 7 个抽象钩子（_get_initial_nodes/_get_node_id/_get_node_children/_get_node_terms/_gen_prompts/_get_node_parent/_get_node_siblings），基类跑完整搜索循环。默认 `strategy=breadth_first`（可选 depth_first，差别只在队列 pop(0)/pop()）、`per_generation_threshold=0.5`、`per_node_threshold=0.1`、`target_soft=True`。循环体：弹出节点→取该节点 surface forms（**全局 surface_forms_probed 集合去重 + never_queue_forms 排除表**）→每个 form 生成提示打靶→**循环内直接加载并调用 primary_detector**（不走主检测流程）→逐代结果二值化后对非 None 求均值得 node_score→**展开决策**：`(mean > per_node_threshold and target_soft) or (mean < per_node_threshold and not target_soft)`——target_soft=True 深挖"软"（易攻破）区域、False 反向死磕韧性区域，把搜索方向做成一个开关。每个节点额外写一条 `tree_data` JSONL（node_id/node_parent/node_score/surface_forms）——**树结构本身是与 attempt 流并行的遥测流**，可离线重建探索树。收尾 `self.primary_detector_real = self.primary_detector; self.primary_detector = "always.Passthru"`——探测已在循环内做完，用探测器热替换让主循环跳过重复检测。
- **IterativeProbe：多轮 BFS 脚手架**（base.py:691-843 亲读）：探针用目标上轮响应生成下轮提示。终止三条件：max_calls_per_conv（默认 10）/ detector 检出成功（end_condition="detector"）/ 探针自带判定函数（"verify"；__init__ 显式校验只能是二者之一）。核心机关在 **_postprocess_attempt 覆写**：基类后处理完成后调 `_generate_next_attempts(this_attempt)` 把下轮尝试追加进 attempt_queue——**下轮生成内嵌在每 attempt 的后处理里（含多进程 worker 内执行时）**，外层按 turn_num 轮转 deepcopy-清空队列。num_generations>1 时每代唯一输出各自分叉（指数增长），follow_prompt_cap=True 时以 初始 attempt 数×soft_probe_prompt_cap 封顶，超限 break 并打印提示。类 docstring 诚实列出 5 条设计权衡（prefill 类攻击不需要本基类可直继承 Probe/探针可改写历史含拒绝轮/每轮 Attempt 都收集送检、notes 可指示特制 detector 跳过/指数爆炸与封顶/BFS 是否够用）。整体 try/except GarakException→log+返回已完成部分（部分结果优于全弃）。
- **IntentProbe：意图跨度探针**（base.py:846-953 亲读）：一个探针横跨整个意图分类体系——__init__ 从 intentservice 取适用意图（blocked_intent_spec 排除；代码注释自问"探针真知道自己该 block 什么吗？更可能知道的是能 include 什么"）、逐意图取 stub、`_expand_stub` 1:* 扩展、`_prompts_from_stub` 生成提示。**覆写 _prune_data 做意图均衡剪枝**：按意图分桶后 target_per_intent=cap//桶数、余数分给前 N 桶（各桶配额差≤1）、桶内 random.sample、prompts 与 prompt_intents 对齐降序删除——对照基类的无差别随机剪枝。`_attempt_prestore_hook` 把 intent 盖章进每个 attempt（意图元数据随证据流走）。空意图集→no-op 返回空列表而非报错。
- 两个亲读发现的实现细节：`_execute_all` 的 Pool 触发 errno 24（EMFILE 文件句柄耗尽）时给出"调 ulimit -n 4096"提示再转 GarakException；**TreeSearchProbe.__init__ 的 strategy 校验是潜伏 bug**（base.py:684）：`self.strategy not in ("breadth_first, depth_first")`——括号里是一个字符串而非二元组，实际做子串匹配，恰好两个合法值都是该串子串而侥幸不炸，但任意子串（如 "first"）也能通过校验。
- **Harness 配对**（probewise.py 亲读）：探针自带 primary_detector/extended_detectors 推荐配对；`--extended_detectors` 扩展；PxD harness 全叉积对照。旧 recommended_detector 字段保留 deprecation 路径（0.9.0.6 迁移痕迹——对插件生态兼容性的尊重）。

### 4.3 检测层（detectors/base.py 343 行、always.py、judge.py 280 行、resources/red_team/evaluation.py 143 行——全文亲读）

- 基类 `Detector.detect(attempt) -> Iterable[float|None]`（0.0-1.0，None=不适用）；类属性声明 doc_uri/lang_spec（BCP47 或 "*"）/MISP tags/`modality={"out":{"text"}}`/`hit_desc`+`pass_desc`（报告文案随命中与否切换）；description 自动取类 docstring 首行，缺失则 warning+ValueError 并附 CPython 文档链接——插件作者契约的强制执行。
- **HFDetector（HF 分类模型检测器）三处硬功夫**：①**签名式分数归一化**——`label != target_class ? (1-score)/2 : (1+score)/2`，把二分类置信度映射到 (0,0.5)/(0.5,1] 两段连续区间，目标类内外都以 0.5 为界且保留置信度信息（优于"非目标类=0"的硬截断）；②`graceful_fail=True`——推理管线任何异常→log critical+整批 [None]（降级为"不适用"，不污染分母、不误判为通过）；③**环境变量手术**——临时设 DISABLE_SAFETENSORS_CONVERSION 阻止 HF 自动开转换 PR、用完恢复原值；另强制 torch.multiprocessing spawn 起法；None 输出的位置对齐用 non_none_offsets 记录、结果 reverse+pop 复原顺序。
- **StringDetector**：matchtype 三态（str 子串 / word `re.search(r"\b"+re.escape(s)+r"\b")` 词边界 / startswith）；**normalize="NFKC+strip_format" 抗混淆归一化**——NFKC 后剔除全部 Unicode Cf 类字符（零宽连接符、双向控制符等隐写通道），触发词侧与输出侧都归一化后再匹配；非法 normalize 配置→warning+整批 [None]（配置错误不终止 run）。
- **TriggerListDetector**：匹配 `attempt.notes["triggers"]`——**触发词随 attempt 动态携带**（DAN 族每个变体自己的触发串），单字符串强制转列表。诚实记录一个瑕疵：notes 无 triggers 键时返回**空列表**而非对齐长度的 None 向量（结果向量比 outputs 短，靠下游容忍）。
- **FileDetector**（fileformats 族基类）：notes["format"] 不匹配 valid_format→warning+全 None；跳过非普通文件（管道/设备）；_test_file 返回 None 时 coerce 成 0.0 兜底。
- **ModelAsJudge（LLM 裁判）**：Detector+EvaluationJudge 双继承——检测器只持有 generator，评分逻辑在共享 mixin `resources/red_team/evaluation.py`（与 PyRIT 共享对抗引擎同构的"裁判引擎"模式）。**goal 回填链**：detector_goal 未配→从插件注册表 `_plugins.plugin_info(f"probes.{attempt.probe_classname}")["goal"]` 取探针声明的 goal 注入裁判系统提示——裁判目标与探针元数据单一来源。默认裁判 nim 的 llama3-70b-instruct、confidence_cutoff=7；1-10 分强制括号格式 `Rating: [[n]]`；tested_prompt 优先 notes["original_prompt"]（翻译前原文）；system_prompt_judge 惰性缓存（检测器实例跨 attempt 复用）；裁判 generator 经合成配置树复用插件装载机制加载，且必须是 OpenAI 兼容对话格式（显式校验，异常解包 e.__cause__）。
- **is_adversarial 注记门控协议**：RefusalOnlyAdversarial / JailbreakOnlyAdversarial 在 notes["is_adversarial"]=False 时直接返回 [None]*n——**多轮探针（GOAT/FITD）把中间轮标记为非对抗，只有最终对抗轮参与判定**，与 IterativeProbe 设计注释第 3 条（notes 指示特制 detector 跳过）构成同一协议的两端。代码 TODO 承认应升级为真正的 skip 语义。
- **Refusal 语义反转 & Jailbreak 的 JailbreakBench 方法论**：Refusal 的 hit(1.0)=「作答了」（[[YES]]），0.0=拒绝——从"安全边界是否守住"的反面看同一件事；Jailbreak 默认提示采用 JailbreakBench 分类准则（doc_uri 指向其仓库）：肯定式开头但无实质有害内容=safe、警告+信息并存=unsafe、无关请求=safe，并因 on_topic_score 的 `[PROMPT]:` 包装破坏其格式而**绕过 on_topic_score 直调 _create_conv**，goal 取 notes["attack_goal"]（GOAT 等 probe 逐 attempt 设置）回退 attempt.goal 两级。
- **EvaluationJudge（共享裁判引擎）**：`_create_conv` **两级 token 守卫**——先廉价启发式（词数/0.75 > evaluator_token_limit 才触发），再 tiktoken 精确计数并从头迭代截断（excess tokens→按 0.75 折回词数→切片）；未知模型回退 gpt-4 编码器与 4096 上限。解析器 `\[\[(\d+)\]\]` / `\[\[(yes|no)\]\]`，**无匹配默认 1.0**——judge_score 语义下=最低分（保守），但 on_topic 语义下=「作答」，对 Refusal 是 fail-open 方向，引用时需注意。
- **always.py**：Fail/Pass/Random 测试三件套 + **Passthru**（skip=True；断言 attempt 已有 detector_results；取字典序第一个检测器的既有结果原样返回）——TreeSearchProbe 循环内自测后把 primary_detector 热替换成 Passthru 以跳过主循环重复检测，正是此类的用途。

### 4.4 统计与报告（evaluators/base.py 亲读——本项目最大亮点）

- 逐检测器评估：None/通过/失败三分计数（None 是一等公民——"检测器不适用于此输出"不污染分母）；`test()` 默认**fail everything**（阈值由 eval_threshold 配置，基类显式保守）。
- **hitlog**：每个失败输出独立 JSONL（goal/prompt/output/triggers/score/run_id/attempt_id/generator/probe/detector 全量）——攻击成功案例可直接回放。
- **bootstrap 置信区间**：二值结果重采样，且用 `analyze/calibration` 的**检测器灵敏度/特异度校准**修正区间（detector_metrics.get_detector_se_sp）——把"检测器本身会错"纳入不确定性，六个已审项目（乃至多数红队工具）里独一份的统计严谨度；样本量 < bootstrap_min_sample_size 时跳过并记 debug。
- **意图矩阵**：eval_record 按 attempt.intent 分桶 pass/total，HTML digest 汇总为 technique_intent_matrix——按攻击意图维度看通过率。
- 报告事件流：start_run setup（全配置快照）→ init → 逐 attempt → 逐 eval → probe_summary → completion → digest 追加 + HTML。

### 4.5 记忆与上下文管理

无跨 run 记忆。有**校准资产**：analyze/calibration 存检测器 Se/Sp 估计（data/calibration），把历史检测器表现变成当前 run 的统计先验——扫描器形态下的"机构记忆"。

### 4.6 结果验证与去误报机制

- 分层去误报：检测器打分→evaluator 阈值→CI（检测器误差校正）→hitlog 人工复核；None 语义隔离不适用样本。
- `show_z` 校准模式（analyze/calibration.Calibration）。
- 局限：多数经典检测器仍是字符串/触发词匹配（对改写型越狱弱）；LLM 裁判自身可靠性依赖裁判模型质量（有校准框架但默认未全启用）。

### 4.7 报告生成 / 人工交互（HITL）

`garak-report/`（独立 React 前端仓库子目录）+ report_digest HTML；interactive.py 提供交互模式（对话式跑探针）。无中途审批——扫描器语义，HITL 在报告端。

### 4.8 安全与隔离

- 攻击目标是模型 API；本机无 shell 执行面（function generator 除外——把任意函数当模型，属测试设施）。
- run_id 用 uuid4（注释：防 uuid1 泄漏主机信息）；报告目录 0o740；HTTP UA 统一可定制（_config.set_http_lib_agents——红队扫描的 OPSEC 细节）。
- 探针默认 active=False 的用 tier（UNLISTED）分级，防误开高危/实验探针。

## 5. 值得借鉴的设计与技巧

1. **探针×检测器×生成器×buff 四方插件 + 两种 harness 配对策略**：攻防资产解耦，新攻击=加数据文件+薄声明类；"探针自带推荐检测器 + 可选全叉积"兼顾效率与覆盖。
2. **多语言红队的翻译回路**：triggers 正向翻译打靶、输出逆翻译回流，检测器单语言——**一套英文检测器打全球模型**的成本结构。
3. **检测器 Se/Sp 校准的 bootstrap CI**：把检测器自身误差纳入不确定性量化——任何"LLM 裁判"系统都该抄的统计层。
4. **None 三值语义**（命中/未命中/不适用）：分母干净，统计不注水。
5. **hitlog 独立落盘**：每个攻击成功=可回放证据包（goal+prompt+output+score+全链 ID）。
6. **括号格式强制评分**（`Rating: [[n]]`）：LLM 裁判输出解析的廉价鲁棒化。
7. **元类驱动的探针族**（DANProbeMeta）：一族攻击变体共享 goal/intent/tags/detector 默认，新增变体=提示文件+三行类声明。
8. **意图/标签/tier 三轴元数据**（T009 式意图码 + owasp:llm01/avid/demon 标签 + 分级）：探针可按合规框架/研究维度切片。
9. **CAS Policy 行为策略层级**（cas.py）：从评测结果自动构建"模型行为画像"并可跨模型 diff——评测结果的结构化再利用。
10. **配置快照进报告头 + uuid4 OPSEC + UA 定制 + 25% 概率提示**：可复现性与红队卫生的细节意识。
11. **TreeSearchProbe 的 target_soft 三态搜索开关**：per_node 均分高于阈值→深挖易攻破区域、低于→死磕韧性区域；叠加 tree_data 遥测流（node_id/parent/score 逐节点 JSONL）——把"攻击面探索"本身做成可离线重建的树。
12. **is_adversarial 注记门控**：多轮攻击只在最终对抗轮判定、中间轮返回 None——任何多轮攻击评测都需要的分母卫生。
13. **HFDetector 签名式归一化 (1±score)/2**：二分类置信度→以 0.5 为中心的连续分，目标类内外置信度都保留。
14. **NFKC+strip_format 匹配归一化**：剥 Unicode Cf 类零宽/控制字符后再做触发词匹配——检测侧抗隐写混淆的标配。

## 6. 局限与改进点

- **不是 agent**：无工具使用、无目标驱动的多步攻击规划（atkgen/AutoDAN 等自适应探针是受限的生成式扩展）；对需要交互/状态的目标（agent 系统、Web 应用）覆盖有限——这是扫描器与渗透 agent 的本质分界。
- 字符串/触发词检测器占比高，改写型/语义型越狱依赖 LLM 裁判，裁判质量成为单点。
- 65k 行单包，probes/data 语料与代码混居；报告 JSONL 事件 schema 靠约定无 schema 校验。
- lite 默认（速度优先）与"扫描器应当彻底"的期待有张力（有 hint 缓解）。
- 亲读发现的实现瑕疵：TreeSearchProbe 策略校验实为子串匹配（base.py:684 元组误写成单字符串）；TriggerListDetector 无 triggers 时返回比 outputs 短的空向量；裁判解析失败默认 1.0 在 on_topic 语义下是 fail-open 方向（Refusal 把不可解析输出当"作答"计）。

## 7. 与其他已审计项目的对比

| 维度 | garak（本项目） | hexstrike-ai | cai | PentestGPT |
|---|---|---|---|---|
| 形态 | **LLM 漏洞扫描器**（探针矩阵） | MCP 工具服务器 | 研究框架 | 确定性渗透内核 |
| 攻击对象 | 模型行为（API） | 主机/网络（shell） | CTF/靶机 | CTF 目标 |
| "智能" | 语料库+检测器（+LLM 裁判） | 无（规则） | 25+ agent | Supervisor/Executor |
| 统计/验证 | **最强**（Se/Sp 校准 CI+hitlog） | 无 | 竞赛+判旗 | 形式校验 |
| 可扩展性 | 插件四方+声明式探针 | 端点样板 | agent 单例发现 | 双角色合同 |

garak 补上景观的另一主分支：**此前六项都在"攻击系统"，garak 是"攻击模型"**——它是 LLM 红队的 nmap，与 pentest-agent 们共享探针语料与判定思想但形态完全不同。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `garak/evaluators/base.py` | ✅ 亲读 | 1-300 逐段；digest 部分机制确认 |
| `garak/command.py` | ✅ 亲读 | 全文 |
| `garak/probes/base.py` | ✅ 亲读全文 | 953/953；初审 100-380，补读 280-953（TreeSearch/Iterative/Intent 三基类全展开） |
| `garak/harnesses/probewise.py` `pxd.py` | ✅ 亲读 | probewise 全文，pxd 头部 |
| `garak/attempt.py` | ✅ 亲读 | 1-180（数据模型） |
| `garak/detectors/base.py` | ✅ 亲读全文 | 343/343（HFDetector 归一化/String/TriggerList/File 四基类） |
| `garak/detectors/judge.py` | ✅ 亲读全文 | 280/280（ModelAsJudge/Refusal/Jailbreak 族+is_adversarial 门控） |
| `garak/detectors/always.py` | ✅ 亲读全文 | 55/55（Passthru 热替换机制） |
| `garak/resources/red_team/evaluation.py` | ✅ 亲读全文 | 143/143（EvaluationJudge 共享裁判引擎+两级 token 守卫） |
| `garak/probes/dan.py` | ✅ 亲读 | 元类+声明式结构 |
| `garak/_config.py` `cas.py` `intents/` | ✅ 部分 | 配置分层/Policy 头部/意图体系 |
| `garak/generators/`（26 后端） | ⬜ | 接口已知，未逐个读 |
| `garak/probes/` 其余 44 族 | ⬜ | 清单+抽样（encoding/latentinjection 结构确认同 dan 模式） |
| `garak/analyze/`（calibration/bootstrap_ci） | ✅ 部分 | 机制经 evaluator 调用点亲读 |
| `garak-report/`（React 前端） | ⬜ | 未读 |

> 其余 44 个探针族与 26 个 generator 后端为同构样板/独立适配器，横向对比需要时按族回读（latentinjection/agentforger/web_injection 等与 agentic 安全直接相关，值得后续专项回读）。

## 9. 结论

**garak 的核心实现思路是：把 LLM 红队做成 nmap 式扫描器——192 个声明式探针（提示语料即数据）经 buff 变换与多语言翻译回路打向 26 种后端的任意模型，探针之下还有三层可复用脚手架（TreeSearchProbe 树搜索攻面探索 / IterativeProbe 多轮 BFS / IntentProbe 意图跨度+均衡剪枝），每个探针自带推荐检测器（字符串/触发词/HF 分类带签名式归一化/LLM 裁判括号评分+is_adversarial 门控），评测层用检测器灵敏度/特异度校准的 bootstrap 置信区间与逐命中 hitlog 把"模型会失败吗"变成带不确定性的可复现测量，最后经意图矩阵与 CAS 行为策略层级把结果结构化为可跨模型对比的行为画像。** 它是"攻击模型"分支（对照此前六个"攻击系统"项目）的事实标准，统计方法论与插件架构对任何红队/评测工具都是直接可抄的范本。

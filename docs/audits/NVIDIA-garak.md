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
| 审计日期 / 人 | 2026-08-24 / ZCode |

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
│   └── base.py(953) # ★ 探针生命周期: mint→buff→generate→逆翻译→报告（亲读）
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
- **TreeProbe/多轮扩展**（base.py:707-801）：多轮探针按 BFS 展开"每代唯一输出→下一轮分叉"，soft_probe_prompt_cap 封顶防指数爆炸（代码注释自问"要不要 DFS？"——诚实的 TODO）。
- **Harness 配对**（probewise.py 亲读）：探针自带 primary_detector/extended_detectors 推荐配对；`--extended_detectors` 扩展；PxD harness 全叉积对照。旧 recommended_detector 字段保留 deprecation 路径（0.9.0.6 迁移痕迹——对插件生态兼容性的尊重）。

### 4.3 检测层（detectors）

- 基类 `Detector.detect(attempt) -> Iterable[float|None]`（0.0-1.0，None=不适用）；`StringDetector`（子串命中）、`TriggerListDetector`（提示内触发词在输出中复现）、`HFDetector`（HF 分类模型批量推理）。
- **ModelAsJudge**（judge.py 亲读）：LLM 裁判——系统提示要求 1-10 分且**强制括号格式** `Rating: [[n]]`（易解析、抗自由文本漂移）；goal 参数化（"10 分=达成了 {goal}"）；默认裁判模型 nim 的 llama3-70b-instruct、confidence_cutoff=7；裁判 generator 必须是 OpenAI 兼容对话格式（显式校验）。
- 命名对应：每个 DAN 变体有自己的检测器（dan.DAN/AntiDAN/STAN/DUDE/DevMode…，metaclass 同款）——**攻击变体与判定特征成对演化**。

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

## 6. 局限与改进点

- **不是 agent**：无工具使用、无目标驱动的多步攻击规划（atkgen/AutoDAN 等自适应探针是受限的生成式扩展）；对需要交互/状态的目标（agent 系统、Web 应用）覆盖有限——这是扫描器与渗透 agent 的本质分界。
- 字符串/触发词检测器占比高，改写型/语义型越狱依赖 LLM 裁判，裁判质量成为单点。
- 65k 行单包，probes/data 语料与代码混居；报告 JSONL 事件 schema 靠约定无 schema 校验。
- lite 默认（速度优先）与"扫描器应当彻底"的期待有张力（有 hint 缓解）。

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
| `garak/probes/base.py` | ✅ 亲读 | 100-380 精读（生命周期/多语言/并行）；TreeProbe 700-801 机制读 |
| `garak/harnesses/probewise.py` `pxd.py` | ✅ 亲读 | probewise 全文，pxd 头部 |
| `garak/attempt.py` | ✅ 亲读 | 1-180（数据模型） |
| `garak/detectors/judge.py` `base.py` `dan.py` | ✅ 部分 | judge 全头部+裁判提示词；base/dan 结构与样例 |
| `garak/probes/dan.py` | ✅ 亲读 | 元类+声明式结构 |
| `garak/_config.py` `cas.py` `intents/` | ✅ 部分 | 配置分层/Policy 头部/意图体系 |
| `garak/generators/`（26 后端） | ⬜ | 接口已知，未逐个读 |
| `garak/probes/` 其余 44 族 | ⬜ | 清单+抽样（encoding/latentinjection 结构确认同 dan 模式） |
| `garak/analyze/`（calibration/bootstrap_ci） | ✅ 部分 | 机制经 evaluator 调用点亲读 |
| `garak-report/`（React 前端） | ⬜ | 未读 |

> 其余 44 个探针族与 26 个 generator 后端为同构样板/独立适配器，横向对比需要时按族回读（latentinjection/agentforger/web_injection 等与 agentic 安全直接相关，值得后续专项回读）。

## 9. 结论

**garak 的核心实现思路是：把 LLM 红队做成 nmap 式扫描器——192 个声明式探针（提示语料即数据）经 buff 变换与多语言翻译回路打向 26 种后端的任意模型，每个探针自带推荐检测器（字符串/触发词/HF 分类/LLM 裁判括号评分），评测层用检测器灵敏度/特异度校准的 bootstrap 置信区间与逐命中 hitlog 把"模型会失败吗"变成带不确定性的可复现测量，最后经意图矩阵与 CAS 行为策略层级把结果结构化为可跨模型对比的行为画像。** 它是"攻击模型"分支（对照此前六个"攻击系统"项目）的事实标准，统计方法论与插件架构对任何红队/评测工具都是直接可抄的范本。

# xoxruns/deadend-cli 逐行代码审计

> 审计对象：Deadend CLI —— 本地优先的自主 Web 渗透 agent（**XBOW 验证基准 ~80%、Kimi K2.5、全程 ~$122**）：**ADaPT 按需分解架构**（论文实现）+ supervisor-subagent 层级 + **五档置信度策略带**（fail<0.2/expand 0.2-0.6/refine 0.6-0.8/validate>0.8）+ judge 裁决 + **反伪造共享块** + 逐题基准日志入库。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/xoxruns/deadend-cli |
| 本地路径 | `repos/agents/deadend-cli/` |
| 审计基线 commit | `34e8371`（Update README.md；pro 版开发中） |
| 语言 / 规模 | Python ~41,284 行（deadend_agent 核心+prompts 子模块+CLI/jsonrpc）+ TS 前端壳 |
| Landscape 定位 | 类型：渗透 Agent / Stars：中高 / 一句话：反馈驱动迭代的本地 Web 渗透 agent（ADaPT+置信度带+judge） |
| License | 见仓库 |
| 关联论文 | ADaPT: As-Needed Decomposition and Planning（架构出处）+ Medium 技术深潜文 |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：标准工具失败后的**自定义利用迭代**——"生成 Python payload→观察响应→迭代精炼直至突破"；完全本地执行（无云依赖零外泄）。
- **AI 真伪核查**：真 AI（core_agent 1,516 行 LLM 引擎+12 个 jinja2 角色提示+ADaPT 递归 agent）。
- **差异化定位**：**置信度显式驱动决策**的四带策略 + ADaPT 论文架构落地 + 反伪造提示词块——把"证据强度→下一步动作"做成连续谱而非二值判断。

## 2. 架构总览

```
CLI/TS 壳（deadend-app 2619）── jsonrpc_server(1290)
   ▼
deadend_agent/
 ├─ agents/architecture.py ★ ADaPTAgent（论文的按需分解：递归 _solve→
 │    事件驱动展开；策略带 expand/refine/fail 由置信度决定）
 ├─ core_agent/core_agent.py(1516)：LLM 引擎（重试/内容策略违规处理/置信度字段
 │    提取失败回退 0.1/工具 schema 反射生成）
 ├─ agents/：supervisor 路由（requester/shell/python_interpreter 三选一决策）
 │    + judge（ACHIEVED/NOT 二判）+ recon/exploit/authenticator/memory/reporter
 ├─ context/context_engine.py(1667)：上下文引擎；rag/ code_indexer/ embedders
 └─ tools/：browser(Playwright 1191+auth 938)/sandbox(Docker/WebAssembly)
deadend_prompts/（子模块）：12 个角色 jinja2 + _shared/ 五共享块
  （_anti_fabrication ★/_confidence_scoring ★/_credentials/_error_recovery/_memory_summary）
  + tools/*.description.jinja2（工具描述即提示词文件）
benchmarks-results/xbow/：逐题 .log 入库（XBEN-001..104）
```

## 3. 核心模块精读（审计主体；41k 行大仓亲读计划：共享提示块+supervisor/judge+架构）

### 3.1 反伪造共享块（_anti_fabrication.jinja2 全文亲读）

- "**绝不生成、猜测或构造**验证 token、flag 或证明"三铁律：只报告**逐字**出现在工具输出中的发现；**必须能引用包含声称证据的确切行**；"证据不逐字存在于输出中，它就不存在"。
- **验证 token 规则**（有期望格式时）：只报逐字匹配格式的 token；**"伪造 token 长什么样（永不报告这些）"的反例清单**——"包含描述漏洞的可读词的 token"、"你'认为'应该存在的 token"、"从部分信息拼装的 token"；报告须附三件套（确切值+逐字行+产出工具）。**"没找到 token 是合法结果——确认的漏洞不意味着 token 存在"**——防"为了交差而造 token"的最后压力释放阀。
- 无格式时退化为证据规则（基线 vs exploit 对照/可演示证明）。
- 该块被 **supervisor 与 judge 双双 include**——反伪造是全角色共享地基。

### 3.2 置信度评分块（_confidence_scoring.jinja2 全文亲读）

- **五档带**：0.8-1.0 ACHIEVED/0.6-0.8 HIGH（需验证）/0.4-0.6 MEDIUM/0.2-0.4 LOW/0.0-0.2 FAILED——README 的策略带（fail<20%/expand 20-60%/refine 60-80%/validate>80%）由此实现。
- **可加调整表**：+0.1/成功工具调用、+0.2/新端点或数据、+0.4/发现漏洞、-0.1/工具失败——**把置信度从直觉变成可审计的算术**（各 agent 统一 rubric）。

### 3.3 supervisor 提示（头部 80 行亲读）——三子代理路由决策表

- requester（自动纠错的快速 HTTP："auto-correct 畸形请求——快但控制弱，**日常请求的默认首选**"）/shell（安全工具+curl 级精细控制+"HTTP 走私/chunked 编码等边缘情况"）/python_interpreter（fuzz/暴力/多变体循环/"需要状态的复杂多步利用"）——每项 **USE FOR/DO NOT USE FOR/PRIORITY 三段式**，边界含工具语义级细节（"requester 会自动改行尾——可接受于简单检查，HTTP 走私要 curl"）。
- "你不亲自执行任务。你路由任务并评估结果。"

### 3.4 judge 提示（头部 50 行亲读）

- 二判（ACHIEVED/NOT ACHIEVED）+ **逐漏洞类型的验证标准**（注入=基线 vs payload 对照；认证绕过=未认证 200+敏感数据；暴露=提取到不可见数据；访问控制=他人数据/提权）——"基于**工具验证的证据**而非假设"；有期望格式时走"格式在输出中→ACHIEVED"的字面判定。

### 3.5 ADaPT 架构与 core_agent（结构+关键行亲读）

- architecture.py：论文 "As-Needed Decomposition"——递归 _solve+**事件驱动展开**（"objective 已解决的信号触发，ADaPT 只对该事件反应"）；策略注释明示 "ADaPT policy (expand / refine / fail)" 三分支。
- core_agent：LLM 重试+**ContentPolicyViolation 专门处理**（_handle_content_policy_violation——对内容策略拒绝的显式应对路径）；置信度字段提取失败→回退实例带 0.1（**解析失败=低置信**，与"失败即保守"家族一致）；工具 schema 从函数签名反射生成。

## 4. 值得借鉴的设计与技巧

1. **反伪造块三铁律+伪造反例清单+无 token 合法性声明**——反幻觉提示词的最完整单块实现（"证据不逐字存在即不存在"+"没找到是合法结果"双闸），可整体移植到任何有验证 token/flag 语义的系统。
2. **置信度算术化**（五档带+可加调整表）——把主观置信变成可审计的加减法，全 agent 统一 rubric。
3. **ADaPT 按需分解的事件驱动展开**——分解只在"未解决"信号时发生（对照静态 DAG 的先全分解后执行）。
4. supervisor 三选一的 USE FOR/DO NOT USE FOR/PRIORITY 决策表（含工具语义边界如 auto-correct vs 精细控制）。
5. 逐题基准日志入库+成本披露（~80% @ $122）；内容策略违规的专门错误路径；解析失败→置信 0.1。

## 5. 局限与改进点

- 41k 行仅提示块+三角色提示+架构结构深读（context_engine 1,667 行未读——上下文核心）；pro 版开发中（README 自述当前版停更）。
- 置信度调整表是提示词层算术（无执行层校验——模型可能不自洽加减）；judge 与 verifier 家族相比无独立重测（xalgorix 式）。
- XBOW ~80% 自报（对照 T3MP3ST 同基准 90.1% 但其含遥测重推导）；模型面窄（Kimi K2.5 为主）。

## 6. 与其他已审计项目的对比

| 维度 | deadend-cli（本项目） | T3MP3ST | xalgorix | HackSynth |
|---|---|---|---|---|
| XBOW | ~80%（$122） | 90.1%（verify-claims） | — | — |
| 分解 | **ADaPT 按需（事件驱动）** | 盲匠主从 | — | — |
| 决策 | **置信度五带+算术 rubric** | COA 矩阵 | 不对称裁决 | 状态机自报 |
| 反伪造 | **共享块三铁律+反例清单** | 引文核验 | 逐类标准 | — |
| 判定 | judge 二判+类型标准 | 独立验证器 | — | 摘要含旗 |

它与 T3MP3ST 同打 XBOW 且都重证据——T3MP3ST 用执行层核验（引文核验+scope 闸），deadend 用提示层反伪造+置信度算术：**同一基准上"执行层治理 vs 提示词治理"的天然对照实验**。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `deadend_prompts/_shared/_anti_fabrication.jinja2` | ✅ 亲读全文 | 反伪造块 |
| `deadend_prompts/_shared/_confidence_scoring.jinja2` | ✅ 亲读全文 | 五档带+调整表 |
| `deadend_prompts/supervisor.instructions.jinja2` | ✅ 亲读头 | 80/~300（三路由决策表） |
| `deadend_prompts/judge.instructions.jinja2` | ✅ 亲读头 | 50/~120（类型标准） |
| `deadend_agent/agents/architecture.py` `core_agent.py` | ✅ 结构+关键行 | ADaPT 策略注释/置信回退/内容策略处理 |
| 其余（context_engine/tools/CLI/jsonrpc/9 角色提示） | ⬜ | 结构登记 |
| `benchmarks-results/` | ✅ 存在确认 | 逐题 log 未逐个读 |

## 8. 结论

**Deadend CLI 的核心实现思路是：以置信度为决策主轴的本地渗透 agent——ADaPT 论文的按需分解（事件驱动展开，未解决才分解）承载 supervisor→requester/shell/python_interpreter 三路由与 judge 二判，全角色共享反伪造块（证据不逐字存在即不存在+伪造反例清单+无 token 合法），置信度经五档带与可加 rubric 算术化并直接映射策略（fail/expand/refine/validate），XBOW ~80%@$122 的成本效率与逐题日志入库。** 它与 T3MP3ST 构成同基准上提示词治理 vs 执行层治理的对照实验；反伪造块与置信度 rubric 是两个整块可移植资产。

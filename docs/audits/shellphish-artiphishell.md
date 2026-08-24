# shellphish/artiphishell 逐行代码审计

> 审计对象：ARTIPHISHELL —— Shellphish（UCSB，CGC/AIxCC 老牌劲旅"binary-blade"队）的 AIxCC AFC 决赛 CRS：56+ 微组件 + 数据流管线编排的巨型模糊测试-分析-补丁系统。
>
> 审计方法注记：约 233k 行 Python 的微服务群。核心 LLM 链（aijon 插桩 agent+提示词全文、agentlib 预算框架、patcherq 主循环/程序员状态机/验证 pass、povguy、pipeline 编排）亲读；56 个组件按职责登记（fuzzing 家族、静态分析家族、补丁家族）。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/shellphish/artiphishell |
| 本地路径 | `repos/aixcc/artiphishell/` |
| 审计基线 commit | `951db005027caccb279aeb20291e7da495d43781`（2025-08-27，AFC 决赛后归档态） |
| 语言 / 规模 | Python 微服务群（56 components + 23 libs + services），约 233k 行（不含测试） |
| Landscape 定位 | 类型：AIxCC CRS / 一句话：LLM 插桩引导 fuzzing + 多根因报告驱动补丁流水线的全分布式 CRS |
| License | 头部 SPDX（见仓库 LICENSE） |
| 关联论文 | IJON（USENIX Sec'20，插桩技术的学术源头，UCSB 自家传承） |
| 审计日期 / 人 | 2026-08-24 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：AIxCC AFC——对 C/C++/Java 开源项目自动发现漏洞（PoV）并产补丁，经 CRS/竞赛 API 提交。
- **差异化定位**（对照 buttercup）：**分布式的组件动物园**而非单体——56 个命名带 "-guy" 的微组件（peek-a-boo/griller/pov-patrol/grammaroomba…）由 YAML 数据流管线编排；LLM 的角色更"深"：不仅写补丁，还**给 fuzzer 插语义覆盖率桩**（IJON 宏）。

## 2. 架构总览

```
pipeline.yaml（pydatatask 数据流 DAG：jq 过滤的仓库联接，c/java × delta/full 四轨，
              preprocessing→targets→main→postprocessing 子管线）
   ▼ 编排起 56 组件容器（Tailscale 游戏网络 + Azure Terraform + OTEL/Signoz 遥测）
┌─ fuzzing 家族: aflplusplus/aflrun/libfuzzer/snapchange/jazzer/nautilus(语法)/syzgrammar(内核)
├─ 静态/分析家族: codeql/semgrep/clang-indexer/clang-instrumentation/antlr4-guy(Java 解析)/
│                function-index-generator/analysis_graph/graphquery/invariant-guy/crash-tracer
├─ ★ aijon（LLM 插桩员）: 按静态分析 POI 在 C/Java 代码插 IJON 宏，给 fuzzer 语义反馈
├─ 漏洞侧: crash_exploration/povguy（PoV 验证）/pov-patrol/dyva/vuln_detect_model
└─ 补丁侧: ★ patcherq（七 agent 补丁团队+程序员状态机+8 道验证 pass）/patchery/patcherg/
           patch-request-retry/patch-validation-testing/submitter
libs/agentlib（共享 agent 框架: AgentWithHistory/全局 LLM 预算/逐模型成本核算/事件转储）
```

- **编排方式**：**声明式数据流**（pipelines/*.yaml）——组件是对数据仓库（jq 过滤的任务/元数据集）操作的节点，非命令式调用链；LLM agent 内部则用 LangChain agent executor。
- **LLM 层**：agentlib 抽象（模型可换，各 agent 类属性 `__LLM_MODEL__` 直配）；litellm 网关；OpenAI/Anthropic/Gemini 三家密钥；**全局预算硬闸**（`set_global_budget_limit(price_in_dollars, exit_on_over_budget=True)`）。

## 3. 目录结构逐层解读

见上文架构图；`aixcc-infra/`（竞赛 API server+schema+备份）、`config/`（final.env 等决赛配置）、`local_run/`（本地复跑）。

## 4. 核心模块逐行精读（审计主体）

### 4.1 aijon——LLM 插桩员（libs/aijon-lib + components/aijon，提示词全文亲读）

- **思想**：把 IJON 论文（UCSB 自家）的"人工插语义覆盖率桩"交给 LLM——静态分析产出 POI（越界访问、整数溢出点），LLM 在代码里**只插入** IJON 宏（IJON_CTX 状态追踪/IJON_CMP 魔数比较/IJON_MAX 进度/IJON_DIST·STRDIST 相似距离），让覆盖率制导的 fuzzer 能"看见"魔法数比较与深层状态，翻过它翻不过的坎。
- **系统提示军规**（aijon.system.j2 全文亲读）："你是手术刀"人设；**只准插桩不准重构**（"不得加条件/函数调用/循环、不得动花括号——绝对不能，会毁掉程序"、**"注解参数里出现 IJON_XXX 以外的函数调用=直接删除浪费，DO NOT DO NOT DO NOT"**、指针解引用前不得注解结构体成员、"条件分支覆盖率已隐式可见，要注的是状态变量"——把插桩的失效模式写成咆哮式禁令）；输出契约 `+ LINE_NUMBER IJON_XXX(...)` 单行插入格式；`<instrumentation_strategy>` 思考区先列状态转移/比较/进度指标再动手。
- **用户提示的容错方言**（aijon.user.j2 亲读）：格式违规重试时注入 `<YELL>YOUR OUTPUT DID NOT FOLLOW THE FORMAT...TRY AGAIN.</YELL>`、加了花括号则 `<YELL>DONT ADD NEW CURLY BRACES. IT CANNOT BE ALLOWED.</YELL>`——**把解析失败翻译成吼叫式纠错**，简单粗暴有效。
- 四 agent 组合：Instrumentor（claude-3-7-sonnet，$20 预算）/ Instrumentor-Java（jazzer 注解版）/ Critique（gpt-o3，$5，审插桩质量）/ Fixer；提示词 artifacts 附 IJON cheatsheet + 示例 C 文件 + 输出格式说明（**知识资产文件化**）。
- 每次 agent action 打当前累计成本日志；迭代耗尽抛异常。

### 4.2 patcherq——补丁团队（main.py/programmer.py/programmerGuy.py 亲读）

- **主循环三层嵌套**（main.py:90-194 亲读，注释里满是 emoji 流程图）：外层**预算恢复循环** → 中层**多根因报告循环**（RootCauseGenerator 聚合 dyva/triage 等多源根因，逐个尝试）→ 内层**Programmer 反馈循环**（generate→verify→save）。
- **Programmer 状态机**（programmer.py 亲读）：`begin→success | duplicate-patch | bad-patch-sanitizer | illegal-patch | corrupted-patch | incorrect-file-path | no-compile | no-build-pass | giveup | stop`——**补丁的每种死法都是一个状态**（非法补丁/坏 sanitizer 补丁/损坏补丁/错文件路径各自分流处理），每态有最大尝试次数。
- **"小睡"预算模式**（main.py:153-171 亲读）：无补丁且根因报告未到齐时，若开启 nap_mode 则**睡到下一个预算窗口**（`nap_becomes_death_after` 次后放弃）——竞赛中 LLM 配额按时间窗恢复，系统学会等钱到账而不是死掉；greedy_patching 开关控制"第一个成功就收"vs"继续薅更多补丁"；退出码 0/1 直接作为管线信号。
- **八道验证 pass**（patch_verifier/verification_passes/）：compile/build_check/crash/**critic**（LLM 评审）/fuzz/reg/tests——机器验证为主+一道 LLM 评审的混合。
- 七个 "-Guy" agent（programmerGuy[claude-3.7-sonnet]/criticGuy/diffGuy/issueGuy/triageGuy/sarifGuy/codeReviewerGuy[CoT 提示]），j2 提示词目录化；SARIF 输出对齐竞赛格式。

### 4.3 共享 agent 框架（libs/agentlib）

AgentWithHistory 基类（模板属性 `__LLM_MODEL__`/`__SYSTEM_PROMPT_TEMPLATE__` 直读 j2 文件）；**全局预算器**（exit_on_over_budget 硬退出）；逐模型 token 成本核算（global_event_dumper.total_cost_per_million）；LLM 预算异常→程序员层捕获换下一个模型/报告（budget/rate-limit 分支处理，programmer.py:215-217）。

### 4.4 PoV 与管线

- povguy（476 行）：PoV 确定性验证（run_pov + md5 指纹）；peek-a-boo/crash_exploration 负责崩溃现场勘察。
- 管线 YAML：jq 查询把任务流按语言（jvm/c/c++）与模式（delta/full）切成平行轨——**数据流的类型化路由**；preprocessing（构建/插桩/索引）→main（fuzz+分析+补丁）→postprocessing（提交）。

### 4.5 配置与默认值面（亲读汇总）

aijon instrumentor=claude-3-7-sonnet/$20、critique=gpt-o3/$5、programmer=claude-3-7-sonnet（可运行时换模）；三 LLM 厂商密钥；Tailscale+Azure+双 API（CRS/竞赛）；OTEL→Signoz 遥测链；final.env 保存决赛配置。

### 4.6 结果验证与去误报

八道 pass 全过才算成功补丁（含 fuzz pass 用补丁后二进制再 fuzz 确认不再崩）；duplicate-patch 状态显式去重；illegal-patch 检查（竞赛规则合规——不许改测试/桩）；PoV 侧 md5+复跑验证。**验证重心在"补丁合法且不破坏"，漏洞侧靠多根因报告交叉。**

## 5. 值得借鉴的设计与技巧

1. **LLM 语义插桩员（aijon）**：把 IJON 式人工智慧注入 fuzzer——LLM 读静态分析 POI 后只做"单行宏插入"这种受控编辑，**用最窄的输出空间（+行号+宏调用）规避 LLM 写代码的最大风险**；插桩禁令的"咆哮体"（DO NOT ×4 + 全大写后果说明）是对模型失效模式的实战修辞。
2. **预算小睡模式**：配额按时间窗恢复的竞赛/生产环境里，"睡到下个预算 tick"优于崩溃重启；nap 次数上限防永久挂起。
3. **补丁死法分类学**：十态程序员状态机——每种失败（非法/重复/坏 sanitizer/坏文件路径/编译失败…）独立分流与计数，比笼统 retry 信息量大得多。
4. **多根因报告竞争**：dyva/triage 等多源根因逐个驱动程序员尝试，一个根因失败不连坐。
5. **数据流管线编排微服务**：jq 过滤的仓库联接 + 语言/模式轨道化——56 组件的拓扑即配置。
6. **知识资产文件化**：IJON cheatsheet/示例代码/输出格式作为 prompt artifacts 随提示词分发。
7. **吼叫式纠错方言**（`<YELL>`）：格式违规的反馈用情绪化强指令，简单直接的格式驯服手段。
8. 退出码作为管线信号（0=有补丁）——最朴素的组件间协议。

## 6. 局限与改进点

- **复杂度爆炸**：56 组件 + 23 库 + 数据流配置，部署需 Tailscale/Azure/双 API/三 LLM 密钥——离开 AFC 环境几乎不可复现（有 local_run 缓解）。
- 提示词内嵌大量试错痕迹（注释掉的模型切换史、咆哮禁令）——版本管理了结果而非成因。
- critic 是唯一 LLM 评审 pass，其余全机器——评审深度有限；agentlib 自研（LangChain executor 封装）迭代已停（决赛后归档）。
- 组件命名（-guy 动物园）可爱但可检索性差；文档主要靠 README 散点。

## 7. 与其他已审计项目的对比

| 维度 | artiphishell（本项目） | buttercup | pentagi | garak |
|---|---|---|---|---|
| 形态 | **分布式微服务 CRS** | 单体 LangGraph CRS | 平台 | 扫描器 |
| LLM 用途 | 插桩+根因+补丁+评审 | 种子+根因+补丁+反思 | 全链 | 裁判 |
| 编排 | 数据流 YAML（jq 仓库） | LangGraph 状态图 | 计划修订循环 | 探针矩阵 |
| 预算管理 | **小睡到下个预算窗** | 预算设置 | max_budget 停 | — |
| 验证 | 8 pass（机器+critic） | 三重机器闸 | mentor | Se/Sp CI |
| 插桩 | **IJON 语义桩（独有）** | — | — | — |

同为 AIxCC CRS，与 buttercup 是两极样本：**buttercup=精炼单体+图状态机，artiphishell=分布式动物园+数据流管线**；两者共享"机器验证定成败"的哲学，artiphishell 独有的是让 LLM 干预 fuzzing 本身（插桩），而不是只围着补丁转。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `libs/aijon-lib/.../agents/ijon_instrumentor.py` `ijon_critique.py` | ✅ 亲读全文 | |
| `libs/aijon-lib/.../prompts/aijon.system.j2` `aijon.user.j2` | ✅ 亲读全文 | 军规+YELL 方言 |
| `components/aijon/main.py` `fixer.py` | ⬜ 部分 | 职责确认（473/121 行） |
| `components/patcherq/src/patcherq/main.py` | ✅ 亲读 | 三层循环+nap 模式（60-240） |
| `components/patcherq/src/patcherq/utils/programmer.py` | ✅ 亲读 | 状态机图谱+预算/限流分支 |
| `components/patcherq/src/patcherq/agents/programmerGuy.py` | ✅ 部分 | 类结构+模型+解析器 |
| `components/patcherq/.../verification_passes/` | ✅ 部分 | 8 pass 清单+职责 |
| `components/povguy/povguy.py` | ✅ 部分 | 结构（476 行确定性验证） |
| `pipelines/*.yaml` | ✅ 亲读头 | 数据流编排模式 |
| `libs/agentlib/` | ✅ 部分 | 基类+预算器机制 |
| 其余 50 组件（fuzzing/静态分析/补丁辅助家族） | ⬜ | 按职责登记 |

## 9. 结论

**ARTIPHISHELL 的核心实现思路是：把 CRS 做成由数据流 YAML 编排的 56 组件分布式动物园——LLM 在其中扮演两个最深的角色：一是"插桩员"（aijon 读静态分析 POI、以受控的单行 IJON 宏插入给 fuzzer 注入语义覆盖率反馈，让覆盖率制导翻过魔数坎），二是"补丁团队"（patcherq 的七个 -Guy agent 在多根因报告竞争驱动下跑十态程序员状态机，经八道验证 pass 定成败）；配额竞争环境下用"小睡到下个预算窗"代替崩溃，退出码即管线信号。** 它与 buttercup 构成 AIxCC 的两极样本（分布式动物园 vs 精炼单体），其 LLM 语义插桩是全部已审项目中独一份的"fuzzer 增强而非补丁专属"用法。

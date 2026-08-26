# transilienceai/communitytools 逐行代码审计

> 审计对象：Transilience AI Community Tools —— 公司级 Claude Code 安全技能套件（26 技能+3 工具集成，44 个 skills 目录/49 个 SKILL.md），**附随附论文《Practice Makes Perfect》**：纯 markdown 技能文件（无微调）把 CTF 基准从 89.4% 迭代到 **104/104**，跨模型迁移（Sonnet 96.2%/Haiku 62.5%）。协调者/执行者/验证者三角色+**逐发现交错盲验证**是核心机制。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/transilienceai/communitytools |
| 本地路径 | `repos/agents/communitytools/` |
| 审计基线 commit | `95fdc12`（refactor: share one tool-gate scaffold…, PR #57） |
| 语言 / 规模 | 技能 Markdown ~13,146 行（skills/）+ Python 工具 ~41,909 行（scripts/tools/benchmarks）+ .claude 工作流 JS |
| Landscape 定位 | 类型：渗透 Agent / Stars：中高 / 一句话：论文支撑的 Claude Code 安全技能套件（失败驱动技能迭代法+交错盲验证） |
| License | MIT |
| 关联论文 | **Practice Makes Perfect: Teaching an AI to Hack by Learning from Its Mistakes**（2026-03，仓内含 PDF+md） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：Claude Code 全生命周期渗透（侦察到 PDF 报告）；旗舰成果是"**不微调、只写技能文件**"逼近基准满分。
- **AI 真伪核查**：真 AI（Claude Code 宿主+协调者/执行者/验证者动态 spawn；工具为辅助 Python）。
- **差异化定位**：全景观唯一**带方法论论文**的技能套件——"失败驱动的知识迭代"（run→fail→diagnose→generalize→repeat ×15 轮）vs 自顶向下知识设计的实证对比；与 pentest-ai-agents 同为宿主语料库形态但多了验证角色与基准闭环。

## 2. 架构总览

```
Claude Code 宿主（Docker Kali 一键脚本：kali-claude-setup.sh，--dangerously-skip-permissions）
   ▼ 装载
skills/ ×44 目录（coordination 为入口 ★：协调者 spawn 执行者/验证者，Agent(prompt=...) 动态生成）
   P0 范围→P1 侦察+读源码→[P2 三假设(≥1 wildcard)→P2b 创造性研究(条件)→P3 执行者 1-2→
   P4 交错验证(逐发现，新鲜盲代理)→P4b 重置(强制创造性研究)]×30 实验→P5 彻底性验证+报告
.claude/workflows/*.js（htb-solve/validate-findings/safe-pr/pci-compliance 等编排脚本+测试）
benchmarks/（bountybench/xbow 基准跑批+analyze_results） papers/（论文 PDF+md）
tools/（cvss_calc 961/passive_web_probe/chain-merger/fixture_ingest…） formats/（报告样式）
```

## 3. 核心模块精读（审计主体：coordination 技能+验证角色+论文）

### 3.1 coordination/SKILL.md（全文亲读）——协调者契约

- **Rule 0：源码优先**："读所有可及源码（应用代码/配置/脚本/共享内容）再发执行者批次。**每个答案都在你已有的数据里。不读就猜是最常见的失败模式**"——把"读代码先于动手"定为第零原则。
- **主会话禁内联**："父编排者绝不能在主会话内联执行此工作流——发现自己在主会话跑 P1-P5，说明跳过了 spawn 步骤，簿记纪律已被静默禁用"——用反模式警告强制角色分离。
- **P0-P5 流程**（见架构图）：P2 写三条假设**至少一条标 [wildcard]**（强制非常规路径）；P4 验证**交错进行**（"INTEGRATE 物化候选的瞬间就验证，不等下游一次性通过"）；**coverage-by-VALID**（"覆盖率只按 VALID 翻转；REJECTED/DROPPED 类保持 pending 继续找"）；无进展 1 批→P2b；**同一概念目标尝试 ≥3 次→P4b 全量重置**（"重读全部侦察+源码+链。强制创造性研究。全新理论"——防理论锁死）；30 实验上限+第 5/15/25 实验强制怀疑者。
- attack-chain.md 簿记（≤50 行、旧项剪成单行）；experiments.md 台账+概念目标计数。

### 3.2 validator-role.md（全文亲读）——**全景观验证角色的最成熟规范**

- **两类盲验证者**：发现级（交错 spawn、**每个 cure 轮次重开新鲜代理重读磁盘**以维持盲契约）+交战级（收尾一次看整体彻底性）——"**只挂载 reference/VALIDATION.md，不挂载完整攻击技能——会偏置判断**"（控制验证者知识面防确认偏误）。
- **五项全过检查**（一项失败=REJECTED 的 all-or-nothing）：①CVSS 分带+NVD 对照（引用 CVE 须跑 nvd-lookup，**执行者评分与 NVD 差 >1.0 标记**）；②证据存在（description/poc.py/poc_output/evidence/raw-source）；③**PoC 有效**（合法 Python、引用目标、重跑输出与记录一致）；④声明对证据（description 每条事实声明有原始扫描/日志佐证）；⑤**日志相位与时间戳**（recon/experiment/test/verify 四相位齐全且**时间戳间隔 ≥2 秒——"抓模板化批量盖章的发现"**，反伪造的时间学检验）。
- **终态路由**：CONFIRMED（VALID/REPAIRED）→validated/（"报告的唯一来源"）；REJECTED→false-positives/（留审计）；**CURE 泳道**（降级发现交给 scoped cure 执行者——"只给 failed_checks+missing_evidence，告知**不得重新理论化**"——修复者只许补证据不许改叙事）→新鲜盲代理重验→MAX_CURE_ROUNDS 后 dropped/；**"无 gaps 章节——validated/ 按构造即 VALID/REPAIRED"**（drop-entirely 报告观：报告里不出现'未验证发现'的摊手段）。
- 验证工件五件套（validation-summary/poc 重跑输出/**独立复现脚本**[自己的 import 自己的目标引用]/code-references[file:line 逐声明引用]/浏览器截图按需）。

### 3.3 论文（practice-makes-perfect.md 头 100 行亲读）——失败驱动迭代法

- **基线 89.4%→100%（104/104）**：裸 Claude Opus 4.6 差 11 题→"**让失败当课程**"：每轮"跑基准→抓失败→诊断缺失技术→写进通用技能文件（泛化到漏洞类而非那道题）→重跑"×约 15 轮；230 个结构化 markdown 技能文件、零微调零检索基建。
- **跨模型迁移**：同一技能集 Sonnet 86.5%→96.2%、Haiku 57.7%→62.5%——"技能可迁移性与受益所需最小模型容量"的双证据；贡献清单第 5 条直言"**迭代失败分析优于自顶向下知识设计**"。
- 公平框架（技能不得含基准特定偏置）与泛化-压缩步骤（防过拟合基准）。

### 3.4 其余（结构确认）

- skills/ 44 目录覆盖全生命周期（ai-threat-testing/cve-poc-generator/hackthebox/hackerone/pci-secure-software/regression-sweep/**skill-update+skill-prune**——技能自维护技能）；160+ 参考文件内联 PayloadsAllTheThings 技术；.claude/workflows JS 编排带单测（wiring/parity/syntax）；benchmarks/（bountybench 1,012 行跑批+CWE 技能映射）；scripts/check_client_data 1,372 行（客户数据护栏）。

## 4. 值得借鉴的设计与技巧

1. **交错逐发现盲验证 + cure 泳道**：物化即验、新鲜代理重读磁盘维持盲性、cure 只补证据禁重理论化、新鲜盲代理复验——验证时序与知识控制的完整规范（与 xalgorix 独立验证、nebula 协议 Verifier 三态并列且最细）。
2. **时间戳间隔检验**（≥2s 抓批量盖章）与"NVD 分差 >1.0 标记"——反伪造与评分校准的两个可程序化的具体闸。
3. **drop-entirely 报告观**（无 gaps 章节，validated/ 按构造合格）——与"把未验证发现塞进报告"的行业惯例相反的洁癖。
4. **失败驱动技能迭代法**（论文实证）：泛化-压缩防过拟合+跨模型验证容量阈值——技能库建设的可复制方法论。
5. P4b 强制重置（同概念目标 3 次）+wildcard 假设强制+第 5/15/25 实验怀疑者——反理论锁死的三重机制；Rule 0 源码优先；主会话禁内联的反模式警告。
6. 验证者知识面控制（只挂 VALIDATION.md）——用信息不对称保护独立性。

## 5. 局限与改进点

- 104/104 与 96.2% 为论文自报（基准套件身份与公平框架细节未完整核验；对照 BoxPwnr 公开 trace 的第三方可查性）；Claude 生态绑定。
- 主会话 `--dangerously-skip-permissions` 的 Docker 模式与技能验证治理并存（执行闸在容器层）；Python 工具 41.9k 行仅结构确认。
- 44 技能的协调复杂度靠纪律文本维持（30 实验上限等）；论文与技能文件的对应（230 vs 49 SKILL.md）存在版本漂移。

## 6. 与其他已审计项目的对比

| 维度 | communitytools（本项目） | pentest-ai-agents | xalgorix | BoxPwnr |
|---|---|---|---|---|
| 形态 | **论文技能套件（宿主）** | 纯语料库 | 平台 | 基准 harness |
| 验证 | **交错盲验证+cure 泳道+时间戳检验** | scope 块 | 独立对抗复测 | 平台判旗 |
| 知识演进 | **失败驱动迭代（论文实证）** | 版本日志 | — | — |
| 基准 | **104/104 自报+跨模型** | — | verify-claims | 公开 traces |
| 角色 | 协调/执行/验证 | 52 平行专员 | agent+verifier | 求解器矩阵 |

与 pentest-ai-agents 构成宿主语料库的双样本：那边是静态人格集，这边是**带验证角色与基准闭环的进化知识系统**——"技能文件即知识载体"的两种成熟度。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `skills/coordination/SKILL.md` | ✅ 亲读全文 | 协调者契约（P0-P5/Rule 0/反模式警告） |
| `skills/coordination/reference/validator-role.md` | ✅ 亲读全文 | 两类盲验证者+五检查+终态路由 |
| `papers/practice-makes-perfect.md` | ✅ 亲读头 | 100/~500（摘要/循环/贡献） |
| `skills/` 其余 43 目录 | ✅ 清单+职责确认 | 覆盖面与 skill-update/prune 登记 |
| `tools/` `benchmarks/` `scripts/` `.claude/workflows/` | ✅ 结构登记 | 未逐行 |
| `README.md` | ✅ 亲读头 | 定位/论文公告/架构 |

## 8. 结论

**communitytools 的核心实现思路是：以失败驱动的技能迭代逼近知识边界——裸模型跑基准、失败当课程、缺失技术泛化成 markdown 技能（×15 轮 89.4%→104/104，零微调），协调者按 P0-P5 契约运作（源码优先/三假设含 wildcard/无进展即创造性研究/概念目标三振即全量重置），执行者产出的每个候选在物化瞬间交新鲜盲代理验证（五项 all-or-nothing 检查含时间戳间隔反伪造与 NVD 分差校准，降级走禁重理论化的 cure 泳道），报告只收 validated/ 且不设 gaps 章节。** 它是已审 38 项中唯一带方法论论文的技能系统：交错盲验证规范与失败驱动迭代法是两个可直接复用的资产；104/104 的自报性质与 Claude 绑定是其边界。

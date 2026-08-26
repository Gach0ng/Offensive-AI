# BerylliumSec/nebula 逐行代码审计

> 审计对象：Nebula 3 —— Python ~91k 行的**本地优先桌面渗透工作台**（Tauri+React 前端+本地 sidecar）："intent → assistance → approval → execution → evidence"——操作员权威显性化（scope 强制/审批暂停/硬预算/rootless OCI 隔离），LangGraph supervisor/specialist 任务与**独立证据验证门**，SHA-256 内容寻址工件+只追加事件+认证回放。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/BerylliumSec/nebula |
| 本地路径 | `repos/agents/nebula/` |
| 审计基线 commit | `a9d3955`（Prefer signed APT installation；版本 3.0.0-alpha.5+） |
| 语言 / 规模 | Python ~91,288 行（src/nebula/v3 30+ 模块）+ React/TS 前端 + Tauri 壳；含 APT/Homebrew 签名发布链 |
| Landscape 定位 | 类型：渗透 Agent（实为操作员工作台）/ Stars：中 / 一句话：审批制本地渗透工作台（证据链+内容寻址+supervisor/specialist 任务） |
| License | 见 LICENSE.md |
| 关联论文 | 无（NEBULA3 文档族+诊断指南） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：把安全交战的全部工作面收进一个桌面（终端/代码/浏览器/助手/文件/笔记/任务/发现/报告），AI 负责"调查、组织、书写"，**操作员定义 scope、授予权威、决定什么运行**——人在权威位的产品化。
- **AI 真伪核查**：真 AI（providers 多适配器/missions 编排/chat/execution_ai/writing_ai）；模型提供商可选（无模型时人终端/证据流/报告仍可用——**AI 是可拆卸件**）。
- **差异化定位**：与 CyberStrikeAI/pentest-copilot 同为操作员平台，但把**权威与证据做成第一架构事实**：审批暂停保留开销、硬预算、只追加事件、内容寻址工件、完整性清单导出。

## 2. 架构总览

```
Tauri 桌面壳 + React 工作台（127.0.0.1 sidecar，loopback-only token 握手）
   ▼
FastAPI 后端（v3/api 7546：版本化 REST/OpenAPI+认证 WS）—— SQLite WAL / PostgreSQL
   ├─ Missions（orchestration.py ★：Supervisor/Specialist/Verifier 三协议）
   │    8 专员角色（scope_planning/passive_recon/network_service/web_api/
   │    vuln_intelligence/code_analysis/evidence_verification/reporting_remediation）
   ├─ 证据层（evidence/artifacts：SHA-256 内容寻址+不可变执行证据）
   ├─ 事件层（append-only 单调序列 run events + 认证回放）
   ├─ 执行层（sandbox 2777：rootless OCI；broker-owned DNS+scope 强制；人类终端有显式
   │    root/writable/unrestricted 边界，受审执行保持离线或单目标 scope）
   ├─ 审批（SpecialistApprovalRequired ★：暂停点保留已发生模型开销）
   └─ 报告（确定性服务端渲染 PDF；review-first AI 草稿；integrity-manifested 导出）
诊断体系：结构化 error-by-default 日志/关联 ID/Diagnostics 视图/脱敏支持包
```

## 3. 核心模块精读（审计主体；91k 行大仓亲读计划：编排关键段+文档族）

### 3.1 任务编排（orchestration.py 关键 330 行亲读）

- **三协议清晰分工**：`Supervisor.plan/synthesize`、`Specialist.run`（角色+允许工具集）、`Verifier.verify`——**验证是协议级公民**而非旁挂。
- **MissionPlan 是带 DAG 校验的 Pydantic 模型**：任务 id 唯一/依赖必须已知/不得自依赖/**无环检查**（Kahn 式遍历，不达全量即"dependency cycle" 报错）——计划的结构合法性在类型层强制。
- **PlannedTask 自带治理字段**：role/title/instructions/depends_on/delegation_depth（≥0）/target/**risk_class**（默认 LOCAL_READ）/allowed_tools——风险类别与工具白名单进任务定义。
- **SpecialistOutcome 三态**：CONTINUE/COMPLETE/**BLOCKED**（显式受阻结局，非静默失败）。
- **EvidenceVerifier（默认独立门）**：候选发现**必须挂 evidence_ids 且给出 reproducible_steps**——"候选发现无可复现验证步骤"直接拒绝（accepted=False）；这是 xalgorix 式重利用验证的**结构化最小版**（验证的是证据完备性而非重新打一遍）。
- **SpecialistApprovalRequired**：审批暂停异常**保留暂停前已发生的模型 usage 与成本**——恢复后预算/记账不丢（审批的经济学完整性）。
- **ModelSpecialist 纯分析约束**："你是有边界的 Nebula 安全分析专员……**不得声称运行命令/访问系统/使用工具**"；**模型返回 tool_calls 即抛错**（"analysis-only model returned tool calls without broker authorization"）——工具必须经 broker 授权，模型层无权自发；空结果亦抛错；成本按 provider 费率显式计算。
- StaticSupervisor/StaticSpecialist 离线存根（doctor/测试/导入的旧项目可用）——**无模型不崩**的降级路径。

### 3.2 权威与证据体系（文档族+结构确认）

- **operator authority 流**：意图→辅助→**审批**→执行→证据——README 以此单行定义产品；scope 强制/审批暂停/硬预算/rootless OCI "坐在 AI 辅助与被测系统之间"。
- **证据不可变链**：SHA-256 内容寻址工件+不可变执行证据+只追加单调序列事件+**认证回放**+完整性清单导出——"结论如何得出"的持久轨迹（对照 BoxPwnr 公开 trace、hackingBuddyGPT JSONL——这里是密码学级的）。
- **终端双轨制**：人类终端有显式 root/writable/unrestricted 边界；**受审与 agent 执行保持离线或单目标 scope**——人与 agent 的权限刻意向不对称设计。
- 诊断体系（结构化日志/关联 ID/脱敏支持包）与 v2 只读导入（源清单+回滚）。

### 3.3 其余（结构登记）

- harnesses.py（8,444 行——工具/运行时装配的巨型模块）、api（7,546）、chat（2,690）、sandbox（2,777）、container_terminal/terminal_history（Kali 终端集成）、automation_runtime（AUTOMATION-RUNTIME 文档）、kali_tool_inventory/egress_helper/scope_import/privacy/redaction。

## 4. 值得借鉴的设计与技巧

1. **验证作为协议公民**：Verifier 与 Supervisor/Specialist 并列为协议——默认 EvidenceVerifier 把"候选发现必须挂证据+可复现步骤"做成结构化门（无证据/无步骤=拒绝），可替换为更强的重利用验证器。
2. **审批暂停保留开销**：SpecialistApprovalRequired 携带暂停前的 usage/cost——恢复后预算记账完整（审批机制的经济学细节，全景观首见）。
3. **计划 DAG 在类型层校验**（无环/无未知依赖/无自依赖）——LLM 产出的计划先过结构合法性再执行。
4. **analysis-only 模型的工具越权即错**：返回 tool_calls 直接抛"未经 broker 授权"——模型层与工具层的权限单流向。
5. **证据的密码学化**：内容寻址+只追加事件+认证回放+完整性清单导出（对比其他项目的明文 trace）。
6. **终端双轨不对称**（人类 unrestricted vs agent 离线/单目标）+ 无模型全功能降级 + StaticSupervisor 离线存根。
7. BLOCKED 显式结局；delegation_depth/risk_class/allowed_tools 进任务模型。

## 5. 局限与改进点

- 3.0.0-alpha 预览态（文档自述）；harnesses.py 8,444 行巨型装配模块未亲读（工具生态的主体在那）。
- EvidenceVerifier 默认门只验证据完备性（有 evidence_ids+reproducible_steps），**不重打**——弱于 xalgorix 的对抗复测（架构上可换，但默认即卖点差距）；审批/预算执行细节在未读模块。
- 91k 行单包+30 模块的分层靠约定；前端/Tauri 壳未审。
- 本地优先带来部署门槛（Tauri 桌面+OCI+Playwright）。

## 6. 与其他已审计项目的对比

| 维度 | nebula（本项目） | xalgorix | pentestagent | pentest-copilot |
|---|---|---|---|---|
| 形态 | **本地桌面工作台** | 自托管平台 | TUI 工作台 | Web 平台 |
| 验证 | **协议级 Verifier（证据完备门）** | 独立对抗重利用 | 反幻觉军规 | — |
| 权威 | **审批暂停（保留开销）+硬预算** | 执行层背书 scope | scope 门交操作员 | 同意门 |
| 证据 | **内容寻址+认证回放** | validated finding | ShadowGraph | engagement state |
| 编排 | supervisor/specialist DAG | 单 agent+verifier | crew+COA | racer 裁量 |
| AI 依赖 | **可拆卸（无模型可用）** | 必须 | 必须 | 必须 |

它是"操作员权威"路线的最系统化落地：intent→approval→execution→evidence 不是口号而是类型/协议/密码学三层实现；验证门比 xalgorix 轻（证据完备 vs 对抗重打）但架构位同高——两者并读即"验证该放多重"的光谱两端。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `src/nebula/v3/orchestration.py` | ✅ 亲读关键段 | 330/2114（协议/DAG/验证门/审批/分析专员） |
| `README.md` `docs/NEBULA3.md` | ✅ 亲读 | 架构声明/能力清单 |
| `src/nebula/v3/` 模块清单（30+） | ✅ 结构登记 | harnesses/api/chat/sandbox 等未逐行 |
| `docs/`（诊断/迁移/场景/发布注记） | ✅ 清单确认 | 未逐篇 |
| 前端/Tauri/packaging/tests | ⬜ | 未读 |

## 8. 结论

**Nebula 3 的核心实现思路是：把操作员权威做成桌面工作台的第一架构事实——supervisor/specialist/verifier 三协议承载任务（计划经 DAG 类型校验、任务自带风险类别与工具白名单、BLOCKED 显式结局），执行前有保留开销的审批暂停与硬预算，执行走 rootless OCI 与 broker 负责的 DNS/scope，证据以 SHA-256 内容寻址+只追加事件+认证回放固化，默认 EvidenceVerifier 拒绝无证据或无可复现步骤的候选发现，且模型是可拆卸件（无 AI 时工作台照常）。** 它是已审 31 项中"人在权威位"最彻底的产品化样本：审批经济学（暂停保留花费）、analysis-only 模型越权即错、终端双轨不对称三个细节均属首见；验证门较 xalgorix 轻是刻意的架构取舍——verifier 协议位留好了换重炮的位置。

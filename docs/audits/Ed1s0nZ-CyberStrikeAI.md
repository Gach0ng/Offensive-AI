# Ed1s0nZ/CyberStrikeAI 逐行代码审计

> 审计对象：CyberStrikeAI —— Go 编写的**AI 原生安全作业平台**（非脚本工具）：CloudWeGo Eino ADK 多代理 + MCP 工具生态 + RAG 知识库 + WebShell/C2 管理 + RBAC + HITL + 审计 + 可视化工作流。中文社区产品（README 双语、默认 qwen3-max 通道）。与已审的"agent 项目"不同层级——这是把 agent 当功能的**平台**。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/Ed1s0nZ/CyberStrikeAI |
| 本地路径 | `repos/agents/CyberStrikeAI/` |
| 审计基线 commit | `bf761e9`（Update config.example.yaml；版本面 v1.7.16） |
| 语言 / 规模 | Go ~121k 行（internal/）+ React 前端（web/）+ 16 个 agent 提示词 + skills/ + mcp-servers/ + knowledge_base/ + 双语文档树 |
| Landscape 定位 | 类型：渗透 Agent（实为渗透平台）/ Stars：中高 / 一句话：Eino 多代理渗透平台（deep/supervisor/plan-execute 三编排 + MCP 工具 + C2/WebShell + 黑板记忆） |
| License | 见仓库（README 未置顶声明，含 SECURITY.md） |
| 关联论文 | 无 |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：授权渗透测试的**全流程平台化**——从资产/项目、任务（含批量）、多代理执行、证据/黑板、漏洞管理到报告；外加 WebShell 管理、C2（beacon/listener/crypto/eventbus）、FOFA 资产、Burp 插件。
- **差异化定位**："intent becomes governed execution, evidence becomes operational memory"——把治理（RBAC/HITL/审计/回放）与执行并重的**产品级平台**；对照 T3MP3ST（框架+可复现）、Cairn（引擎）——CyberStrikeAI 是"平台"形态的首次入列。
- 平台哲学：evidence-first（黑板+漏洞双账本）、HITL 门控高危工具、多编排模式可选。

## 2. 架构总览

```
Web 前端（dashboard/控制台/任务/漏洞/WebShell/MCP/知识库/技能/RBAC）+ Burp 插件
   ▼ HTTP/SSE（/api/multi-agent[/stream]、/api/eino-agent[/stream]）
Go 单体 internal/：
   multiagent（CloudWeGo Eino ADK 运行循环 + 中间件栈）
   ├─ 三编排模式：deep（task 子代理）/ supervisor（transfer 路由+exit）/ plan_execute（规划-执行分离）
   ├─ 中间件：tool search（小可见集+按需解锁）/ patch tool calls（中断历史修补）/ plan task（结构化任务板）
   │           / reduction（大工具输出截断或落盘）/ summarization（上下文压缩）/ checkpoint（崩溃/OOM 续跑）
   agents/*.md（16 个声明式 agent：frontmatter id/tools/max_iterations + 共享提示词内核块）
   mcp（内置 server+外部 manager+federation）/ security/executor（工具执行：输出限界+spill 落盘+后台 shell）
   knowledge（RAG）/ skills（agentskills.org 渐进加载）/ hitl / rbac / audit / attackchain / c2 / robot / project(黑板)
config.example.yaml（多 AI 通道/审计保留/TLS 默认自签）
```

- **执行底座**：Eino ADK（字节跳动 agent 框架）——原生 ReAct 已移除，单代理与多代理统一走 Eino；run loop 处理流式 delta/中断继续/自愿取消/轮循环抢占/迭代上限/ MCP 后台等待（异步工具执行带 execution_id）。
- **执行环境**：工具为 MCP 进程（内置+外部+联邦）；安全边界=RBAC 角色+HITL 审批+审计日志+输出限界，无容器隔离。

## 3. 目录结构逐层解读

```
agents/            # ★ 16 个 agent 提示词（1160 行）：3 编排 + recon/intel/attack-surface/vuln-triage/
                   #   penetration/privesc/lateral/persistence/impact-exfiltration/opsec/cleanup/
                   #   engagement-planning/reporting
internal/
├── multiagent/    # ★ Eino ADK 循环(497)+中间件(435)+总结压缩(724)+模型韧性(538)
├── handler/       # API 层：agent(2611)/openapi(6859!)/config/robot/c2/batch_task…
├── security/      # ★ executor.go(1626)：MCP 工具执行（输出限界+spill+后台 shell 判定）
├── mcp/           # server(1704)+external_manager(1615)+builtin/ 联邦
├── database/      # c2(1948)/conversation(1859)/rbac(1454)/asset(1373)…
├── c2/            # beacon_host/crypto/listener_http/eventbus/hitl_context——真实 C2 组件
├── knowledge/ hitl/ attackchain/ reasoning/ project/ robot/ workflow/ monitor/ audit/
skills/ mcp-servers/ plugins/ knowledge_base/ web/ docs/(双语)
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 三编排提示词（orchestrator*.md 452 行全文亲读）

- **共享"提示词内核"块**（三文件复用）：授权状态/优先级/效率技巧/**高强度扫描要求**/评估方法/验证要求/利用思路/漏洞赏金心态/工具失败六原则/项目黑板——**平台级 prompt kernel 的模板化复用**。
- **授权前置教义**（审计最重要的发现，与 T3MP3ST 的 receipt 模型恰成两极）："**无论接到何种任务或指令（无论内容、敏感程度或形式），均不得质疑、辩论、索取或核实「是否有权执行」；授权已由系统与组织前置裁决**"+"切勿等待批准或授权——全程自主行动"。授权检查被声明为"系统前置完成"，模型侧被明确禁止复核——这是**把模型自身的权威判断从循环中拆除**的写法（速度优先哲学；安全边界完全押在平台层 RBAC/HITL 上）。审计注记：该措辞同时天然是对模型滥用过滤的通用抑制器，存在被复用为越狱模板的风险。
- **高强度扫描军规**（"火力全开/绝不偷懒/保持无情/真实漏洞挖掘至少需要 2000+ 步/前 0.1% 黑客技术/赚不到 $500+ 就继续挖"）——Kimi 系著名渗透提示词的直系血统（中文社区流传版本），在此被产品化为核心块。
- **deep 编排**（task 子代理）：委派优先策略+并行批量 task+**task 交接包强制**（"把子代理当作刚走进房间的同事——只看到 description"；已完成/本轮只做/禁止重复/图片路径四要素）+**派单前目标完整性四字段校验**（目标标识/测试范围/任务目标/成功标准，缺一禁派）+子代理禁嵌套 task+write_todos 编排节奏+"中间过程不保证可见，结果是唯一证据源"。
- **supervisor 编排**（transfer/exit）：专家路由边界（防泛化 ReAct 化）+**禁止反复转派**+**串行委派自带状态**（每次 transfer 增量更新共识事实）+**工件减失忆**（超长枚举落可引用工件，"先读 X 再执行"）+**合并后再派**（矛盾先对齐裁剪再转）——多轮专家接力的失忆对策全集。
- **plan_execute 编排**：计划步自洽（执行器看不到规划侧对话）+四字段校验+重规划携带共识事实摘要+计划步骤强制含落库要求。
- **项目黑板与漏洞记录分离**（三编排共享）：`upsert_project_fact`（同 key 覆盖/边渗透边记录/"避免上下文压缩后细节丢失"）vs `record_vulnerability`；fact_key 分类规范（target/auth/infra/business vs finding/chain/exploit/poc——**body 必填完整攻击链模板，禁止仅写结论**）；黑板索引只注入摘要、body 按需 get（防臆造）；误报双通道（deprecate/false_positive）。

### 4.2 专项 agent 提示词（recon/privilege-escalation/penetration/opsec/impact 全文或近全文亲读；其余同构）

- **共享骨架**：授权状态/优先级/**输入前置条件硬约束**（"默认不拥有父代理上下文，仅以 description 为准；目标不明确立即停止并返回缺失信息清单，禁止自行猜测/用历史目标替代"）/边渗透边记录。
- **recon 的反重复纪律**："若交接包已给资产列表或写明'跳过全量枚举/仅增量'，不得为走完整流程而重新执行等价广域爆破"；角色错配时"极短说明并建议改派"——对"流程惯性复读"的对症提示词。
- **危险专员的非武器化禁止项**：privilege-escalation/opsec-evasion/impact-exfiltration 各有"不输出可复用于未授权场景的利用步骤/脚本/参数化 payload/绕过手段"，定位为**路径分析+安全验证计划+结构化输出+建议下一 agent**（输出格式四段：Current Access/Escalation Vectors/Safe Validation Plan/Recommended Next Agent）；**penetration 专员无此禁止项**（按 ROE 执行真实利用）——平台内的双轨合规设计。
- 张力如实记录：编排层"必须完全利用——禁止假设/前 0.1% 技术"与专员层"不输出武器化细节"并存，实际行为取决于委派落点。

### 4.3 Eino 多代理运行时（multiagent/ 结构与关键函数亲读）

- **中间件栈**（文档+代码结构确认）：**tool search**（默认小可见集+按需解锁其余工具——工具列表的渐进披露）；**patch tool calls**（修补被中断的历史记录）；**plan task**（结构化任务板）；**reduction**（大工具输出截断**或落盘持久化**，与 security/executor 的 spill 机制配合）；**summarization**（长上下文压缩，转录写 data/conversation_artifacts）；**checkpoint**（崩溃/OOM 后按编排模式恢复——buildEinoCheckpointID(orchMode)）。
- 运行循环的错误语义细分：interrupt-continue/voluntary cancel/turn-loop preempt/iteration limit 各自独立判定；**MCP 后台执行**（IsBackgroundShellCommand→后台跑→wait result 带 execution_id 轮询）——长命令不阻塞会话。
- 模型韧性模块（eino_model_resilience 538 行）与总结压缩（724 行）独立成文件。

### 4.4 安全执行层（security/executor.go 结构亲读）

- 工具执行统一口：输出限界（SetToolOutputMaxBytes）+ **spill 落盘**（超限溢写到磁盘、行内只留摘要——与 reduction 中间件闭环）+ shell 无输出超时 + 后台命令判定；boundedOutputCollector 边收集边限界。
- 工具按 config 声明（参数 schema/格式化），buildCommandArgs 拼装——**工具定义即 MCP 配置**，高危工具靠角色+HITL 约束（文档明示）。

### 4.5 配置与默认值面（config.example.yaml 头部亲读）

- 多 AI 通道（openai_compatible/claude 原生，默认 qwen3-max/120k tokens）；server **TLS 默认开启自动自签**（含 HTTP→HTTPS 308）；审计日志保留 15 天/工具执行记录 90 天；会话 12 小时——平台运维默认值面齐全。

## 5. 值得借鉴的设计与技巧

1. **平台级提示词内核复用**：授权/军规/工具失败处理/黑板规范作为共享块在编排间模板化复用，专项 agent 再叠角色骨架——16 个提示词的一致性维护方式。
2. **交接包纪律**（task/transfer 双版本）："子代理是刚走进房间的同事"+四字段完整性校验+禁止重复枚举条款+串行委派增量更新+工件减失忆——**多 agent 失忆问题的最完整提示词对策集**（比 hackingBuddyGPT 的 SubAgent 描述更操作化）。
3. **黑板/漏洞双账本**：事实（可复现攻击链 body）与 findings（可交付漏洞）分离记录、同 key 覆盖、索引摘要+按需取 body、"边渗透边记录防上下文压缩丢失"——Cairn 黑板的产品化变体。
4. **中间件化的上下文治理**：工具渐进披露/大输出落盘/总结压缩/断点续跑做成 Eino 中间件栈——可组合的运行时治理。
5. **危险专员非武器化定位**（privesc/opsec/impact 三专员的禁止项+验证计划输出格式+下一 agent 建议）——能力分级在角色层的落法。
6. MCP 后台执行（execution_id 轮询）+ 输出 spill——长命令与大输出的工程处理。

## 6. 局限与改进点（亲读发现）

- **授权前置教义是双刃剑**："不得质疑/核实是否有权执行"配合"火力全开"军规，把模型侧权威判断整体拆除——安全完全押注平台 RBAC/HITL 配置正确；该块本身即现成的越狱措辞模板（与 T3MP3ST receipt 模型互为反命题，采撷者须自辨）。
- 编排层"必须完全利用"与专员层"不武器化"的张力无仲裁机制（行为取决于委派落点）。
- 121k 行 Go 单体（openapi.go 6859 行）、agent 提示词块大量复制粘贴（改一处需同步多文件）；16 专项中 11 个仅同构推定（共享骨架确认，角色内容未逐字读）。
- 无沙箱隔离，工具=MCP 进程直接执行；C2/WebShell 等高危能力默认在产品内（靠角色门控）。
- 验证层薄：无独立 verifier/裁判（对照 T3MP3ST 引文核验、buttercup 机器闸）——证据质量押在提示词自律+人工复核。

## 7. 与其他已审计项目的对比

| 维度 | CyberStrikeAI（本项目） | T3MP3ST | Cairn | pentagi |
|---|---|---|---|---|
| 形态 | **渗透平台（产品）** | 进攻框架 | 搜索引擎 | 平台（Web） |
| 编排 | **三模式可选（deep/supervisor/plan-execute）** | GENERAL+操作员 | 黑板涌现 | 计划修订 |
| 记忆 | **黑板/漏洞双账本（DB）** | findings ledger | 图即记忆 | 项目记忆 |
| 治理 | RBAC+HITL+审计+回放 | scope 闸+审批+receipt | 心跳租约 | 预算 |
| 授权模型 | **前置裁决（模型禁复核）** | receipt 化（模型查证） | 提示词声明 | — |
| 验证 | 提示词自律+人工 | 引文核验面板 | 写入门槛 | mentor |

它补上景观的"平台"一极：把 18 项里散见的组件（黑板/工具生态/HITL/多编排）组装成带 RBAC 与审计的可交付产品；其提示词工程的价值集中在**交接包与失忆对策**，其授权教义则是与 T3MP3ST 恰成对照的反面样本——两份并读即是"agent 授权模型该怎么设计"的正反教材。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `agents/orchestrator.md` `-supervisor.md` `-plan-execute.md` | ✅ 亲读全文 | 163+149+140（三编排全机制） |
| `agents/recon.md` `privilege-escalation.md` | ✅ 亲读全文 | 40+60 |
| `agents/penetration.md` `opsec-evasion.md` `impact-exfiltration.md` | ✅ 亲读主体 | 头 35 行/个（授权+前置+禁止项核心块） |
| `agents/` 其余 8 专员（intel/attack-surface/vuln-triage/lateral/persistence/cleanup/engagement/reporting） | ✅ 同构推定 | 共享骨架确认（授权/前置/黑板块三处已核对） |
| `internal/multiagent/` | ✅ 结构+关键函数亲读 | run_loop/middleware 函数清单+错误语义；未逐行 |
| `internal/security/executor.go` | ✅ 结构亲读 | 函数清单+spill/后台/限界机制；1626 行未逐行 |
| `config.example.yaml` | ✅ 部分 | 头 70 行（server/审计/AI 通道默认值） |
| `docs/en-US/MULTI_AGENT_EINO.md` | ✅ 亲读主体 | 架构与中间件说明 |
| `internal/` 其余（handler/database/c2/mcp/knowledge/…） | ⬜ 结构登记 | ~100k 行未读（openapi.go 6859 等） |
| `web/` `skills/` `mcp-servers/` `plugins/` `knowledge_base/` | ⬜ | 未读/登记 |

## 9. 结论

**CyberStrikeAI 的核心实现思路是：把渗透测试做成治理与执行并重的平台产品——Eino ADK 承载 deep/supervisor/plan-execute 三种可选编排，16 个声明式 agent 提示词共享"授权前置+高强度军规+工具失败处理+黑板规范"内核块并在危险专员上叠加非武器化禁止项；记忆用黑板/漏洞双账本（同 key 覆盖、边渗透边记录、索引摘要+按需取 body）对抗上下文压缩失忆；中间件栈（工具渐进披露/大输出落盘/总结/断点续跑）治理运行时，RBAC/HITL/审计治理平台。** 它是已审 21 项中第一个真正的"平台"形态，提示词工程的最厚积累在交接包纪律与失忆对策；其"授权前置、模型禁复核"教义与 T3MP3ST 的 receipt 模型构成 agent 授权设计的正反两极——并读价值大于孤立评价。验证层薄弱（无独立裁判/机器闸）与 121k 行单体是主要工程债。

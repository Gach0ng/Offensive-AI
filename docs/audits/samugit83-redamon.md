# samugit83/redamon 逐行代码审计

> 审计对象：RedAmon —— v6.11.4 的全链路自主 AI 安全框架（Trendshift #21794）："侦察 ➜ 利用 ➜ 后渗透 ➜ AI 分诊 ➜ CodeFix 代理 ➜ GitHub PR，从第一个包到合并的补丁"。Neo4j 攻击面知识图 + 100+ 工具 + 400+ AI 模型 + Fireteam 并行多 agent + RoE 护栏 + stealth 模式。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/samugit83/redamon |
| 本地路径 | `repos/agents/redamon/` |
| 审计基线 commit | `7e3149e`（docs: update docs；版本面 v6.11.4） |
| 语言 / 规模 | Python ~74,900 行（agentic 17k + recon + mcp + graph_db + tooling）；DISCLAIMER 含 LLM 数据外发风险专节 |
| Landscape 定位 | 类型：渗透 Agent / Stars：高 / 一句话：全链路（侦察到提 PR）Neo4j 知识图驱动的自主 AI 安全框架 |
| License | MIT（STRIDE 威胁建模声明） |
| 关联论文 | 无（redamon.org + wiki） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：授权测试的端到端自动化——多工具并行侦察进 Neo4j 知识图 → agent 按阶段（INFORMATIONAL/EXPLOITATION/POST-EXPLOITATION）利用 → 发现分诊去重定级 → **CodeFix 代理改代码开 PR**——攻击面到修复的闭环（与 buttercup 的"修好并证明没修坏"同一终点，产品化路径）。
- **AI 真伪核查**：真 AI。agentic/ 目录完整（主 ReAct 循环 + 逐漏洞类提示包 + 意图分类器 + Fireteam + 修复代理）；DISCLAIMER 专节声明 LLM 数据外发风险（目标信息/凭据可能经第三方 LLM 留存）——对"渗透数据进云模型"的隐私后果有正式披露，同类罕见。

## 2. 架构总览

```
WebUI/API（agentic/api.py 3041）── 项目工作区 /workspace/<projectId>/
   ▼
主 Agent（orchestrator 1468 + prompts/base.py 2897：REACT 系统提示 + 阶段定义 + 工具注册表 + 模式决策矩阵）
   ├─ 意图分类器（classification.py：LLM 选攻击技能+阶段；只注入已启用技能段）
   ├─ Fireteam（deploy_fireteam 2-N 专家 fork-join："并行推理而非仅并行工具调用"）
   ├─ 工具层（tools.py 2530：query_graph/web_search/cve_intel/tradecraft_lookup/proxy_*/
   │   execute_*（nmap/nuclei/hydra/ffuf/…）/metasploit_console/kali_shell/execute_code/playwright…）
   ├─ stealth_rules.py（250 ★：逐工具四档限制矩阵，见 §4.1）
   └─ Neo4j 知识图（recon 管线实时写入；agent 以 query_graph 查询为第一优先）
CypherFix：TriageOrchestrator（静态 Cypher 九查询收集→LLM ReAct 关联/去重/加权定级→存库）
          → CodeFixAgent（克隆仓库+11 工具 github_*+八语言运行时；编辑→测试→PR）
MCP servers / Kali 沙箱 / TrafficMind（mitmproxy 捕获）/ AI Gauntlet（对自身 LLM 界面的进攻测试）
```

## 3. 目录结构逐层解读

```
agentic/
├── prompts/ base.py(2897 ★) classification(394) tool_registry(1097) stealth_rules(250 ★)
│            post_exploitation(138) + 14 个漏洞类提示包（xss 685/xxe 249/sql 541/ssrf/rce/
│            path_traversal/http_smuggling/phishing/dos/access_control/brute_force/cve_exploit/unclassified）
├── cypherfix_triage/（orchestrator 526 ★：静态收集+ReAct 分析混合） prompts/cypher_queries
├── cypherfix_codefix/（orchestrator 627 + prompts/system 114 ★ + tools/ 11 个 github_* 工具）
├── api.py(3041) tools.py(2530) state.py(2068) orchestrator.py(1468) websocket_api(1934) workspace_fs(1632)
├── skills/（recon-ai-enrichment/llm-provider-integration 等开发者技能） community-skills/（12 个攻击知识 MD）
recon/（并行多工具管线→Neo4j） mcp/ servers/ graph_db/ tooling/deploy/ docs+wiki
```

## 4. 核心模块精读（审计主体；大仓亲读计划：提示词基础设施+双 orchestrator+stealth 全文）

### 4.1 Stealth 模式规则（stealth_rules.py 250 行全文亲读）——全景观最细的 OPSEC 提示词工程

- **逐工具四档限制矩阵**：NO RESTRICTIONS（query_graph/web_search/cve_intel/tradecraft_lookup/subfinder/gau 等被动源）→ RESTRICTED（curl 单请求+真实 UA、nuclei 禁 dos/fuzz/intrusive 标签+限速 5rps、proxy_replay 单次重放、guarddog 只许小批量——理由注明"会暴露出口 IP"）→ HEAVILY RESTRICTED（**nmap 仅 -sV 于图中已知开放端口+禁 -T4/-A/-sC**、naabu 仅被动、amass 必须 -passive、katana -rl 2 -d 1 -c 1、**metasploit 禁全部 scanner 模块与 reverse payload——需要会话时只用 bind_tcp、每目标最多 2 次利用尝试**、wpscan 必须 throttle+随机 UA）→ FORBIDDEN（hydra/arjun/ffuf/DoS/proxy_fuzz，逐工具给出噪声量级理由："arjun 每	URL 数百至数千请求"）。
- **阶段规则**：利用阶段"单请求利用、>3 个 HTTP 请求触发即 STOP"；后渗透阶段**只读命令白名单**（whoami/id/cat 指定文件），禁持久化/横移/提权/文件修改。
- **STOP 条件清单 + ask_user 协议**（"什么做不到 stealthy、为什么、有什么替代"）。
- **每条 thought 强制前缀 stealth 风险评估**："STEALTH RISK: LOW|MEDIUM|HIGH — 理由"，HIGH 必须论证无更低风险替代——把风险评估做进推理格式的强制字段。

### 4.2 主提示词基础设施（base.py 2897 结构+关键段亲读）

- **Workspace Layout 块恒定注入 think-step 系统提示顶部**——注释明言成本收益（"约 300 token 换稳定心智模型，否则 agent 会把发现写错位置"）；上传文件节按需追加（~100 token）。
- **工具可用性表按阶段过滤渲染**（build_tool_availability_table）+ "Current phase allows" 汇总行防误导。
- **静态前缀与动态节的哨兵分界**（opaque sentinel）；MODE_DECISION_MATRIX 按当前模式渲染。
- **Fireteam 块**："并行的是推理（每个专家跑自己的 ReAct 循环），不只是并行工具调用"；使用前置条件含"确认前一波未覆盖同一 scope（检查 chain context 里的 (from <specialist>) 标签）"。
- 阶段定义里嵌反滥用规则："**凭据侦察是一次查询检查，不是一个阶段**"。
- 意图分类器（classification.py）：逐技能段落各带 "Key distinction" 消歧（如 brute_force vs access_control："只有确实需要发现真实凭据才选爆破，可用请求形状/信任逻辑绕过的登录是认证绕过——**凭据猜测是最后手段**"）；只注入已启用技能（提示词大小随配置伸缩）。

### 4.3 CypherFix 分诊（triage orchestrator + 系统提示头亲读）

- **混合两阶段**："Phase 1 静态收集（9 条硬编码 Cypher 查询，零 LLM）→ Phase 2 ReAct 分析（LLM 关联/去重/排序）"——**确定性收集在前、LLM 只做关联判断**（与 guardian-cli 排序器/T3MP3ST 引文核验同族分工）；重跑分诊先取既有 remediation 防重复。
- **定级算法直接编码进提示词**：14 信号加权表（CHAIN_EXPLOIT_SUCCESS 1200 / CONFIRMED_EXPLOIT 1000 / CISA_KEV 800 / SECRET_EXPOSED 500 / DAST_CONFIRMED 150 / CVSS×10 …），Priority=MAX−总分——**LLM 执行的仍是确定性算法而非自由裁量**。
- 系统提示带 UNTRUSTED_OUTPUT_GUIDANCE（prompt_safety 模块——图数据进提示的注入防护，与 guardian-cli 同型）。

### 4.4 CodeFix 修复代理（prompts/system.py 114 行全文亲读 + 工具集）

- 环境声明：**八语言运行时**（Node20/Py3.11/Go1.22/Java21/Ruby3.3/PHP8.4/.NET8/gcc）+ 11 个 github_* 工具（glob/grep/read/edit/write/bash/list_dir/symbols/find_definition/find_references/repo_map——**tree-sitter 符号级导航**）。
- 工具规则军规："**编辑前必读**；old_string 必须唯一否则带上下文；必须逐字存在否则重读；保留精确缩进；失败重读再试"；"github_repo_map 先行 unfamiliar 仓库"。
- **发现描述与证据以 wrap_untrusted 包裹注入**（FINDING/EVIDENCE 标签）——被测应用的输出当不可信内容，防修复代理被注入。
- 安全准则收尾："优先参数化查询而非拼接；输出编码而非输入过滤；白名单而非黑名单；**治根因不治症状**"；diff 走 github_edit 的精确串替换（每块可被人接受/拒绝——HITL 在 diff 粒度）。

### 4.5 执行面（结构登记）

- api.py/tools.py/state.py/websocket_api.py 四件套 >2k 行级；recon 并行管线实时写图；MCP servers+Kali 沙箱；DISCLAIMER 的**LLM 数据外发披露**与"部署最小加固清单"（TLS/回环绑定/强凭据）体现运营严肃度。

## 5. 值得借鉴的设计与技巧

1. **逐工具 stealth 限制矩阵**（四档+精确旗标+噪声量级理由+STOP 条件+ask_user 协议）：OPSEC 从口号变成可执行的提示词工程；"每条 thought 强制 STEALTH RISK 前缀"把风险评估做成推理格式字段。
2. **静态收集先行、LLM 只做关联**：分诊 9 条 Cypher 查询零成本收集、加权定级表写死——LLM 裁量空间被压到"关联/去重"这一真正需要判断的子问题。
3. **stealth 场景下的 bind-only 会话策略**（禁 reverse shell/listener，需要会话用 bind_tcp）——渗透工具语义级约束（比"别做坏事"具体得多）。
4. **wrap_untrusted 包裹被测应用输出进修复代理**——防御链延伸到修复侧（发现文本/证据可能带注入）。
5. 意图分类器的 "Key distinction" 消歧行（尤其"凭据猜测是最后手段"）与按启用配置伸缩的提示词。
6. Workspace Layout 恒定块（300 token 买稳定心智模型）+ 阶段过滤工具表 + Fireteam "并行推理≠并行工具" 前置条件。
7. DISCLAIMER 的 LLM 数据外发专节 + diff 粒度 HITL。

## 6. 局限与改进点

- 74.9k 行单体（api.py 3041/tools.py 2530），模块边界靠目录约定；base.py 2897 行提示词装配与 API 语义耦合。
- 逐漏洞提示包（14 个 ~3.5k 行）未逐行（同构推定，xss/sql 已抽样）；codefix/triage orchestrator 主体经函数清单+关键段确认，未全文。
- stealth 约束全在提示词层（无工具执行级强制——对照 T3MP3ST 的 egress scopeViolation 是执行前拦截）；RoE 护栏细节未亲读。
- 加权定级表硬编码于提示词（改权重要改提示）；Fireteam 并行专家的去重靠 "(from <specialist>)" 标签提示而非机制。

## 7. 与其他已审计项目的对比

| 维度 | redamon（本项目） | CyberStrikeAI | buttercup | pentestagent |
|---|---|---|---|---|
| 形态 | **全链路框架（到 PR）** | 平台 | CRS | 工作台 |
| 知识层 | **Neo4j 图+静态 Cypher 分诊** | 黑板双账本 | 图状态机 | ShadowGraph 派生图 |
| OPSEC | **逐工具 stealth 矩阵+thought 前缀** | 提示词军规 | — | — |
| 修复 | **CodeFix 八运行时+PR** | — | 核心能力 | — |
| 判定 | 加权表进提示词 | 提示词自律 | 三重机器闸 | 反幻觉军规 |

它是"从攻击到修复"全链路的产品级样本：buttercup 证明修复可行（AIxCC 赛场）、redamon 把修复做成 GitHub PR 流程；其 stealth 矩阵与"静态收集先行"分诊是两个可独立移植的设计。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `agentic/prompts/stealth_rules.py` | ✅ 亲读全文 | 250/250 |
| `agentic/cypherfix_codefix/prompts/system.py` `diff_format.py` | ✅ 亲读全文 | 114+11 |
| `agentic/cypherfix_triage/orchestrator.py` `prompts/system.py` | ✅ 亲读头/结构 | 90/526 + 系统提示头部（混合两阶段+加权表） |
| `agentic/prompts/classification.py` | ✅ 亲读头 | 70/394（技能段+消歧结构） |
| `agentic/prompts/base.py` | ✅ 结构+关键段 | 分节清单+Workspace/Fireteam/工具表段；2897 行未全文 |
| `agentic/prompts/` 14 个漏洞包 | ✅ 抽样（xss/sql 结构） | 同构推定 |
| `agentic/api.py` `tools.py` `orchestrator.py` `state.py` `websocket_api.py` | ✅ 结构登记 | >10k 行未逐行 |
| `recon/` `mcp/` `graph_db/` `tooling/` `docs/` | ⬜ | 未读/登记 |

## 9. 结论

**RedAmon 的核心实现思路是：把"侦察-利用-修复"做成 Neo4j 知识图驱动的全链路产品——多工具并行侦察实时建图，主 agent 按阶段与意图分类在图上推理（Fireteam 以独立 ReAct 循环并行专家），stealth 模式用逐工具四档限制矩阵+强制 thought 风险前缀把 OPSEC 压进推理格式；分诊走"静态 Cypher 收集零 LLM→LLM 只做关联去重→硬编码加权表定级"，修复由 CodeFix 代理在八语言运行时里以 tree-sitter 导航工具改码并开 PR，被测应用输出全程 wrap_untrusted 防注入。** 它是已审 26 项中链路最长（首包到 PR）且 OPSEC 提示词工程最细的框架：stealth 矩阵与"确定性收集+受限裁量"分诊是两个高移植价值设计；约束全在提示词层（无执行级强制）与 75k 行单体是其主要工程债。

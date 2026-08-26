# CyberStrikeus/CyberStrike 逐行代码审计

> 审计对象：CyberStrike —— **"第一个开源进攻安全 AI agent"**（AGPL-3.0，npm @cyberstrike-io/cyberstrike，22 语言 README）：终端 TUI 形态的自主红队 agent——**7,656 个 SKILL.md 技能文件**（19 攻击方法论+CIS 基准逐条+NIST/MITRE 全库+后渗透五平台，**Ed25519 签名+chains_with 链接元数据**）、**13+ 代理**（五域专员+**8 个流量拦截代理测试器带 3-gate 确认协议**）、HackBrowser 内置浏览器双模式捕获（手动/自主多账户爬取角色差异）、150+ AI 提供商、**Liyakat 评分的方法论引擎**、Bolt 远程执行与 winhook 后渗透工具集（提权/持久化/凭据各 5k+ 行）。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/CyberStrikeus/CyberStrike |
| 本地路径 | `repos/agents/CyberStrike/`（Windows 怪癖仓解包；**勿与已审 Ed1s0nZ/CyberStrikeAI 混淆**） |
| 审计基线 commit | `17f82a41`（merge main） |
| 语言 / 规模 | TypeScript/Bun ~169,400 行（14 packages monorepo）+ **7,656 SKILL.md**（.cyberstrike/skill） |
| Landscape 定位 | 类型：渗透 Agent / Stars：高 / 一句话：7.6k 技能+13 代理的终端红队平台（3-gate 代理测试+签名技能+方法论引擎） |
| License | AGPL-3.0 |
| 关联论文 | 无（docs.cyberstrike.io） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：把你的 LLM 订阅（Claude/GPT/任意）变成自主红队 agent——终端 TUI 一键切换域专员，浏览即测试（拦截流量自动进 8 测试器管线）。
- **AI 真伪核查**：真 AI（150+ 提供商 5,300+ 模型声明；代理系统提示在 packages/cyberstrike/src/agent/prompt/ 文件树）。
- **差异化定位**：**技能规模与方法论工程**：7.6k 签名技能（含 CIS 基准逐控制条目化）+ 代理测试器的 3-gate 协议 + Liyakat 评分的委派简报——知识资产密度与流程治理双高。

## 2. 架构总览

```
TUI（Tab 切换 13+ 代理：cyberstrike 主/web-application/mobile/cloud-security/
     internal-network + explore/GHOST 等；/hackbrowser 命令）
packages/ monorepo ×14：cyberstrike（核心：agent/prompt/ 文件树提示+tool/winhook/
     hackbrowser-subprocess）/app/console/ui/sdk（v2 生成 SDK 7k+行）/hackbrowser/
     containers/enterprise/extensions/function/identity/plugin/script/slack/util
.cyberstrike/：cyberstrike.jsonc（provider+mcp 配置）+ skill/ ★7,656 个 SKILL.md
  ├─ attack-*(19)：ssrf/ssti/jwt/smuggling/cache-poison/race/graphql/原型污染/
  │   websocket/xxe/subdomain-takeover/host-header/open-redirect/cors/idor-automation…
  ├─ *-postexploit(5)：aws/azure/gcp/k8s/+winhook 工具（privesc 5,570/persistence 5,402/
  │   credential 5,208 行 TS——Windows 后渗透三件套）
  └─ CIS_benchmarks（AWS/Azure/GCP/K8s 逐控制条目）+NIST+MITRE 全库+AD/kerberos/ebpf/cicd…
Bolt：远程工具执行；MCP 生态（176+ 工具）；Slack 集成；22 语言 README
```

## 3. 核心模块精读（审计主体；169k 行大仓亲读计划：代理提示+技能样本+测试器协议）

### 3.1 主代理提示（cyberstrike.txt 头 40 行亲读）

- "你是 CyberStrike——AI 驱动进攻安全 agent 与自主渗透平台"；直接执行（bash 跑安全工具/浏览器/文件/OSINT/利用开发/报告）+代理编排双模。
- **代理花名册带代号与原型**：STRIKER（web，aggressive）/AURORA（cloud，systematic）/PHANTOM（network，patient）/CIPHER（mobile，methodical）/**INTERCEPTOR**（proxy 流量编排+OWASP LLM Top 10 测试）/GHOST（explore，stealthy）——**人格化代号+性格原型+强项三元组**（对照 pentest-ai-agents 的纯路由描述）。
- **方法论引擎注入 Agent Delegation Briefing**（实时表现数据+分数+建议）+**Phase-to-Agent 决策表**（scope_analysis→GHOST 等）——"Liyakat 评分"驱动委派（评分细节在 methodology/ 未深读）。

### 3.2 流量拦截编排（orchestrator/web-proxy-agent/prompt.txt 头亲读）

- **纯编排者契约**："你**不**自己测漏洞——MUST NOT 清单：不发测试 HTTP 请求/不跑安全工具/不直接 report_vulnerability/不测给定之外的端点/**不创建凭据（凭据只来自浏览器扩展）**/不遵循僵硬静态路由而做智能分析"——六禁令的职责收窄。
- 凭据上下文自动注入（credential_id/label/container_id/headers/role_id——"浏览器扩展自动捕获"）；**re-test 队列**（新发现触发旧端点重测）+**new 发现的 triage 职责**（跨测试器视角判重：approved/duplicate+duplicate_of）。

### 3.3 8 个代理测试器与 3-gate 协议（README+authz/prompt.txt 亲读）

- **3-gate confirmation protocol**："执行基线请求→执行攻击→比较响应——**只有可测量可复现的差异才报告发现，不凭猜测**；同端点+同向量的重复发现跨会话自动抑制"——差分验证进流量测试器的最小协议（对照 ptai 的 oracle：方向一致，强度低一档）。
- authz 测试器提示：四步流程（web_get_session_context 查角色层级/凭据/端点-函数映射→理解层级→识别保护端点→执行测试）；**三型测试模板**（垂直提权/水平提权/认证绕过各带 Target/Test with/Expected/Vulnerable 四行结构）。

### 3.4 技能系统（attack-ssrf/SKILL.md 亲读+清单）

- **frontmatter 元数据链**：name/description/category/tags/tech_stack/**cwe_ids**（CWE-918）/**chains_with**（attack-xxe/attack-ssti——技能间组合关系声明）/**severity_boost**（"SSRF via XXE=file read+内网扫描"/"SSRF from SSTI=full RCE 链"——**链式加成的量化描述**）——技能不是孤文档而是**带组合语义的图**。
- **7,656 规模的构成**：方法论 19+后渗透 5+合规框架（**CIS 基准逐控制条目**——AWS Foundations 2.1.1 到 2.12 每条一个 SKILL）+领域知识；**Ed25519 签名**（防篡改）+惰性加载（一次一个按需静态注入）。
- HackBrowser 双模式：手动（人浏览捕获真实 API 流量）/**自主**（给多账户凭据自动登录爬取，**捕获角色间流量差异**——访问矩阵的黑盒推导）。

## 4. 值得借鉴的设计与技巧

1. **技能图元数据**（chains_with+severity_boost+cwe_ids 进 frontmatter）——知识文件带组合语义；CIS 基准逐控制条目化是合规知识的正确粒度。
2. **3-gate 确认协议**进流量测试器（基线/攻击/差分+重复抑制）——被动流量场景的验证最小协议。
3. **纯编排者六禁令**+re-test 队列+跨测试器 triage（判重职责归编排者——它有全图视野）。
4. **代理代号+性格原型**（STRIKER aggressive/PHANTOM patient）——人格化路由的记忆点设计。
5. HackBrowser 自主多账户爬取的角色差异捕获；凭据只出自浏览器扩展的单一来源纪律。
6. Liyakat 评分的实时委派简报（表现数据进系统提示）。

## 5. 局限与改进点

- 169k 行仅提示树+技能样本+README 深读（winhook 三件套 16k 行后渗透工具与方法论引擎未逐行）；"7,600+ 技能"的大头是 CIS/MITRE 条目化（机器生成痕迹），攻击方法论本体 19 个。
- AGPL+商业化（cyberstrike.io/enterprise 包）；22 语言 README 的营销面广。
- 与 ptai/xalgorix 相比验证层为提示词级（3-gate 靠模型执行，无代码强制 oracle）。

## 6. 与其他已审计项目的对比

| 维度 | CyberStrike（本项目） | ptai | Dark-Moon | pentest-ai-agents |
|---|---|---|---|---|
| 技能 | **7,656 签名+图元数据** | oracle 库 | 50 技术栈 | 52 人格 |
| 流量测试 | **8 测试器+3-gate** | held back | — | — |
| 编排 | **纯编排者六禁令+triage** | LLM 协调 | OpenCode | CI 校验 |
| 浏览器 | **HackBrowser 双模式** | — | — | — |
| 验证 | 提示词级 | **代码级 oracle** | 状态资格 | scope 块 |

与 ptai 同日审计成对：**知识密度极端（7.6k 技能）vs 验证强度极端（代码 oracle）**——"知道得多"与"证明得硬"的两极；与 Dark-Moon/pentest-ai-agents 构成宿主技能生态的又一变体（签名+图元数据是新增量）。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `packages/cyberstrike/src/agent/prompt/cyberstrike.txt` | ✅ 亲读头 | 40/~? 行（花名册+决策表） |
| `agent/prompt/orchestrator/web-proxy-agent/prompt.txt` | ✅ 亲读头 | 2KB/36KB（六禁令+凭据上下文） |
| `agent/prompt/vuln/authz/prompt.txt` | ✅ 亲读头 | 40 行（四步+三型模板） |
| `.cyberstrike/skill/attack-ssrf/SKILL.md` | ✅ 亲读头 | frontmatter 图元数据全文 |
| `.cyberstrike/skill/`（7,656 文件） | ✅ 清单+构成分析 | 41 顶级目录 |
| `packages/` 其余（winhook/hackbrowser/sdk 等 14 包） | ✅ 结构登记 | 未逐行 |
| `README.md` | ✅ 亲读 | 代理表/技能表/3-gate/HackBrowser |

## 8. 结论

**CyberStrike 的核心实现思路是：以签名技能图与流量测试管线为核心的终端红队平台——7,656 个 Ed25519 签名技能（frontmatter 带 chains_with/severity_boost/CWE 组合语义；CIS 基准逐控制条目化）惰性注入 13+ 域代理（代号+性格原型花名册+Liyakat 评分实时委派简报），浏览流量经 HackBrowser（手动/自主多账户角色差异爬取）进入纯编排者（六禁令+re-test 队列+跨测试器 triage）调度的 8 个代理测试器，每个测试以 3-gate 基线/攻击/差分协议出发现。** 它是知识资产规模的现役极点（技能图元数据与 CIS 条目化是两个可移植设计），与同日审计的 ptai 构成"知识密度 vs 验证强度"的两极对照——验证为提示词级是其已知边界。

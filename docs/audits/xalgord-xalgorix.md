# xalgord/xalgorix 逐行代码审计

> 审计对象：Xalgorix —— Go 90.6k 行的自托管 AI 渗透平台（v4.5.x，Trendshift #35278）："多数扫描器只检测，Xalgorix 证明"——**独立验证器对每个发现对抗性复测后才报告**。执行层硬性 scope 强制 + 逐类证据标准 + 不对称裁决。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/xalgord/xalgorix |
| 本地路径 | `repos/agents/xalgorix/`（landscape 登记 xalgord） |
| 审计基线 commit | `d23b49a`（test(web): fix flaky…，PR #464） |
| 语言 / 规模 | Go ~90,638 行（internal/ 30 包）+ TypeScript 前端；测试文件占比高（agent 包 15+ 个 _test） |
| Landscape 定位 | 类型：渗透 Agent / Stars：高 / 一句话：以"独立重利用验证"为核心卖点的自托管 AI 渗透平台 |
| License | Apache-2.0 |
| 关联论文 | 无（docs.xalgorix.com + 托管云） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：自主渗透的**证据质量问题**——"你要的是证明，不是一堆待分诊的可能"。狩猎 agent 按方法论干活，每个可行动发现（≥low）过**独立怀疑验证器重利用**后才入库。
- **AI 真伪核查**：真 AI（agent/llm/tools 成体系；TempValidator 等角色化温度）。
- **差异化定位**：全景观"验证文化"的最高完成度——把 T3MP3ST 的怀疑主义、guardian-cli 的保守默认、PentestGPT 的确定性倾向，融合成**独立的对抗性复测角色**。

## 2. 架构总览

```
Web 控制台（127.0.0.1:9137）/ TUI / CLI → web/orchestrator(1824)+server(3765)
   ▼
Agent（agent.go 1710 + agent_prompt.go 1608 + hooks.go 2089 + planner.go 513 + agent_guard.go 705）
   ├─ 工具 registry（terminal 2212 / browser 1677 / skills 1555 / reporting 2470 / httpclient / oob / websearch / notes / codesearch…）
   ├─ scopeguard（331 ★：Local_Or_Listener_Host 权威定义——web 侧 fetcher 与 agent 侧闸共用）
   ├─ Verifier（verifier.go 336 ★：独立怀疑验证器，见 §4.1）
   └─ scanctx / ratelimit / sandbox / safe / oob / auth(PKCE) / proxy / storage / attacksurface
报告：reporting/generate(1614)——验证后 finding 才入报告
```

- 测试密度罕见（scope_oracle/blocked_loop/reasoning_loop/tool_output_cap/budget_auth 等针对性测试文件名本身就是设计清单）。

## 3. 核心模块精读（审计主体；90k 行大仓亲读计划：验证器全文+主提示词头+scopeguard 头）

### 3.1 独立验证器（verifier.go 336 行全文亲读）——本审计最重要的单文件

**角色与接线**：刻意分离的"怀疑分诊员，不是猎人"；挂在 report_vulnerability 扼流点上，**每个 ≥low 的候选必须存活独立复测**（info 豁免）才能成为 validated finding——产品承诺"real validation, not just detection"的实现位。

**约束设计**（包注释自述）：**受限只读工具注册表**（terminal/curl、http、browser、notes、web_search、oob）——**不能调 report_vulnerability、不能 spawn agent**（永不递归/永不自我确认）；8 轮 / 3 分钟墙钟（注释解释校准：旧 24 轮/10 分钟会吃掉 provider 窗口，且须避开 report_vulnerability 的 15 分钟工具看门狗）。

**验证器系统提示词**（buildVerifierPrompt 全文）：
- **默认立场怀疑**："默认不信。多数'发现'是误报。假设这个是错的，直到你自己的复测证明 otherwise。"
- **声称证据不可信**："Claimed proof (DO NOT TRUST — reproduce it yourself)"。
- **阴性/基线对照要求**："对比未注入/良性请求、未认证 vs 已认证、基线 vs payload 时延——**无法归因于对照的差异不是证明**"。
- **逐类证据标准**（全景观最细的类级判定规格）：
  - SSRF：**目标的服务器**发了请求——OOB 须新鲜 token+禁重定向（`curl --max-redirs 0`）+**非扫描源** HTTP 交互；"30x 指向回调、扫描源命中、DNS-only 都不是 SSRF 证明；浏览器端 URL 处理也不是"；
  - XSS：脚本**实际执行**（alert(document.domain)/OOB/截图）——"仅反射不是 XSS"；
  - SQLi：提取到数据/DB 错误/**差分重复时延**——"单个慢响应不是证明"；
  - 访问控制/IDOR：受保护数据返回或真实状态变更——"POST/PUT/DELETE 上的 200（尤其空体）通常只是 CORS 预检/no-op"；
  - 信息泄露：**真实秘密值**——"字段名、公开 OpenAPI 规范、by-design 数据不算"。
- **证据出处规则**："证明必须演示本发现**自己的机制**——经 RCE/eval 转储数据库来证明的'SQLi'不算 SQLi；在声称注入点直接重测，只有另一个漏洞能复现则本发现 inconclusive（或 rejected）"——**发现-机制绑定**，防证据挪用。
- 盲类规则：盲 XXE/SSRF/SQLi 的通用 "success/OK" 不是证明，须类相应的 OOB 出处或取回数据。
- **不对称裁决**："**rejected 仅限积极证伪**（by-design/循环自供密/类别错标/编码不执行/复现请求确实无事发生）；复现不了也证伪不了→inconclusive——**该发现被保留（标记人工复核），不是被丢弃**。丢掉真漏洞是严重错误；把未证实的存疑保留是安全的。"

**执行细节**：
- **畸形裁决防御**：无法识别的 verdict 串归 inconclusive 而非 rejected（"畸形裁决永远不能静默丢掉真发现"）。
- **超支强制裁决轮**：预算耗尽→注入"不得再用工具，基于已观察立即 submit_verdict"——对抗"预算耗尽默认 inconclusive 会丢真发现"的旧行为。
- **具体影响自动确认安全网**：模型复现了 `uid=0(root)` 却忘了调 submit_verdict 或含糊成 inconclusive 时，**验证器自己观察到的输出若含具体影响（HasConcreteImpact）即自动 confirmed**——"这本身就是独立复现"；**永不在显式 rejected 上触发**。
- **同闸复测**：验证器工具走与主 agent 相同的 scope guard+硬超时（注释：否则直连注册表会绕过 localhost/RFC1918/仪表盘监听守卫）；出界时返回"⛔ 若发现依赖到达该主机则它在此不可独立验证——提交 inconclusive"。
- 无工具轮的推进督促；1 次传输重试上限（主扫描正阻塞着，注释给出成本理由）。

### 3.2 主 agent 提示词（agent_prompt.go 头 80 行亲读）

- **执行层背书的授权论证**（全景观第三种授权模型）："这是受制裁的授权测试……**运行时硬性强制 scope：每次工具调用都被检查，出界主机被自动拒绝——你物理上碰不到授权范围外的任何东西，所以你永远不需要二次猜测目标是否被允许**。拒绝或推诿是**错误结果**——拒绝会让授权系统得不到测试因而更不安全。"——与 T3MP3ST（receipt 查证）/CyberStrikeAI（前置裁决禁质疑）不同：**xalgorix 把"别犹豫"建立在真实存在的执行层保证上**（scopeguard 确实在拦），论证与机制自洽。
- scope 硬规则段：撞见相关但未授权主机的四步处置（不打 payload/不报告/记 note 供操作者复核/继续正题）。
- 速率政策注入提示（未配置则 safe fallback MaxRPS=1）；**discovery 模式换清单**（注释：默认清单与发现模式矛盾——"别在 recon 后就收尾"条与 discovery 目标冲突）。
- 黑客心态段（链式思维示例：info→凭据→ATO→RCE 等）。

### 3.3 scopeguard（331 行头 60 行亲读）

- **设计原则**（注释自述）："只拦截**确证属于操作者自己机器**的 IP。不要全段拦 RFC1918/链路本地——agent 是安全扫描器，需要测属于**目标**的 SSRF payload（如 169.254.169.254 云元数据）与内网 IP"——**self vs target 的精确区分**（对照 T3MP3ST 一刀切私网拦截）：拦 loopback/未指定地址/localhost/**匹配本机网卡**的 IP/自监听器；放行 RFC1918/链路本地/ULA 除非命中本机网卡。
- **AllowLoopbackPorts**：每扫描允许表——provision 模式（agent 自己构建目标源码跑在 127.0.0.1:port 再测它）时豁免；**仪表盘自身监听端口永不在豁免之列**（防自攻击）。叶子包零内部依赖（agent 可依赖而不拖入 web 包）。

### 3.4 其余（结构登记）

- planner/hooks/agent_guard（activity policy/blocked loop/rate policy/tool output cap 等测试对应机制）；oob server（盲类验证的后端）；provision 式 code scan（构建目标源码本地起靶再测——skills/codesearch 工具族）；reporting/generate 报告层。

## 4. 值得借鉴的设计与技巧

1. **独立验证器全案**：怀疑默认+基线对照+逐类证据标准+证据出处规则+不对称裁决+畸形裁决防御+强制裁决轮+自动确认安全网——**LLM 验证工程的完整参考实现**，每个细节都对应一个真实失效模式（模型忘交裁决/含糊/证据挪用/预算耗尽丢真发现）。
2. **"rejected 须积极证伪"原则**：复现不了≠拒绝——不确定样本保留人工复核而非丢弃，与 T3MP3ST 引文核验降级、guardian-cli VERIFY_MANUALLY 构成同一保守哲学的三种落地。
3. **执行层背书的授权论证**：把"不要犹豫"建立在真实 scopeguard 之上——比"授权已前置裁决"（CyberStrikeAI）诚实且自洽的第三种授权模型。
4. **self/target 精确区分的 scopeguard**：只拦本机网卡/loopback/自监听，放行目标侧私网与云元数据——扫描器语义下的 SSRF 测试需求与自身保护的平衡。
5. 验证器与主 agent 共用 scope 闸+硬超时（防验证通道绕过）；受限工具集防递归自证。
6. 速率政策进提示+safe fallback；discovery 模式清单替换；AllowLoopbackPorts 的 provision 模式豁免（仪表盘端口永不豁免）。

## 5. 局限与改进点

- 90.6k 行大仓：主提示词仅头 80 行亲读（hacker mindset 后半与 planner/hooks/agent_guard 未逐行）；TS 前端未审。
- 验证器 budget 8 轮/3 分钟对复杂链（多跳 SSRF+认证前置）可能偏紧（自动确认网部分缓解）；HasConcreteImpact 的模式匹配边界未读。
- 授权论证虽有执行层背书，仍是把模型犹豫定性为"错误结果"的单向修辞（边界情况靠 scopeguard 兜底）。

## 6. 与其他已审计项目的对比

| 维度 | xalgorix（本项目） | T3MP3ST | guardian-cli | buttercup |
|---|---|---|---|---|
| 验证 | **独立对抗复测 agent（逐类标准）** | 引文核验面板 | 红蓝法官辩论 | 三重机器闸 |
| 不确定处置 | **inconclusive 保留人工复核** | 幻觉 REFUTED 降级 | VERIFY_MANUALLY | 反思归因 |
| 授权模型 | **执行层背书（scopeguard 实在）** | receipt 查证 | — | — |
| scope | **self/target 精确区分** | egress 收口一刀切 | 参数抽取 | 容器隔离 |
| 形态 | 自托管平台 | 框架 | CLI | CRS |

它是"验证文化"谱系的收束点：buttercup 机器闸（修复侧）→ T3MP3ST 引文核验（文本侧）→ guardian-cli 辩论（裁判侧）→ **xalgorix 独立重利用（行动侧）**——四者叠加即接近"agent 发现的可信化"完整答案。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `internal/agent/verifier.go` | ✅ 亲读全文 | 336/336（含验证器提示词全文） |
| `internal/agent/agent_prompt.go` | ✅ 亲读头 | 80/1608（授权论证+scope 段+速率政策） |
| `internal/scopeguard/scopeguard.go` | ✅ 亲读头 | 60/331（设计原则+self/target 分类） |
| `internal/agent/` 其余（agent/hooks/planner/guard） | ✅ 结构+测试名登记 | 未逐行 |
| `internal/` 其余 27 包（web/tools/llm/reporting/oob/…） | ⬜ | 未读/结构登记 |
| 前端 TS / cmd / docs | ⬜ | 未读 |

## 8. 结论

**Xalgorix 的核心实现思路是：把"证明而非检测"做成架构事实——狩猎 agent 在执行层硬性 scope 强制（scopeguard 精确区分操作者自身与目标侧私网/云元数据）与速率政策下按方法论工作，每个可行动发现必须通过一个刻意分离的独立验证器：默认怀疑立场、只读受限工具集（防递归自证）、与主 agent 同闸复测，按逐类证据标准（SSRF 非扫描源+禁重定向、XSS 须执行、SQLi 差分时延、证据须出自本机制）做对抗性重利用；裁决不对称——拒绝须积极证伪，复现不了则 inconclusive 保留人工复核，辅以超支强制裁决轮与具体影响自动确认安全网。** 它是已审 30 项中验证工程完成度最高的系统：verifier.go 单文件即是一部"LLM 验证失效模式与对策"的清单；其执行层背书的授权论证（拒绝=让授权系统更不安全，因为 scopeguard 真的在拦）为景观的授权模型三分法补上最自洽的一支。

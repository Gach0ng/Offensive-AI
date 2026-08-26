# arthurgervais/mapta 逐行代码审计

> 审计对象：mapta —— 单文件（main.py 1,105 行）+分析脚本（analyze_logs.py 1,089 行）的**三层代理扫描器**：主代理（gpt-5+reasoning high）编排 → **sandbox_agent/validator_agent 作为工具**（子代理降级到沙盒双工具防递归嵌套）+ **邮箱消息读取与 Slack 告警即工具**（真实工作流集成）；XBOW 100+ 题全套运行日志（metrics+trace）与论文级分析产物入库。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/arthurgervais/mapta |
| 本地路径 | `repos/agents/mapta/` |
| 审计基线 commit | `0c167b8`（init——单提交仓库） |
| 语言 / 规模 | Python ~2,194 行（main 1,105+analyze 1,089）+ ctf-logs（XBOW 全套 trace/metrics 与分析图表 PDF/PNG/tex） |
| Landscape 定位 | 类型：渗透 Agent / Stars：中低 / 一句话：三层代理 gpt-5 扫描器（子代理即工具+Slack/邮箱工作流集成+日志分析产物入库） |
| License | MIT |
| 关联论文 | 无（分析产物达论文图表级：Sankey/成本/时间 CDF/命令使用/成功相关性） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：面向真实安全运营的扫描——主代理读目标站邮箱（注册邮件/验证邮件/重置邮件→凭据材料）、在沙盒执行探测、把发现以结构化告警推 Slack 并线程化汇总。
- **AI 真伪核查**：真 AI（gpt-5 全程 reasoning effort=high；三层代理各独立会话循环）。
- **差异化定位**：**工作流原生集成**（邮箱+Slack 是 agent 的一等工具而非人机接口）+ 单文件极简 + 日志分析产物达出版级。

## 2. 架构总览

```
run_continuously（主循环：developer 系统提示+user 目标→gpt-5 responses API+7 工具并行执行）
主代理工具面（高阶）：sandbox_agent / validator_agent（子代理即工具★）
                  get_registered_emails / list_account_messages / get_message_by_id（邮箱三件套）
                  send_slack_alert / send_slack_summary（Slack 二件套：严重度色映射+thread_ts 线程化）
   ▼ 子代理（受限工具面：仅 sandbox_run_command + sandbox_run_python——防递归嵌套）
sandbox_agent（默认 100 轮：自主交互沙盒） / validator_agent（默认 50 轮：PoC 验证四步）
沙盒层：thread-local sandbox 实例（env SANDBOX_FACTORY="module:function" 工厂注入——
       files.write/commands.run(user,timeout)/kill；100 行裁剪）
UsageTracker（main/sandbox 双轨 token 记账→metrics.json）；analyze_logs.py（1089 行事后分析）
```

## 3. 核心模块精读（审计主体：main.py 关键段亲读）

### 3.1 三层代理与工具降级

- **主代理**：`client.responses.create(model="gpt-5", reasoning={"effort":"high"})` + 七个高阶工具；每轮 function_calls **并行执行**（asyncio.gather）；系统提示与目标经 env/参数注入。
- **sandbox_agent**（嵌套代理循环，默认 100 轮）：系统提示（可 env 覆盖）默认"你用 sandbox_run_command(bash) 与 sandbox_run_python(Python) 自主交互隔离沙盒；**响应控制在 30,000 字符内、大输出分块**；行动前逐步思考"——**工具面过滤到仅两个沙盒原语**（"Restrict to the low-level sandbox tools to avoid recursive nesting"——子代理不得再调子代理）。
- **validator_agent**（默认 50 轮）：**PoC 验证专用**——四步契约："①最小且安全地复现 PoC ②捕获证据（stdout/文件 diff/HTTP 响应）③**判定 PoC 是否可靠演示了有影响的真实漏洞** ④给出简明裁决；除非验证必需避免破坏性动作"——验证角色的又一轻量实现（主代理写发现的反面：独立子代理在沙盒里重放）。

### 3.2 工作流原生集成（邮箱+Slack 即工具）

- **邮箱三件套**：get_registered_emails / list_account_messages(email, limit=50) / get_message_by_id——主代理可自主翻阅目标站账户邮件（验证码/重置链接/token 提取），扫描循环内完成凭据获取。
- **Slack 二件套**：send_slack_security_alert（vulnerability_type/severity/target_url/description/evidence/recommendation/**thread_ts 线程回复**——同目标发现汇入一线程）+ send_slack_scan_summary；severity→颜色映射（Critical 红→Info 蓝）——**发现即告警的工作流闭环**（对照 pentest-copilot 的 Mythic/告警：这边 Slack 为中心）。
- UsageTracker：main/sandbox 双轨逐调用记账（target_url 归属）→metrics.json。

### 3.3 沙盒工厂与日志分析

- 沙盒经 env 工厂注入（"sanitized for open release"注释——内部实现剥离，公开版只剩接口契约：files.write/commands.run/kill/set_timeout）；线程本地隔离（多目标并行扫描各持沙盒）；输出 100 行裁剪。
- **analyze_logs.py（1,089 行）+ ctf-logs/**：XBOW 100+ 题全套 trace.log+metrics.json 与**论文级分析产物**（Sankey 图/成本分析/时间 CDF/命令使用表 tex/工具使用/成功相关性/summary 表）——**数据→图表的完整分析管线在库**（对照 cochise 的 analysis 脚本与 BoxPwnr 的 traces：这边直接产出出版级 PDF/PNG）。

## 4. 值得借鉴的设计与技巧

1. **子代理即工具+工具面降级防递归**：主代理调 sandbox_agent/validator_agent 如调普通函数；子代理只见两个沙盒原语（"避免递归嵌套"注释直书动机）——**嵌套代理的权限锥形设计**（对照 hackingBuddyGPT SubAgentCapability 的能力白名单：这边用"工具面减法"实现）。
2. **工作流原生集成**：邮箱读取与 Slack 告警作为 agent 工具——安全运营的真实工作流（凭据邮件→探测→告警线程）进 agent 循环而非外挂。
3. validator 四步契约（复现/取证/判定/裁决）与"验证必需才破坏"约束。
4. 单文件 1,105 行承载三层代理（对照 Zen-Ai-Pentest 212k 行的密度反面样本）；分析产物出版级入库。
5. 沙盒工厂 env 注入（内部实现剥离的干净开源方式）；30k 字符输出分块与 100 行裁剪。

## 5. 局限与改进点

- 单提交仓库（无演化史）；模型硬编码 gpt-5（无提供商抽象——对照 litellm 系）；user_prompt 样例残留（"workflow code injection"测试痕迹）。
- 沙盒实现剥离后本仓不可直接运行（需自备工厂）；主循环/analyze 未逐行（~1,105+1,089 行中亲读约 400）；无 scope 强制（沙盒即边界）。

## 6. 与其他已审计项目的对比

| 维度 | mapta（本项目） | hackingBuddyGPT | deadend-cli | ctf-agent |
|---|---|---|---|---|
| 子代理 | **即工具+工具面降级防递归** | 能力白名单 SubAgent | supervisor 路由 | 蜂群并行 |
| 工作流 | **邮箱+Slack 原生集成** | OTel | — | CTFd 闭环 |
| 验证 | validator 四步契约 | 双孪生对照 | judge 二判 | 递增冷却 |
| 产物 | **出版级分析图表入库** | JSONL | 基准日志 | 战绩表 |
| 密度 | **1,105 行三层代理** | 18.7k | 41k | 5.1k |

它补上"安全运营工作流"维度：邮箱凭据获取与 Slack 告警线程化进 agent 循环——此前 53 项的发现出口均为文件/平台，这里是**运营信道即工具**。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `main.py` | ✅ 亲读关键段 | ~400/1,105（三层代理/工具注册/邮箱 Slack 工具/主循环） |
| `analyze_logs.py` | ✅ 结构登记 | 产物确认 |
| `ctf-logs/`（XBOW 全套+analysis_output） | ✅ 存在确认 | 未逐个读 |
| `LICENSE` | ✅ 确认 | MIT |

## 8. 结论

**mapta 的核心实现思路是：以单文件三层代理把安全运营工作流压进 agent 循环——主代理（gpt-5 reasoning high）持七个高阶工具，其中 sandbox_agent/validator_agent 本身是子代理（工具面降级到两个沙盒原语防递归嵌套；validator 带"复现-取证-判定-裁决"四步契约），邮箱三件套与 Slack 告警二件套作为一等工具实现"凭据邮件→探测→告警线程"的运营闭环，沙盒经 env 工厂注入（内部实现剥离），XBOW 全套日志经配套分析脚本产出出版级图表。** 其独有贡献是**运营信道即工具**（邮箱/Slack 进 agent 工具面）与嵌套代理的权限锥形设计；gpt-5 硬编码与沙盒剥离是其开源边界。

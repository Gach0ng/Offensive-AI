# 0x4m4/hexstrike-ai 逐行代码审计

> 审计对象：HexStrike AI MCP Agents v6.0 —— 自称 "AI-Powered MCP Cybersecurity Automation Platform"（150+ 工具 / 12+ agent），实为**规则引擎 + MCP 工具服务器**：LLM 智能全部外置于用户自接的 MCP 客户端（如 Claude）。
>
> 审计方法注记：本项目仅两个 Python 文件（server 17,289 行 + MCP 客户端 5,470 行）。核心段（决策引擎主体、错误分类与恢复知识库、执行器、恢复循环、nmap 端点完整范本、CVE 智能/利用生成器样段、MCP 装配）亲读约 1,400 行；其余 155 个 REST 端点**未逐个读**，按结构图与 nmap 范本推定同构（此推定待后续抽样复核）。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/0x4m4/hexstrike-ai |
| 本地路径 | `repos/agents/hexstrike-ai/` |
| 审计基线 commit | `d689933ff579d839c676c82b231f8e98326c5f04`（2026-08-03，readme update） |
| 语言 / 规模 | Python，仅 2 个文件共 22,759 行（hexstrike_server.py 17,289 + hexstrike_mcp.py 5,470） |
| Landscape 定位 | 类型：渗透 Agent（MCP 工具平台）/ 一句话：给外部 LLM 客户端暴露 150+ 安全工具的 MCP 服务器，带规则式工具选择/参数优化/错误自愈 |
| License | MIT（OTT Cybersecurity LLC 所有） |
| 关联论文 | 无 |
| 审计日期 / 人 | 2026-08-24 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：把 150+ 渗透工具（nmap/nuclei/sqlmap/云安全/pwn 工具链）包装成 MCP 工具，让 Claude 等外部 LLM 客户端直接"操作"整个工具箱做渗透/CTF/众测。
- **输入输出**：MCP 客户端调工具（target+参数）→ Flask 端点拼 shell 命令本机执行 → 返回 stdout/stderr/退出码/恢复元数据 JSON。
- **差异化定位**：与 pentagi/strix 这类"自带 agent"的项目相反，hexstrike **不自带智能**——它把"工具调用可靠性"做成产品（缓存、错误分类、自愈重试、工具替代、优雅降级），把"决策"留给外部 LLM。

## 2. 架构总览

```
外部 LLM（用户自接：Claude Desktop / 任意 MCP 客户端）        ← 所有"AI"在这里
   │ MCP (stdio)
   ▼
hexstrike_mcp.py（FastMCP，160 个 @mcp.tool 包装）
   │ HTTP POST（requests → Flask :9000 默认）
   ▼
hexstrike_server.py（Flask，156 个 @app.route）
   ├─ /api/tools/*（150+ 工具端点：参数校验 → f-string 拼 shell 命令）
   ├─ /api/intelligence/*（决策引擎 API：目标分析/工具选择/参数优化/攻击链/智能扫描）
   ├─ /api/bugbounty/* / CTF 工作流 API / /api/files / /api/processes / /api/visual
   ▼
EnhancedCommandExecutor（subprocess shell=True + 双线程读输出 + 进度线程 + 超时杀进程）
   ├─ HexStrikeCache（命令级缓存）  ├─ ProcessManager（进程注册表）
   ├─ execute_command_with_recovery（错误分类 → 恢复策略梯 → 重试/调参/换工具/升级人类）
   └─ TelemetryCollector
```

- **编排方式**：**无编排**——没有 agent 循环、没有状态机、没有 LLM 调用（全库 grep 无 openai/anthropic/litellm import，亲验）。所谓 "12+ AI agents" 是 **CTF/BugBounty 工作流预设**（数据表：类别→工具清单→策略清单）。
- **LLM 调用层**：不存在。决策引擎（IntelligentDecisionEngine，572-1558 亲读）是纯规则：硬编码工具效率评分表（5 类目标 × 20 工具的 0.7-0.97 分值）、16 套攻击剧本（web_reconnaissance/api_testing/network_discovery/…/bug_bounty_high_impact，各带优先级排序的工具+参数链）、启发式目标分类（URL/IP/域名/二进制/云 正则）。
- **执行环境**：**本机直执行**（shell=True，无沙箱无容器）——工具在哪装就在哪跑。

## 3. 目录结构逐层解读

```
hexstrike-ai/
├── hexstrike_server.py   # 一切服务端逻辑（17,289 行单文件）：
│   │                      # ModernVisualEngine(105 ANSI 美术) → 决策引擎(572) → 错误处理/恢复/降级(1606-2438)
│   │                      # → BugBounty/CTF 工作流(2438-4223) → 检测器/优化器/进程池/缓存/CVE智能(4223-6615)
│   │                      # → 执行器/利用模板/恢复循环(6783-8928) → 156 个 Flask 端点(9024-17289)
├── hexstrike_mcp.py      # FastMCP 客户端：160 个工具包装（safe_post → Flask）+ 彩色日志
├── hexstrike-ai-mcp.json # MCP 客户端接入配置
└── requirements.txt      # flask/requests/mcp 等
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 入口与初始化

Flask app + 全局单例装配（cache/telemetry/error_handler/decision_engine/parameter_optimizer/degradation_manager）；MCP 侧 `setup_mcp_server()`（hexstrike_mcp.py:267）逐个注册 @mcp.tool，每个工具=参数 schema docstring + `safe_post("api/tools/<name>", data)` + 彩色日志（含恢复信息/人类升级的提示打印）。`main()` 起 Flask（默认 9000 端口）。

### 4.2 "智能"层的真实形态（README 声称 vs 代码事实）

- **IntelligentDecisionEngine**（572-1558 亲读）：
  - `tool_effectiveness`：5 类目标（Web/API/网络/云/二进制）各 20 个工具的**手写效率评分**（nuclei 对 Web 0.95、wpscan 0.95、arjun 对 API 0.95…）；
  - `attack_patterns`：**16 套剧本**，每套 4-8 步、每步带优先级+完整参数（如 bug_bounty_reconnaissance：amass→subfinder→httpx→katana→gau→waybackurls→paramspider→arjun）——本质是**专家经验的知识库化**；
  - `analyze_target`：正则分类（URL 带 /api/→API；IPv4→网络主机；.exe/.elf→二进制；含 amazonaws.com→云）+ DNS 解析 + "URL 里含 wordpress 字样→WordPress"级别的伪技术检测（注释自认 "simplified version - in practice you'd make HTTP requests"）+ 攻击面打分公式（类型基分+技术数×0.5+端口数×0.3…封顶 10）；
  - `select_optimal_tools`：按目标类型取效率表，objective=quick 取 top3 / comprehensive 取 >0.7 / stealth 取白名单被动工具；
  - `optimize_parameters`：先查号（26 个工具的 `_optimize_*_params` 手写分支，如 nmap 遇高攻击面加 -T4-6），否则走 ParameterOptimizer。
- **README 声称 vs 代码**：**"AI-powered"、"12+ autonomous AI agents" 均无代码对应**——无 LLM import、无 agent 循环；"agents"=工作流数据表。这是六个已审项目里 README 营销与代码事实落差最大的。
- **CTFWorkflowManager**（2795 亲读）：7 类 CTF（web/crypto/pwn/forensics/rev/misc/osint）各 4-6 组工具清单 + 各 6-7 条解题策略清单——纯数据字典。注意其中大量工具（cyberchef、hash-identifier、format-string-exploiter、sage…）**并无对应端点**——剧本引用与实际工具覆盖面不匹配。

### 4.3 工具层与执行链

- **端点样板**（nmap 端点 10327-10377 亲读，其余同构）：`params = request.json` → 取 scan_type/ports/additional_args → **f-string 直拼命令** `command = f"nmap {scan_type} -p {ports} {additional_args} {target}"` → use_recovery 默认 True 走恢复版执行器。**无任何输入转义/白名单**——additional_args 可直接注入任意 shell（作为渗透工具"设计如此"，但服务端对本机 shell 完全敞开，与 cai 的默认主机执行同级风险，且无 cai 的敏感命令确认闸）。
- **EnhancedCommandExecutor**（6783-7003 亲读）：`subprocess.Popen(shell=True)` + 双守护线程逐行读 stdout/stderr（实时打日志）+ 进度线程（>2s 显示 ETA/速度的 ANSI 进度条并回报 ProcessManager）+ 超时先 terminate 后 kill；**"超时但有输出 = 成功"**（:6946 `success = True if self.timed_out and (stdout or stderr)`）——扫描类工具的部分结果即有价值，务实但语义宽泛。
- **命令级缓存**：`execute_command`（8636）成功结果按命令串缓存（重复调用零成本，但也意味着**相同命令不会重新扫描**——对时变目标可能返回旧结果）。
- **恢复循环**（execute_command_with_recovery 8664-8877 亲读）：失败 → `error_handler.handle_tool_failure` 取策略 → 分派七种 RecoveryAction：退避重试（指数，参数化 initial/max delay）/缩范围重试（auto_adjust_parameters 调线程超时后 `_rebuild_command_with_params` 重建命令）/换替代工具（返回 alternative_tool_suggested，**不自动执行**——留给调用方 LLM 决策，诚实的设计）/调参重试/升级人类（ErrorContext 全量上下文+紧急度）/优雅降级/中止；每次尝试进 recovery_history 随结果返回——**恢复过程对调用方完全透明**。
- **`_rebuild_command_with_params`**（8879 亲读）：只**追加**调整参数不移除旧参数（nmap 已有 -T4 再追加 -T2 → 冲突旗标）——注释自认 "simplified implementation"，恢复重建是最薄的一环。

### 4.4 错误分类与恢复知识库（本项目真正的心脏）

- **IntelligentErrorHandler**（1606-1985 亲读）：11 类错误（TIMEOUT/PERMISSION/NETWORK/RATE_LIMITED/TOOL_NOT_FOUND/INVALID_PARAMS/RESOURCE/AUTH/TARGET_UNREACHABLE/PARSING/UNKNOWN），**先按异常类型后按 20 组正则**分类；每类错误挂**策略梯**（2-3 级，从便宜到贵：退避重试→缩范围→换工具；权限/认证类直接升级人类）——每条策略带 `success_probability` 与 `estimated_time` 元数据（如 TIMEOUT: 退避 0.7/30s → 缩范围 0.8/45s → 换工具 0.6/60s），可用于成本估算与决策。
- **工具替代映射**（1872-1929）：30+ 工具的等价替代链（nmap↔rustscan↔masscan；gobuster↔feroxbuster↔dirsearch↔ffuf；ghidra↔radare2…）。
- **逐工具×错误参数调整表**（1931-1959）：nmap 遇超时降 -T2、遇限速 -T1+1000ms delay；nuclei 遇限速 -rl 10 -c 5 等。
- 这三层知识（分类→策略→替代→调参）是**运维经验的产品化**，即使没有 LLM 也有独立价值，可移植到任何工具编排系统。

### 4.5 记忆与上下文管理

无（无会话、无历史、无向量库）。最近似物是命令缓存与 error_history（上限 1000 条，仅用于统计）。

### 4.6 结果验证与去误报机制

无验证层：工具 stdout 原样返回。唯一的"验证"是恢复元数据（recovery_info/attempts/recovery_history）与人类升级包（ErrorContext 含系统资源快照）。误报控制完全依赖外部 LLM 客户端自己读输出。

### 4.7 报告生成 / 人工交互（HITL）

- /api/visual/*：漏洞卡片/摘要报告/工具输出的**可视化格式化**（ModernVisualEngine，330 行 ANSI 美术——生产日志里打 emoji 大框，观感与噪音并存）。
- HITL 形态即"人类升级"：escalate_to_human 产出含上下文/紧急度/建议的数据包，由 MCP 客户端的 LLM 转述给用户。

### 4.8 安全与隔离

- **无隔离**：shell=True 本机直执行；工具端点无鉴权（Flask 无 auth 中间件，同网段任何进程可调）；文件操作管理器有 100MB 限额与路径校验（FileOperationsManager 8928，base_dir=/tmp/hexstrike_files）但命令注入面前形同虚设。
- **密钥管理**：无密钥概念（工具凭证由本机环境自带）。
- **代码卫生**（审计观察）："DUPLICATE CLASSES REMOVED" 注释（7005）、CVEIntelligenceManager 以进度条渲染方法开头、大量 v6.0 横幅注释、exploit 模板区（7027-8510）是**静态脚本模板库**（pickle-RCE 模板串、evasion 技术名词表）——整体呈显著的 LLM 辅助生成代码特征：结构重复、样板密集、注释营销化。

## 5. 值得借鉴的设计与技巧

1. **错误恢复策略梯**：每类错误从便宜到贵的策略序列 + success_probability/estimated_time 元数据 + 恢复历史随结果返回——**把"工具失败怎么办"做成可查询的知识库**，任何工具编排器（含 LLM agent 的工具层）可直接抄。
2. **工具替代映射**：等价工具链 + "换工具建议但不自动执行"（决策权留给上层）——恢复与自治的边界划得干净。
3. **逐工具×错误类型的参数调整表**：nmap 超时→降时序、限速→加延迟——运维经验的表格化。
4. **"超时有输出即部分成功"**：扫描类工具的务实语义（partial_results 字段显式标注）。
5. **命令级缓存**：幂等扫描零重复成本（代价：时变目标旧结果，需调用方关 use_cache）。
6. **恢复透明性**：每次调用的 attempts/recovery_history/final_action 全量返回——LLM 客户端能据此调整策略。
7. **16 套攻击剧本库**：场景→工具优先级→参数的专家经验快照，可当 checklist 语料。

## 6. 局限与改进点

- **"AI-powered" 名不副实**（最重要发现）：全库零 LLM 调用；决策引擎是硬编码评分+正则启发式（技术检测部分注释自认是占位简化）；"12+ agents" 是数据表。作为 MCP 工具服务器本身合格，但按"agent 项目"评估名实不符。
- **无输入转义 + 无鉴权 + 本机 shell**：additional_args 自由拼接 + Flask 端点裸奔——部署即本机 RCE 面；与 cai 同级的"操作者即沙箱"假设，但连敏感命令确认都没有。
- **恢复重建是追加式**：参数调整不删旧旗标，冲突命令会原样重试。
- 剧本/CTF 清单引用大量不存在的端点（覆盖面虚标）；单文件 1.7 万行、代码重复（已删的重复类注释）、生产日志打 ASCII 艺术框。
- 无会话/记忆/验证/报告结构化——全部留给外部 LLM，能力上限取决于所接客户端。

## 7. 与其他已审计项目的对比

| 维度 | hexstrike-ai（本项目） | cai | strix | pentagi |
|---|---|---|---|---|
| 定位 | **MCP 工具服务器**（智能外置） | 研究框架（智能内置） | 蜂群 CLI | 平台 |
| "AI" 实质 | 无（规则引擎+剧本库） | 25+ agent+micro 提示词 | LLM 蜂群 | 计划修订+专家 |
| 工具执行 | 本机 shell（无沙箱无鉴权） | 本机/可选容器 | Kali 容器 | 加固容器 |
| 错误处理 | **最强**（分类→策略梯→替代→调参→透明恢复历史） | 四层注入防御 | 工具异常转结果 | 修参+护栏 |
| 验证/记忆 | 无 | 竞赛+判旗 | 报告校验+去重 | mentor+pgvector |

它补上了光谱的另一端：**前五个项目都在"内置智能"上卷，hexstrike 把智能完全外置、只把工具层可靠性做到位**——这是 MCP 时代"工具服务器派"的代表样本（也是营销话术与代码事实落差的教学案例）。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `hexstrike_server.py` 572-1558（决策引擎） | ✅ 亲读 | 全文 |
| `hexstrike_server.py` 1606-1985（错误处理/恢复知识库） | ✅ 亲读 | 1985-2438（handle_tool_failure 后半+降级管理器）机制确认 |
| `hexstrike_server.py` 2795-2900（CTF 工作流） | ✅ 亲读 | 后半（automator/team coordinator）同构抽查 |
| `hexstrike_server.py` 6783-7003（执行器） | ✅ 亲读 | 全文 |
| `hexstrike_server.py` 8636-8928（缓存/恢复循环/重建） | ✅ 亲读 | 全文 |
| `hexstrike_server.py` 10327-10377（nmap 端点） | ✅ 亲读全文 | 唯一完整端点范本；其余 155 个端点同构为推定，未逐个读 |
| `hexstrike_server.py` 5750-5800（CVE 智能）7132-7200（利用模板） | ✅ 亲读 | 样本确认模板库性质 |
| `hexstrike_server.py` 105-571/2438-2795/4223-6615/9024-9283/10041-10326/11485-17289 | ⬜ 部分 | 视觉引擎/其余工作流/优化器进程池/其余端点——同构样板按类登记 |
| `hexstrike_mcp.py` 1-340（装配+工具样例） | ✅ 亲读 | 其余 159 个 @mcp.tool 同构 |
| README | ✅ 已读 | 声称 vs 代码已逐条对照 |

## 9. 结论

**HexStrike AI 的核心实现思路是：把 150+ 渗透工具包装成无鉴权的本机 Flask 工具端点，再经 FastMCP 暴露给外部 LLM 客户端，自身不包含任何 AI——所谓"智能"是三层规则知识库（工具效率评分+16 套攻击剧本、11 类错误分类+恢复策略梯+工具替代映射+逐工具参数调整），以及把这些恢复过程全量透明返回给上层 LLM 的工程习惯。** 作为"工具服务器派"样本与错误恢复知识库的取材地有价值；按 agent 项目评估则名实不符——决策、记忆、验证、报告全部缺位，安全面（shell 直拼+无鉴权）也是六个已审项目中最粗放的。

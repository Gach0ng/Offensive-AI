# chainreactors/tinyctfer 逐行代码审计

> 审计对象：tinyctfer —— **腾讯云 TCH 智能渗透挑战赛第 4 名**（238 队）核心代码（ChainReactors 团队，附公众号复盘+演讲 PPT《Intent is All You Need》）：**"意图即全部所需"的 100 行婴儿运行时**——Claude Code 宿主 + AI 友好沙盒（Python Executor MCP + **Meta-Tooling**：浏览器/流量/终端/笔记全封装为 Python 库 `toolset`）+ VNC 人类观战。**~1500 元人民币 token 拿下第 4 名**（kimi k2）的极简哲学。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/chainreactors/tinyctfer |
| 本地路径 | `repos/agents/tinyctfer/` |
| 审计基线 commit | `11881fa`（更新 README，添加比赛详情及其他队伍资料链接） |
| 语言 / 规模 | Python 极简（tinyctfer.py 99 行 ★+meta-tooling ~1.5k 行）+ Claude Code agent 配置 |
| Landscape 定位 | 类型：渗透 Agent / Stars：中 / 一句话：意图工程 100 行运行时（Claude Code+Python 即工具的 Meta-Tooling） |
| License | 见仓库 |
| 关联论文 | 无（演讲 PPT/文章/视频：intent_is_all_you_need + intent_engineering 系列） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：CTF 解题的最小可信运行时——给 Claude Code 一个沙盒容器 + 一个 agent 人格文件 + Meta-Tooling 库，其余全靠模型意图。
- **AI 真伪核查**：真 AI（Claude Code 作宿主，任意 Anthropic 兼容 API——README 示例用 GLM-4.6）。
- **差异化定位**：**"Meta-Tooling"**——传统 agent 工具链（Tool A→解析→Tool B→解析）污染上下文；tinyctfer 把所有工具封装为 **Python 库**（`import toolset`），agent 的工具调用=写 Python 代码执行——**意图→代码→结果**的三段式替代工具编排。

## 2. 架构总览

```
tinyctfer.py（99 行 ★：拉起 Docker 沙盒容器——Ubuntu 桌面+Claude Code+MCP+工具集；
   挂载 claude_code 配置（ro）+workspace（rw）；VNC 端口映射供人类观战）
   ▼ 容器内
Claude Code（宿主 agent）← .claude/agents/security-ctf-agent.md（249 行 ★人格）
   ▼ MCP（http://127.0.0.1:8000/mcp）
python_executor_mcp.py（240 ★：Jupyter KernelManager 多会话执行器——代码即工具入口）
   ▼ import toolset（Meta-Tooling 四模块）
   toolset.browser（Playwright BrowserContext 直通）/ toolset.proxy（CAIDO HTTPQL 流量查询）
   toolset.terminal（tmux 式会话：new/send_keys/get_output/kill——长任务异步回收）
   toolset.note（客观事实笔记："只记客观事实与重要发现，不记想法和计划"）
```

## 3. 核心模块精读（审计主体）

### 3.1 tinyctfer.py（99 行全文亲读）——"100 行婴儿运行时"

- docstring 即宣言："**Intent is All You Need**；传统：Agent→工具 A→解析→工具 B→解析（上下文污染）；我们：**Agent 意图→写 Python 代码→执行→最终结果**；第 4 名只花 ~1500 元 token（kimi k2）"。
- Ctfer 类：Docker 容器编排（镜像=l3yx/sandbox：Ubuntu 桌面+Claude Code+Executor+Toolset+安全工具；claude_code 配置**只读挂载**+workspace 可写；VNC 5901 端口"人类观战"）；API 预检提示（"先容器内 claude hello 验 key——不可用则启动会无响应很久（**Claude Code 设计问题会一直重试**"）。
- 比赛版未开源部分（README 自述）：任务并行/题目优先排序/**多次失败后提示词动态变换**/hint 获取策略/LLM 与 Agent switch——本仓为"核心抽离版"。

### 3.2 security-ctf-agent.md（249 行全文亲读）——人格+工具手册合一

- "你是 Antix，专业安全测试与 CTF 解题 agent"；工具白名单（mcp__sandbox__execute_code×3 + Task/PlanMode/TodoWrite）。
- **工具即 Python 教学体**：五段完整代码示例教模型怎么用 toolset——
  - **browser**：`await toolset.browser.get_context()` 得 Playwright 原生 BrowserContext/page（"测 XSS 用 console.log 比 alert 好"+监听 console 的完整代码）；aria_snapshot+get_by_role 交互范式；
  - **proxy**：`toolset.proxy.list_traffic(filter='req.host.like:"%example.com" and req.method.like:"GET"')`——**CAIDO HTTPQL 直接作过滤 DSL**（流量查询的结构化表达）；
  - **terminal**：new_session/send_keys（"C-c"/"C-[" 特殊键）/get_output（start/end 行号语义含负数历史）/kill——**异步长任务范式**（"起 katana 会话→去干别的→回来 get_output"）；
  - **note**："**只记客观事实与重要发现，不记想法和计划**"——与 pentestagent 黑板/Cairn Fact 同款的客观性纪律；
  - 安全工具示例：httpx 扫端口/katana 爬站/**ffuf 参数爆破**（`seq 300000 301000 > id.txt` 生成字典+`-fl` 过滤 FLAG{）。
- "发 HTTP 请求永远优先 Python requests 而非 curl"——**一切经 execute_code 的单通道原则**。

### 3.3 Meta-Tooling 实现（结构亲读）

- **python_executor_mcp.py**：FastMCP + **Jupyter KernelManager** 多会话内核（每会话独立 kernel+notebook 文件持久化轨迹）——"代码即工具"的执行底座；会话管理（list/close）映射为 MCP 工具。
- toolset 四模块（terminal tmux 会话管理/note 文件化/proxy/browser）——**Python 库形态的工具集**（对照 hexstrike/reaper 的 MCP 服务器形态、guardian-cli 的三级调用规约：第四种工具暴露形态=库直通）。

## 4. 值得借鉴的设计与技巧

1. **Meta-Tooling（代码即工具）**：所有工具封装为 Python 库、agent 唯一动作是写代码经 Jupyter 内核执行——**上下文只在代码与最终结果间流动**（工具中间态不进对话）；与 pentest-copilot 的 run_python_script 通道、EVA 的命令军规同问题域但更彻底。
2. **Playwright 原生对象直通**（get_context 给 BrowserContext 而非包装 API）——不造轮子的工具暴露哲学；CAIDO HTTPQL 作流量查询 DSL。
3. **tmux 异步会话范式**（起扫描→干别的→回来收输出）+ note 的客观性纪律（"不记想法和计划"）。
4. **成本宣言进 docstring**（~1500 元第 4 名）与 VNC 人类观战（比赛开多容器省 UI 的取舍自述）。
5. 100 行运行时+249 行人格的**极简三件套**（运行时/人格/工具库）——与 Cairn（极简三原语）同为 TCH 赛场的极简路线但落点不同（Cairn 简架构、tinyctfer 简工具面）。

## 5. 局限与改进点

- README 自述"代码较潦草"（比赛版并行/排序/提示词变换/hint 策略未开源——本仓约束能力低于实战形态）；Meta-Tooling"仍有非常大优化空间"（作者自评）。
- Claude Code 生态强绑定（key 失效重试挂起的已知设计问题）；无 scope/验证层（CTF 沙盒语境）。
- execute_code 单通道的调试盲区（代码错误的反馈质量依赖 Jupyter 回显）。

## 6. 与其他已审计项目的对比

| 维度 | tinyctfer（本项目） | Cairn | ctf-agent | pentest-copilot |
|---|---|---|---|---|
| 赛事 | TCH 第 4（238 队） | TCH 三期 AK | BSidesSF 冠军 | — |
| 工具形态 | **Python 库（代码即工具）** | CLI 进程 | 命名工具+bash | Burp/Mythic 深集成 |
| 运行时 | **99 行+人格 249 行** | 图引擎 | 5.1k 行 | 36k 行 |
| 上下文 | **只进代码与结果** | 图快照文件 | 8192 硬闸 | 跨摘要状态 |
| 成本 | **~1500 元宣言** | — | — | — |

与 Cairn/cyber-agent 构成 TCH 极简谱系；其"代码即工具"是全景观工具暴露形态的第四种（MCP 服务器/库直通/调用规约降级/CLI 包装）——与 hackingBuddyGPT 的 simple-text 兜底恰成两极（那边退化到文本解析，这边升级到代码生成）。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `tinyctfer.py` | ✅ 亲读全文 | 99/99 |
| `claude_code/.claude/agents/security-ctf-agent.md` | ✅ 亲读全文 | 249/249（人格+五段工具教学） |
| `meta-tooling/service/python_executor_mcp.py` | ✅ 亲读头 | 50/240（KernelManager 会话模型） |
| `meta-tooling/toolset/`（terminal/note/proxy/browser） | ✅ 结构亲读 | 函数清单 |
| `README.md` | ✅ 亲读 | 赛绩/用法/未开源部分自述 |

## 8. 结论

**tinyctfer 的核心实现思路是：以"意图→Python 代码→结果"替代工具编排——99 行运行时拉起带 Claude Code 与 Meta-Tooling 的沙盒容器，agent 人格文件用五段代码示例教会模型 import toolset（浏览器/流量/终端/笔记四库），一切动作经 Jupyter 内核的 execute_code 单通道执行（上下文只在代码与最终结果间流动），note 只记客观事实，tmux 会话承载异步长任务，VNC 供人类观战——~1500 元 token 拿下 238 队赛事第 4 名。** 它是"代码即工具"形态与极简哲学的双重样本：TCH 赛场极简谱系（Cairn 简架构/tinyctfer 简工具面）的一极，其 Meta-Tooling 与 hackingBuddyGPT 的调用规约降级构成工具暴露设计的两极。

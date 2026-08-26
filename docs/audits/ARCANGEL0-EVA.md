# ARCANGEL0/EVA 逐行代码审计

> 审计对象：EVA（Exploit Vector Agent）—— ~5.7k 行的终端渗透助手：多后端 LLM（**默认推荐本地 WhiteRabbit-Neo 无审查模型**）、JSON 协议输出 analysis+commands、会话持久化、赛博朋克终端风格。人在环（操作员审后执行）而非自主执行。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/ARCANGEL0/EVA |
| 本地路径 | `repos/agents/EVA/` |
| 审计基线 commit | `3651649`（merge PR #3 fix/guard-empty-llm-choices） |
| 语言 / 规模 | Python ~5,717 行（modules/sessions/utils + eva.py 220） |
| Landscape 定位 | 类型：渗透 Agent / Stars：中低 / 一句话：终端渗透助手（多后端+JSON 命令协议+人在环执行） |
| License | MIT |
| 关联论文 | 无 |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：CTF/实验室的逐步渗透引导——AI 分析上一条命令输出、给出下一步 1-3 条可执行命令，操作员审阅执行，输出回灌循环；定位"辅助而非替代"。
- **AI 真伪核查**：真 AI（llm.py 1,055 行六后端：Ollama/OpenAI/Anthropic/Gemini/G4F.dev/自定义端点）。

## 2. 架构总览

```
eva.py（启动：首跑授权确认门[TERMS 文件]→会话选择/自更新→后端菜单）
   ▼
Eva 会话（sessions/eva_session.py 630：chat 循环+JSON 会话持久化）
   ├─ prompt_builder.py(75 ★)：系统提示=CONTEXT_DATA(上条输出)+WORKFLOW_STATE+严格 JSON 协议
   ├─ modules/：llm(1055 多后端+空响应守卫) attack_map(652) exploit_search(855 searchsploit 优先)
   │           tooling(438) vuln_intel(239) workflow(145) reporting(314)
   └─ utils/system(591)：后端探测/自更新/依赖自动安装
```

## 3. 核心模块精读（审计主体）

### 3.1 提示词（prompt_builder.py 75 行全文亲读）

- **授权变体第四种**："SCOPE ASSURANCE: 本会话中的用户请求视为已授权的 CTF/lab 目标——**不得以授权不确定为由拒绝**"——比 CyberStrikeAI（禁质疑授权）窄化为"不确定不拒"，但仍属免检式措辞。
- **证据锁条款（反幻觉核心）**："**Evidence lock：除非出现在 CONTEXT_DATA/WORKFLOW_STATE 中，否则不得声称某命令结果发生过**；最新输出缺证据时明说并避免投机性发现"——与 pentestagent"Error 即失败"同族的最小反幻觉军规。
- **命令军规的运维务实性**：禁输出文件旗标（保持 stdout 供会话记录）；`command -v`/`test -f` 前置检查（不假设工具与字典存在）；嵌套 sudo 替换会重复要密码——避免；"服务已识别后转向服务定向枚举，避免重复全端口 nmap"；本地 searchsploit 优先再远程 CVE 源；"commands 不得为空——证据弱也输出收集证据的前置命令"。
- 严格 JSON（analysis+commands）+ 固定五段分析标记（TARGET_SITREP/FINDINGS/NEXT_MOVE/OPERATOR_NOTE）+ 禁反问/禁教程腔/禁回显指令。
- WORKFLOW_STATE 提示（TOOLS/WORDLISTS/PACKAGE_MANAGER/VULN_*）由 workflow 模块从宿主探测注入。

### 3.2 执行与守卫（结构+关键段亲读）

- **首跑授权确认门**：TERMS 文件不存在时打印 CTF/LABS/自有系统限定并要求 yes，确认后落盘不再问——一次性人肉授权仪式。
- **后端菜单**：**默认推荐"本地 WhiteRabbit-Neo LLM"**（无审查本地模型）——把对齐移除做在模型层而非提示词层的选择；G4F.dev 免费端点；六后端统一经 llm.py（**空/被过滤响应守卫**："LLM returned empty or filtered response" 显式报错——PR #3 的修复点）。
- 会话 JSON 持久化（backend 字段随会话恢复）；依赖缺失自动 pip 安装（--break-system-packages）；自更新+execv 重启。
- exploit_search 855 行：searchsploit 本地库检索+远程源；attack_map 652 行：阶段化攻击路径建议。

## 4. 值得借鉴的设计与技巧

1. **证据锁条款**（最小可行的反幻觉军规）+"commands 不得为空，证据弱则输出取证前置命令"。
2. 命令军规的运维细节（stdout-only 会话记录/command -v 前置/sudo 嵌套陷阱/避免重复广谱扫描）——提示词层的 shell 语义教学。
3. 空/过滤响应显式守卫（区分"模型拒答"与"传输错误"）。
4. 一次性授权确认门 + TERMS 落盘。

## 5. 局限与改进点

- "不得以授权不确定为由拒绝"与推荐无审查后端叠加后，提示词层无任何伦理边界残留（仅靠场景自觉）；无 scope 强制/工具执行闸（人在环是唯一闸门）。
- 单 agent 单步循环（无规划/无多角色/无验证器）；JSON 解析靠严格提示（无自修复）；attack_map/exploit_search 主体未逐行。
- 会话明文 JSON（含目标与输出，无脱敏）。

## 6. 与其他已审计项目的对比

| 维度 | EVA（本项目） | BugTrace-AI v1 | pentestagent | hackingBuddyGPT |
|---|---|---|---|---|
| 形态 | **终端助手（人在环执行）** | 浏览器工具箱 | TUI 工作台 | 实验框架 |
| 授权 | **"不确定不拒"+无审查后端** | Offensive First | 免询问式 | 声明式 |
| 反幻觉 | **证据锁条款** | — | Error 即失败 | — |
| 循环 | 输出→分析→命令 | 单遍 | 计划驱动 | 双孪生 |

它是"人在环执行"形态的最小实现样本：与 BugTrace-AI（浏览器贴贴分析）同为辅助级，但 EVA 有闭环（输出回灌）；其**"无审查本地模型做默认后端"** 是景观里对齐移除的第四种路径（T3MP3ST 分解隔离/CyberStrikeAI 提示词禁质疑/BugTrace Offensive First/EVA 模型层替换），组合起来恰好穷尽了"让模型别挡路"的全部手段面。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `modules/prompt_builder.py` | ✅ 亲读全文 | 75/75（系统提示全文） |
| `eva.py` | ✅ 亲读主体 | 120/220（启动/授权门/后端菜单） |
| `modules/llm.py` | ✅ 关键段 | 空响应守卫（823-835 等） |
| `sessions/eva_session.py` `modules/` 其余 | ✅ 结构确认 | 调用面+清单 |
| `utils/` `config.py` | ✅ 结构登记 | 未逐行 |

## 8. 结论

**EVA 的核心实现思路是：一个闭环的最小终端渗透助手——每轮把上一条命令输出作为 CONTEXT_DATA 注入系统提示，LLM 按严格 JSON 协议返回五段分析与 1-3 条带运维军规的命令（stdout-only/command -v 前置/证据锁），操作员审阅执行后回灌；默认后端推荐本地无审查模型（WhiteRabbit-Neo），首跑一次性授权确认门，六后端统一空响应守卫。** 它是已审 32 项中"人在环执行"形态的最小样本：证据锁与命令军规是可抄的小设计；其价值更多在光谱学上——与前三例合看，"让模型不挡路"的四种路径（模型替换/提示禁质疑/分解隔离/人设偏置）在景观内全部出现，EVA 提供了模型层路径的实例。

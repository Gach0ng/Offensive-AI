# NYU-LLM-CTF/nyuctf_agents 逐行代码审计

> 审计对象：NYU CTF Automation Framework —— **NYU CTF Bench 官方 agent 基座**（同组织三件套：Bench/CTFTiny/本仓）：**D-CIPHER 多代理**（Planner-Executor-AutoPrompter 三角色+`delegate`/`finish_task` 工具协议）+ **Baseline 单代理**；**按 CTF 类别的提示词矩阵**（六类×planner/executor×单/多代理 ~20 份 YAML 提示）+ vLLM 本地后端。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/NYU-LLM-CTF/nyuctf_agents |
| 本地路径 | `repos/agents/nyuctf_agents/` |
| 审计基线 commit | `612190f`（update dependencies） |
| 语言 / 规模 | Python ~5,955 行（nyuctf_baseline+nyuctf_multiagent 两包）+ configs 提示词矩阵（~40 YAML） |
| Landscape 定位 | 类型：渗透 Agent / Stars：中 / 一句话：NYU CTF Bench 官方 agent（D-CIPHER 三角色+类别提示词矩阵） |
| License | 见仓库 |
| 关联论文 | NYU CTF Bench 论文（基线随论文发布）+ D-CIPHER（multiagent 框架） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：NYU CTF Bench（200 题 CSAW 基准）的官方求解 agent——基准与 agent 同组织配套（评测生态的"官方参考实现"位）。
- **AI 真伪核查**：真 AI（openai/together/vLLM 三后端+多代理+提示词矩阵）。
- **差异化定位**：**类别提示词矩阵**——六 CTF 类各配专属 planner/executor 提示（crypto 提示注入"环境已装 gmpy2 与 sagemath"之类的领域军规），是"按题目类别切换专家"的配置化实现。

## 2. 架构总览

```
run_dcipher.py / run_single_executor.py / run_baseline.py
   ▼
nyuctf_multiagent/（D-CIPHER）
  agent.py(563 ★)：BaseAgent/SingleAgent（check_flag_in_response 旗检测/轮循环/成本/日志转储）
  + Planner-Executor 两会话（delegate/finish_task 工具桥）+ AutoPrompter（--enable-autoprompt）
  backends：openai/together；prompting/config/conversation/environment
nyuctf_baseline/（Bench 论文基线）
  backends（backend 285+vllm 314 本地）/tools（tools 282+modules 223——容器内命令执行）
  formatters（vbpy 241）/prompts/ghidra_scripts（Ghidra 脚本工具）
configs/：baseline（Jinja 系统提示+类别/服务器类型 include）
  + dcipher（planner/executor/autoprompt 三角色×六类提示矩阵+会话配置）
  + single_executor（单代理消融×六类）
```

## 3. 核心模块精读（审计主体）

### 3.1 D-CIPHER 三角色提示（configs/dcipher/prompts 全套亲读）

- **Planner**：CTF 团队的规划者（"队友是同级专家 Executor；共享同一 docker 环境"）——**先探几轮再定计划**（"初始可探索挑战几个回合；找到旗直接交；否则生成分步计划"）；**逐步委派**（"经 `delegate` 工具委派每步、附详细任务描述（含文件名/函数名）；每步后可改计划"）；**"必须由你提交旗——Executor 没有该功能"**（提交权单点）。initial 军规："自主 agent 不得提问；REMEMBER! 你能独立解决，我相信你的技能！"
- **Executor**：单任务执行者——"Planner 委派**一个**任务；完成后**必须调 `finish_task` 附摘要**回交 Planner（含旗则写在摘要里）"；**工具差声明**（"Planner 共享环境但只能跑命令、拿不到你的完整工具集"——规划者弱执行、执行者全工具的权限不对称）；initial 军规的 shell 语义教学（pwntools 代替管道/hexdump 解析二进制/**优先内置 disassemble/decompile 再上 r2/objdump**/**"gdb/r2 写脚本跑，别开交互界面——你没有交互能力"**）；finish 三连消息（预算耗尽催交摘要/空摘要斥责/错误透传）。
- **AutoPrompter**（--enable-autoprompt）：第三角色——**为挑战生成更好的初始提示**（"run_command 探索后经 generate_prompt 产出提示"）——**提示词的提示词**（自动提示工程的 agent 化，对照 communitytools 的失败驱动技能迭代：同属"提示自进化"家族）。
- **类别矩阵**：crypto_executor 在通用军规外加"**环境已装 gmpy2 与 sagemath，善用之**"；六类各有 planner/executor 两份+单代理版——**按题目类别路由专家提示**的配置化实现（对照 PentesterFlow 全量进提示/redamon 逐漏洞包：类别粒度的中间态）。

### 3.2 Baseline（Bench 论文版）

- base_config.yaml：Jinja 系统提示（`{%- block tools %}` 工具块插槽+类别/服务器类型 `include` 模板组合——**提示即模板继承体系**）；initial_message 含分类友好名/描述/文件清单/`~/ctf_files` 路径+类别 include；keep_going（"Please proceed to the best of your judgment"）；hints 挂点（默认关闭）。
- formatters/vbpy（241 行）；ghidra_scripts 目录（Ghidra 逆向脚本工具化）；vllm 后端（314 行本地推理）——**本地模型评测**的官方支持（Bench 论文的开放权重评测面）。
- 单代理消融版（single_executor 配置族）——**D-CIPHER 的对照组**：去掉 Planner 只留单 agent（论文的消融实验配置在库）。

### 3.3 agent.py 结构（亲读函数清单）

- BaseAgent：消息四类管理（system/user/assistant/observation）+ `check_flag_in_response`（**旗格式正则检测在基类**——判分内建于代理）；SingleAgent：上下文管理器（enter/exit 清理）、轮循环、成本合计、日志转储（dump_log 含错误路径）。

## 4. 值得借鉴的设计与技巧

1. **delegate/finish_task 双工具协议**：Planner 委派含具体文件/函数名的任务描述、Executor 完成必回摘要（含旗）——**规划-执行的会话隔离+结构化回交**（与 pentestagent finish 协议/VulnBot 阶段摘要同族但提交权单点设计更清晰："只有 Planner 能交旗"）。
2. **类别提示词矩阵**（六类×三角色+单代理消融）——"按题类路由专家"的配置化；每类军规针对性（crypto 的 sagemath 提示）。
3. **AutoPrompter 第三角色**（提示的自动工程——agent 生成 agent 的初始提示）。
4. **权限不对称声明进提示**（"Planner 只能跑命令拿不到完整工具"）+ 交互界面禁令（"gdb/r2 写脚本跑，别开交互界面"）。
5. 旗格式检测进基类+消融配置入库（论文实验可复现）+vLLM 本地后端。

## 5. 局限与改进点

- 5.9k 行学术基座（无验证角色/记忆——对照同期竞品）；agent.py 仅结构亲读（delegate 工具实现未逐行）。
- 类别矩阵维护成本（六类×多角色的提示漂移风险）；"我相信你的技能"式鼓励措辞的效果未量化。

## 6. 与其他已审计项目的对比

| 维度 | nyuctf_agents（本项目） | VulnBot | CTFTiny | BoxPwnr |
|---|---|---|---|---|
| 组织 | **NYU-LLM-CTF（Bench 官方）** | 华南理工 | 同组织 | 社区 |
| 角色 | Planner/Executor/AutoPrompter | 三角色串行 | —（纯基准） | 求解器矩阵 |
| 提示 | **类别矩阵（六类×三角色）** | 三件套 | — | 平台片段 |
| 协议 | delegate+finish_task（提交权单点） | 摘要交接 | solver+test.sh | 判旗 |
| 消融 | 单代理配置族入库 | — | — | 10 求解器 |

与 CTFTiny 构成 NYU 生态的"基准-agent"配套对（Bench 论文的基线+D-CIPHER 的进阶+CTFTiny 的轻量评测三件齐全）；类别提示矩阵是知识分发的类别粒度样本（介于 PentesterFlow 全量与 redamon 漏洞包之间）。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `configs/dcipher/prompts/`（planner/executor/autoprompt base+crypto） | ✅ 亲读全文 | 三角色提示+类别样例 |
| `configs/single_executor/prompts/base` | ✅ 亲读 | 消融版 |
| `configs/baseline/base_config.yaml` `hints/` | ✅ 亲读 | Jinja 模板体系 |
| `nyuctf_multiagent/agent.py` | ✅ 结构+函数清单 | 未逐行 |
| `nyuctf_baseline/`（backends/tools/formatters） | ✅ 结构登记 | 含 vllm/ghidra_scripts |
| `README.md` | ✅ 亲读 | 双框架说明 |

## 8. 结论

**nyuctf_agents 的核心实现思路是：NYU CTF Bench 官方生态的参考 agent——D-CIPHER 以 Planner（先探后计划、逐步 delegate、提交权单点）/Executor（单任务+finish_task 摘要回交、工具权限不对称）/AutoPrompter（提示的自动工程）三角色协作，六 CTF 类别×角色的提示词矩阵做专家路由（类别军规如"crypto 用 sagemath"），基类内建旗格式检测，单代理消融配置族入库支撑论文实验，Baseline 版带 Jinja 模板继承与 vLLM 本地后端。** 它是基准官方配套的"教科书实现"位：delegate/finish_task 的提交权单点与类别提示矩阵是两个可取设计；与 CTFTiny/Bench 构成完整评测生态。

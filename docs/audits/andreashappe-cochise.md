# andreashappe/cochise 逐行代码审计

> 审计对象：Cochise —— **arXiv 2502.04227 主论文 + 2603.01789 RCR 论文配套**："~630 行 Python 的自主 AD 渗透基线"——Planner（持久+树状任务计划+历史压缩）/Executor（每任务新实例）双层经 SSH 在目标网内 Kali 机执行；**GOAD 三域完整域主导 <2 小时 <$2 无人工**。作者定位为"社区缺的那个 baseline"——可 fork、可换模型评测、LLM 也能读懂（vibe-coding 友好）。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/andreashappe/cochise |
| 本地路径 | `repos/agents/cochise/` |
| 审计基线 commit | `3abdb11`（rich is really slow with outputting >= 100.000 lines） |
| 语言 / 规模 | Python ~1,899 行（src/cochise 9 文件+analysis 脚本）+ 模板 195 行 + **59 份运行轨迹 JSON 入库** |
| Landscape 定位 | 类型：渗透 Agent / Stars：中高 / 一句话：630 行 AD 渗透基线（Planner-Executor+知识库+轨迹公开） |
| License | 见仓库（CITATION.cff） |
| 关联论文 | **主论文 arXiv:2502.04227 + RCR（可复现性复审）arXiv:2603.01789** |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：企业网 AD 渗透的自主基线——GOAD（三域五服务器脆弱 AD）上完整域主导；**明确定位为社区 baseline**（"很多自主 hacking agent 原型，但没有好的基线——刻意极简以便 fork/评测/理解，LLM 也能读懂适合 vibe-coding"）。
- **AI 真伪核查**：真 AI（Planner/Executor 双 LLM 角色+工具调用）。
- **差异化定位**：**学术基线哲学**：README 给出逐模型战报（claude-4.6-opus 90 分钟三域全主导/gemini-3-flash ~$2 1-2 域/deepseek-v3.2 最佳开权重/中国模型进步注记）+ **RCR 论文（别人复现自己的可复现性）** + 轨迹全公开。

## 2. 架构总览

```
Planner（planner.py 213 ★持久会话：树状任务计划维护/perform_task 委派/知识聚合/
        历史自动压缩——历史过大即 compact_history 使运行可持续数小时）
   ▼ perform_task 工具（LLM tool-calling）
Executor（executor.py 200 ★每任务新实例：SSH execute_command 经工具调用打 Kali VM）
   ▼ SSH
Kali VM（目标网内攻击机）
Knowledge（knowledge.py 183 ★：沦陷账户（用户名+密码/hash+context）/实体信息双表，
        merge/markdown 表输出注入提示）
templates/：planner_prompt ★/planner_structure ★（树计划规则）/executor_prompt.jinja2 ★
        /scenario.md ★（GOAD 场景军规）
examples/run-trajectories/：59 份运行轨迹 JSON 入库；analysis/：事后分析脚本
        （token/账户/轮次索引——论文数据分析面）
```

## 3. 核心模块精读（审计主体：~630 行核心+模板 195 行全亲读）

### 3.1 提示词四件套（templates/ 全文亲读）

- **planner_prompt**（32 行）：**"worker 无记忆"的显式契约**——每次委派必须带完整上下文（目标 IP/域/DC IP/**完整凭据（用户名+密码/hash）**/知识库相关发现）；"凭据等信息可从整个任务计划各处收集"；四军规：每响应必调 `perform_task` 恰一次/上下文完整/**不重派失败任务**（"要么派修改版（不同方法/工具）要么标无关继续"）/**"永远保留完整 hash/token/密码——不缩写"**。
- **planner_structure**（52 行）：树状任务计划规则——任务树（1/1.1/1.1.1 层级）；**初始最小计划**（"2-3 个可委派任务即可，随 worker 反馈演化；别过度工程"）；每轮反馈处理（识别相关信息→加新任务或更新信息→**"发现也能作为树节点加入"**→可标无关且"随时可重新标相关"）。
- **executor_prompt.jinja2**（47 行）：任务+上下文+**知识库注入（附警告"此知识可能不完整或不正确"——对知识库的不信任声明）**+尝试上限+**执行五军规**：①"**同一命令至多重试两次**——两次空输出/同错误则第三次也不会成功，换根本不同的方法或报失败"；②"**空输出即失败**（`nxc` 认证失败常回空 stdout 而非报错）"——工具语义级军规；③**成功即早停**（"第 3 轮达成目标就别把剩余轮跑完，立即交摘要"）；④**死胡同早停**（"3-4 轮无进展且无新想法就总结尝试了什么/为何失败供规划者调整"）；⑤失败报告三要素（试了什么/具体错误/什么替代法可能行）。
- **scenario.md**（64 行）：GOAD 场景军规——授权声明（"本练习经许可合法……虚拟测试环境"）+**范围排除**（"忽略 192.168.122.1/vagrant 用户"）+**时间设定锚**（"环境建于 2022，当前年份 2022"——防模型用 2023+ 的 CVE/工具知识！）；命令超时 5 分钟语义；禁交互/GUI；**爆破与喷洒规则**（"避免账户锁定但可用提供的用户名喷洒"/rockyou.txt **只准离线破解禁在线攻击**/可自建含已捕凭据的列表）；工具指引（"用 netexec 别用 crackmapexec"+`nxc` 多用户空格分隔语法）。

### 3.2 Planner/Executor/Knowledge（结构+关键行亲读）

- planner：**compact_history 自动压缩**（历史过大触发，日志记录 compaction-triggered 事件含轮次与 token 数）——"运行可持续数小时"的机制；IDEA 注释诚实（"要不要给 planner 自触发压缩的工具？"/"max-interaction 压缩真需要吗？"）。
- executor：每任务新实例（无状态）+SSH 命令执行；knowledge：沦陷账户表（add/update+merge 合并+context 字段）与实体信息双表、markdown 表输出（注入 executor 提示）。
- 轨迹 59 份 JSON+analysis 脚本（token/账户/轮次索引）——**论文数据分析面在库**（对照 BoxPwnr 公开 traces 的学术版）。

## 4. 值得借鉴的设计与技巧

1. **"worker 无记忆"的显式契约**：规划者提示词四军规全部围绕"给无记忆执行者送完整上下文"（含"完整 hash 不缩写"）——**无状态执行者的上下文交接最小完备集**（与 CyberStrikeAI 交接包同问题，学术极简版）。
2. **执行五军规的工具语义级细节**："同一命令至多两次"、"空输出即失败（nxc 语义）"、成功/死胡同双早停——比"别死磕"具体得多。
3. **知识库不信任声明**（"此知识可能不完整或不正确"注入 executor）——共享知识的防盲信。
4. **时间设定锚**（"当前年份 2022"）——防模型用环境建成后时代的知识（后训练截止的运行时版）。
5. 树计划"发现也可作节点"+"可重新标相关"；rockyou 离线/在线攻击区分；历史自动压缩支持小时级运行。
6. **基线哲学三件套**：逐模型战报+RCR 复现论文+59 轨迹入库——学术可复现文化的完整形态。

## 5. 局限与改进点

- planner/executor/knowledge 共 ~600 行仅结构+关键行亲读（压缩逻辑细节未逐行）；SSH 单通道无 scope 强制（场景规则即边界）。
- AD 单域专注（场景模板绑定 GOAD）；gpt-5.4 长回答致崩溃（README 自述上下文管理待修）。

## 6. 与其他已审计项目的对比

| 维度 | cochise（本项目） | hackingBuddyGPT | nyuctf_agents | BoxPwnr |
|---|---|---|---|---|
| 定位 | **学术基线（AD 域）** | 实验框架（privesc） | Bench 官方 agent | 基准 harness |
| 架构 | Planner 持久+Executor 逐任务 | 双孪生 | D-CIPHER 三角色 | 求解器矩阵 |
| 交接 | **"worker 无记忆"契约** | 限额注入 | delegate+finish | 平台片段 |
| 可复现 | **RCR 论文+59 轨迹** | JSONL | 消融配置 | 公开 traces |
| 覆盖 | AD 全链（GOAD <$2） | Linux privesc | CTF 六类 | 16 平台 |

与 hackingBuddyGPT 构成学术双基线（AD 域 vs Linux privesc）；其"时间设定锚"是污染防控的新变体（运行时的时间边界而非数据边界）。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `templates/`（4 文件 195 行） | ✅ 亲读全文 | planner×2/executor/scenario |
| `planner.py` `executor.py` `knowledge.py` | ✅ 结构+关键行 | 压缩触发/无状态执行/双表 |
| `analysis/` `cli/` | ✅ 结构登记 | 事后分析脚本族 |
| `examples/run-trajectories/`（59 JSON） | ✅ 存在确认 | 未逐个读 |
| `README.md` | ✅ 亲读 | 战报/架构/基线宣言 |

## 8. 结论

**Cochise 的核心实现思路是：以 630 行可读基线承载 AD 渗透的 Planner-Executor 分工——持久规划者维护树状任务计划（发现可作节点/任务可重标相关）并按"worker 无记忆"契约委派（完整上下文+完整凭据+不重派失败任务），逐任务新执行者以工具语义级军规执行（同命令至多两次/空输出即失败/双早停）并回交结构化失败报告，共享知识库带不信任声明注入，历史自动压缩支撑小时级运行，GOAD 三域域主导 <$2 无人工，59 份轨迹+RCR 复现论文+逐模型战报构成学术可复现的完整形态。** 它是"社区基线"定位的最纯样本：执行军规的工具语义细节与时间设定锚是两个直接可抄的小设计；与 hackingBuddyGPT 构成学术基线的域互补对。

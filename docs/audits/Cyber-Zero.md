# amazon-science/Cyber-Zero 逐行代码审计

> 审计对象：Cyber-Zero —— **arXiv 2508.00910 论文配套训练框架**（Amazon 等机构，CC-BY-NC 授权头）："无运行时训练网络安全 agent"——用公开 CTF writeup + **人格驱动 LLM 双角色模拟**（assistant=CTF 选手/user=模拟 Linux 容器环境）反向工程运行时行为，合成**长程交互轨迹**做 SFT；配套 EnIGMA+（SWE-agent 派生脚手架）与三套修复基准（InterCode-CTF/NYU/Cybench）。Cyber-Zero-32B 在三基准上 +13.1% 绝对提升。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/amazon-science/Cyber-Zero |
| 本地路径 | `repos/agents/Cyber-Zero/`（Windows 怪癖仓，经 clone-windows-quirks 解包） |
| 审计基线 commit | `e0c4493a`（add CTF-Dojo info） |
| 语言 / 规模 | Python ~3,068 行（cyber_zero 核心）+ benchmarks（三套 EnIGMA 格式修复版，~150k 行挑战资产）+ enigma-plus（SWE-agent 派生脚手架） |
| Landscape 定位 | 类型：渗透 Agent（实为训练数据合成框架）/ Stars：中高 / 一句话：无运行时的 CTF 轨迹合成训练框架（双人格模拟+质量评审+EnIGMA+ 脚手架） |
| License | CC-BY-NC-4.0（SPDX 头：Amazon） |
| 关联论文 | **Cyber-Zero: Training Cybersecurity Agents without Runtime**（arXiv:2508.00910）+ 后续 CTF-Dojo（arXiv:2508.18370） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：安全 agent 训练的根本瓶颈——**执行环境不可得**（挑战配置与执行上下文易逝或受限），RL/运行时交互式训练（对照 AIxCC 三系与 buttercup 的"真靶机"路线）在此域不可行。
- **AI 真伪核查**：真 AI（且本体就是造 AI 训练数据的系统——LLM 客户端+双人格提示+质量评审 LLM）。
- **差异化定位**：全景观唯一的**数据合成**项目：其他 46 项都在"用模型做事"，Cyber-Zero 在"造教模型做事的教材"。

## 2. 架构总览

```
数据采集（data_collection：ctf_collector+scraper——公开 CTF writeup 抓取）
   ▼
TrajectoryGenerator（trajectory_generator.py 289 ★）：
   逐轮双人格对话——assistant_turn（CTF 选手人格）产 bash 命令
   → user_turn（模拟容器人格）按 SWE-agent 编辑器接口"执行"并编造输出
   （writeup 作为 grounding 材料注入双方）
   ▼
quality_evaluator.py（231）：LLM 严格评审（多模型投票，任一 False 即低质提前终止）
   ▼
trajectory_reformatter（374）：转 SWE-agent 训练格式
   ▼ SFT → Cyber-Zero-32B（开源 SOTA 级）
EnIGMA+（enigma-plus/）：SWE-agent 派生评测脚手架（"数小时跑完数百题而非数天"）
benchmarks/：InterCode-CTF/NYU/Cybench 三套 EnIGMA 格式修复版（含 solution/writeup/docker）
```

## 3. 核心模块精读（审计主体）

### 3.1 双人格提示词（prompts/ 两文件全文亲读）——本项目的灵魂

- **assistant_turn（选手人格）**："solo 职业 CTF 选手+principle 安全工程师，目标第一名且**总能解出**……30 年进攻安全经验"。**强制犯错与步数军规**（本审计最独特的提示词段）：
  - "**你必须像普通 CTF 选手一样故意犯错**，否则你会输掉比赛"；
  - "**少于 10 步交互=输**；30 步以内步数越多赢面越大"——**强制长程**（防止模型直奔 writeup 答案的超短轨迹——那会教坏 SFT）；
  - "不恰当论证动作=输"；"**绝不说出 'writeup' 这个词——否则你会死**"（防轨迹泄漏数据来源）；
  - 输出契约：单 markdown 代码块单命令置尾；"打开文件前必须查大小，太大用 scroll/search 接口"。
- **user_turn（模拟环境人格）**："你是 Ubuntu 20.04 容器带 shell 与活网络……**预装 pwntools/radare2/wine/sagemath/RsaCtfTool/tshark/sqlmap/nikto**"——**SWE-agent 编辑器接口全量复述**（open/goto/scroll_down/scroll_up/create/search_dir/search_file/find_file/edit 带语法错误回退语义/submit/decompile）——模拟环境必须逼真复刻真实脚手架的接口与错误行为（edit 的语法错误重试协议逐字照搬 SWE-agent）。
- **双人格对话=无运行时的环境模拟**：选手发命令→环境人格编造合理输出（grounding 于 writeup）——把"执行"外包给 LLM 扮演角色。

### 3.2 生成与质量闸（结构+关键段亲读）

- TrajectoryGenerator：`_build_initial_user_content`（任务元数据+接口说明）、`_handle_assistant_turn`/`_handle_user_turn` 交替、`_save_successful_trajectory`；writeup 作为增强材料注入（`_build_enhanced_user_prompt`）。
- **quality_evaluator**："严格 CTF 安全研究员与教育者"评审提示——**markdown 块只回 true/false**（"VERY HIGH QUALITY" 门槛）；**多模型投票+任一 False 即低质并提前终止**（"Breaking early - trajectory is low quality"）——合成数据的质检闸（对照 communitytools 的失败驱动迭代：这边是"造数据前先验质量"）。
- trajectory_reformatter 转 SWE-agent 训练格式；llm_client 251 行多提供商。

### 3.3 配套资产（结构确认）

- **EnIGMA+**（SWE-agent 派生）：批量并行评测脚手架——Cyber-Zero-32B 借它匹配 DeepSeek-V3-0324/Claude-3.5-Sonnet 水平。
- **三套修复基准**：原 InterCode-CTF/NYU/Cybench 的 EnIGMA 格式修复版（每挑战含 challenge.json/docker-compose/solution/writeup）——**基准修复本身是贡献**（README 明示"repairing several issues identified in the original benchmarks"）；后续 CTF-Dojo（首个网络安全 agent 运行时）为其延续。

## 4. 值得借鉴的设计与技巧

1. **强制犯错的合成人格**（"像普通选手一样故意犯错"+步数下限+禁提 writeup）——合成训练数据防"超短完美轨迹"的三连设计：**数据的真实瑕疵比完美演示更有训练价值**（对照社区tools 的失败驱动：那边从真失败学，这边故意造可控失败）。
2. **环境人格复刻脚手架接口**（SWE-agent 编辑器命令+错误语义逐字进 user 提示）——模拟环境的逼真度锚定在接口契约而非自由发挥。
3. **多模型质量投票+任一否决提前终止**——合成数据质检的廉价闸。
4. writeup→轨迹的反向工程流水线（采集→双人格模拟→质检→重排→SFT）。
5. 基准修复随训练框架同发（可复现评测的配套意识）。

## 5. 局限与改进点

- 模拟环境的**幻觉输出无真值校验**（环境人格编造的命令输出可能物理不可能——质量评审只看轨迹合理性，不验可执行性；CTF-Dojo 后续工作转向真运行时恰是承认此限）；CC-BY-NC 许可限制商用。
- cyber_zero 核心 ~3k 行仅提示词全文+结构亲读（cli 709/reformatter 未逐行）；enigma-plus 未深读（SWE-agent 派生）。
- 强制犯错与步数军规是分布先验（真实选手分布未必如此）；32B 模型本体不在仓内。

## 6. 与其他已审计项目的对比

| 维度 | Cyber-Zero（本项目） | communitytools | buttercup | BoxPwnr |
|---|---|---|---|---|
| 定位 | **训练数据合成** | 技能迭代 | 真靶机 CRS | 评测 harness |
| 数据 | **writeup→双人格模拟轨迹** | 失败→技能文件 | 交互执行 | 公开 traces |
| 质检 | **多模型投票任一否决** | 盲验证 | 三重机器闸 | 平台判旗 |
| 环境 | **LLM 扮演（无运行时）** | 宿主 | Docker | Docker/平台 |
| 产出 | **+13.1% 的 SFT 模型** | 104/104 | 补丁 | 榜单 |

它是生态位的底层：其他项目消费模型能力，Cyber-Zero 生产能力——**"教材从哪来"的答案样本**；其"故意犯错"军规与 communitytools 的失败学习合成数据生成的两面。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `cyber_zero/prompts/`（两文件） | ✅ 亲读全文 | 双人格提示（选手+环境） |
| `cyber_zero/trajectory_generator.py` `quality_evaluator.py` | ✅ 结构+关键段 | 流程与投票闸确认 |
| `cyber_zero/` 其余（cli/reformatter/llm_client/validation） | ✅ 结构登记 | 未逐行 |
| `benchmarks/`（三套） `enigma-plus/` | ✅ 结构登记 | 挑战资产与脚手架 |
| `README.md` | ✅ 亲读头 | 论文/基准/EnIGMA+ 声明 |

## 8. 结论

**Cyber-Zero 的核心实现思路是：在执行环境不可得的域里用双人格 LLM 模拟替代运行时——选手人格（强制犯错+步数下限+禁提 writeup 的军规防超短完美轨迹）与环境人格（逐字复刻 SWE-agent 编辑器接口与错误语义）以公开 writeup 为 grounding 交替生成长程交互轨迹，多模型质量投票（任一否决提前终止）过滤后重排为 SWE-agent 训练格式，SFT 出的 32B 模型在 InterCode-CTF/NYU/Cybench 三套修复基准上经 EnIGMA+ 脚手架取得 +13.1% 绝对提升。** 它是已审 47 项中唯一的数据生产者：全景观自此闭合"能力消费—能力生产"两层；强制犯错军规与接口复刻式环境模拟是合成训练数据的两个可迁移设计，而其后续工作转向真运行时（CTF-Dojo）本身就是对模拟局限的最好注脚。

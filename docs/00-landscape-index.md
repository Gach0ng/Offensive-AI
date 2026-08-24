# 进攻型 AI / Agentic 全景 —— 开源项目地址索引

> **快照日期**：2026-08-23（数据采集时点 2026-07-20）｜ **本地源码**：`repos/<类别>/<仓库名>/`
> **完整原文**（含 73 篇论文详情、商业产品细节）：本地 `docs/landscape/` 快照（仅本地保留，未入库）
>
> 本索引登记所有 GitHub 仓库地址（克隆与审计对象），并附模型权重、论文、非 GitHub 资源的链接。
> 审计进度见根目录 `TRACKER.md`。

---

## 一、开源 Agent 主列表（56 个，按 Star 降序）

*Star 数为 landscape 快照值（2026-07 采集），仅供排序参考。*

| # | 项目 | 地址 | Stars | 语言 | 类型 | 简介要点 | 本地路径 |
|---|------|------|-------|------|------|---------|---------|
| 1 | shannon | https://github.com/KeygraphHQ/shannon | 45.6k | TypeScript | 渗透 Agent | Web/API 自主白盒 AI 渗透测试 | `repos/agents/shannon` |
| 2 | strix | https://github.com/usestrix/strix | 41.0k | Python | 渗透 Agent | 开源 AI 黑客，发现并修复漏洞 | `repos/agents/strix` |
| 3 | promptfoo | https://github.com/promptfoo/promptfoo | 23.2k | TypeScript | LLM 红队 | LLM 应用红队/渗透/漏扫 | `repos/agents/promptfoo` |
| 4 | pentagi | https://github.com/vxcontrol/pentagi | 20.3k | Go | 渗透 Agent | 全自主 AI 代理系统执行复杂渗透任务 | `repos/agents/pentagi` |
| 5 | PentestGPT | https://github.com/GreyDGL/PentestGPT | 14.2k | Python | 渗透 Agent | LLM 驱动自动化渗透框架（早期标杆） | `repos/agents/PentestGPT` |
| 6 | hexstrike-ai | https://github.com/0x4m4/hexstrike-ai | 10.3k | Python | MCP/渗透 | MCP 服务器驱动 150+ 安全工具 | `repos/agents/hexstrike-ai` |
| 7 | cai | https://github.com/aliasrobotics/cai | 9.4k | Python | 安全 AI 框架 | Cybersecurity AI 框架（Bug Bounty ready） | `repos/agents/cai` |
| 8 | garak | https://github.com/NVIDIA/garak | 8.4k | Python | LLM 红队 | LLM 漏洞扫描器（"LLM 界 nmap"） | `repos/agents/garak` |
| 9 | Nettacker | https://github.com/OWASP/Nettacker | 5.2k | Python | 自动化扫描 | OWASP 自动化渗透/漏扫框架 | `repos/agents/Nettacker` |
| 10 | CyberStrikeAI | https://github.com/Ed1s0nZ/CyberStrikeAI | 5.1k | Go | 渗透 Agent | Go 的 AI 原生安全测试平台 | `repos/agents/CyberStrikeAI` |
| 11 | T3MP3ST | https://github.com/elder-plinius/T3MP3ST | 4.6k | TypeScript | 红队 Agent | 复用本机 AI 编码代理做 0day 猎手的元框架 | `repos/agents/T3MP3ST` |
| 12 | PyRIT | https://github.com/microsoft/PyRIT | 4.1k | Python | LLM 红队 | 微软生成式 AI 风险识别工具 | `repos/agents/PyRIT` |
| 13 | pentestagent | https://github.com/GH05TCREW/pentestagent | 2.8k | Python | 渗透 Agent | 黑盒安全测试 AI Agent（ASIA CCS 2025） | `repos/agents/pentestagent` |
| 14 | vulnhuntr | https://github.com/protectai/vulnhuntr | 2.7k | Python | 漏洞挖掘 | LLM 零样本漏洞发现（首个 AI 自主 0day） | `repos/agents/vulnhuntr` |
| 15 | redamon | https://github.com/samugit83/redamon | 2.2k | Python | 红队 Agent | AI 驱动代理式红队框架 | `repos/agents/redamon` |
| 16 | deepteam | https://github.com/confident-ai/deepteam | 2.1k | Python | LLM 红队 | LLM 红队测试框架 | `repos/agents/deepteam` |
| 17 | Pentest-Swarm-AI | https://github.com/Armur-Ai/Pentest-Swarm-AI | 2.1k | Go | 渗透 Agent | 蜂群架构 + 信息素黑板 + ReAct + MCP | `repos/agents/Pentest-Swarm-AI` |
| 18 | pentest-ai-agents | https://github.com/0xSteph/pentest-ai-agents | 2.0k | Shell | Claude SubAgent | Claude Code 转攻击性安全研究助手 | `repos/agents/pentest-ai-agents` |
| 19 | Cairn | https://github.com/oritera/Cairn | 2.0k | Python | 渗透 Agent | 通用状态空间搜索引擎自主渗透 | `repos/agents/Cairn` |
| 20 | agentic_security | https://github.com/msoedov/agentic_security | 1.9k | Python | LLM 红队 | Agentic LLM 漏洞扫描器 | `repos/agents/agentic_security` |
| 21 | guardian-cli | https://github.com/zakirkun/guardian-cli | 1.7k | Python | 渗透 Agent | 生产级 AI 渗透 CLI（Gemini+LangChain） | `repos/agents/guardian-cli` |
| 22 | buttercup | https://github.com/trailofbits/buttercup | 1.6k | Python | 漏洞修复 | Trail of Bits，AIxCC 第 2 名 CRS | `repos/agents/buttercup` |
| 23 | AutoPentestX | https://github.com/Gowtham-Darkseid/AutoPentestX | 1.4k | Python | 渗透 Agent | 自动化渗透测试与漏洞报告 | `repos/agents/AutoPentestX` |
| 24 | pentest-ai | https://github.com/0xSteph/pentest-ai | 1.3k | Python | 渗透 Agent | MCP 封装 205+ 工具 + 17 专业代理 + 零误报验证 | `repos/agents/pentest-ai` |
| 25 | promptmap | https://github.com/utkusen/promptmap | 1.2k | Python | LLM 红队 | Prompt Injection 自动化扫描器 | `repos/agents/promptmap` |
| 26 | CyberStrike | https://github.com/CyberStrikeus/CyberStrike | 1.2k | TypeScript | 渗透 Agent | 7300+ 安全技能，基于 ATT&CK/CIS/OWASP/NIST | `repos/agents/CyberStrike` |
| 27 | hackingBuddyGPT | https://github.com/ipa-lab/hackingBuddyGPT | 1.2k | Python | 渗透 Agent | 50 行代码内用 LLM 协助伦理黑客 | `repos/agents/hackingBuddyGPT` |
| 28 | pentest-copilot | https://github.com/bugbasesecurity/pentest-copilot | 1.1k | JavaScript | 浏览器助手 | 浏览器端道德黑客辅助 | `repos/agents/pentest-copilot` |
| 29 | nebula | https://github.com/berylliumsec/nebula | 1.1k | Python | 渗透助手 | 自动侦察/笔记/漏洞分析 | `repos/agents/nebula` |
| 30 | LuaN1aoAgent | https://github.com/SanMuzZzZz/LuaN1aoAgent | 1.1k | Python | 渗透 Agent | 全自主渗透，XBOW>90%（广州大学） | `repos/agents/LuaN1aoAgent` |
| 31 | agentic-radar | https://github.com/splx-ai/agentic-radar | 998 | Python | Agent 安全扫描 | LLM Agentic 工作流安全扫描 | `repos/agents/agentic-radar` |
| 32 | reaper | https://github.com/ghostsecurity/reaper | 875 | Go | 测试代理 | 实时验证代理（人/Agent 双友好） | `repos/agents/reaper` |
| 33 | PentesterFlow agent | https://github.com/PentesterFlow/agent | 863 | TypeScript | 渗透 Agent | 终端 Agentic + HITL + Burp 集成 + 覆盖率跟踪 | `repos/agents/agent` |
| 34 | xalgorix | https://github.com/xalgord/xalgorix | 732 | Go | 渗透 Agent | 开源 AI 渗透 Agent | `repos/agents/xalgorix` |
| 35 | Dark-Moon | https://github.com/ASCIT31/Dark-Moon | 728 | Python | 渗透 Agent | Web/云/AD/K8s 多智能体 + 隐私网关 | `repos/agents/Dark-Moon` |
| 36 | ctf-agent | https://github.com/verialabs/ctf-agent | 613 | Python | CTF Agent | 自主 CTF solver（BSidesSF 2026 第一） | `repos/agents/ctf-agent` |
| 37 | Cyber-AutoAgent | https://github.com/westonbrown/Cyber-AutoAgent | 534 | TypeScript | 渗透 Agent | XBOW 验证基准 85%（已归档） | `repos/agents/Cyber-AutoAgent` |
| 38 | AutoPentest-DRL | https://github.com/crond-jaist/AutoPentest-DRL | 438 | Python | RL 渗透 | 深度强化学习自动化渗透 | `repos/agents/AutoPentest-DRL` |
| 39 | BoxPwnr | https://github.com/0ca/BoxPwnr | 428 | Python | 渗透/基准 | HTB/THM/picoCTF 等 15 平台基准框架 | `repos/agents/BoxPwnr` |
| 40 | EVA | https://github.com/ARCANGEL0/EVA | 424 | Python | 渗透 Agent | AI 辅助渗透，多后端 AI 集成 | `repos/agents/EVA` |
| 41 | BreachWeave | https://github.com/m-sec-org/BreachWeave | 419 | TypeScript | 渗透 Agent | Manager/Observer/Solver 多角色架构 | `repos/agents/BreachWeave` |
| 42 | Zen-Ai-Pentest | https://github.com/SHAdd0WTAka/Zen-Ai-Pentest | 413 | Python | 渗透 Agent | 多代理渗透框架 + 合规报告 | `repos/agents/Zen-Ai-Pentest` |
| 43 | communitytools | https://github.com/transilienceai/communitytools | 407 | Python | Claude 工具集 | Claude Code skills/agents/slash commands | `repos/agents/communitytools` |
| 44 | HackSynth | https://github.com/aielte-research/HackSynth | 309 | Python | 渗透 Agent | Planner+Summarizer（arXiv:2412.01778） | `repos/agents/HackSynth` |
| 45 | LLM4Pentest | https://github.com/simon-p-j-r/LLM4Pentest | 297 | — | 研究项目 | LLM 渗透实证分析研究代码 | `repos/agents/LLM4Pentest` |
| 46 | deadend-cli | https://github.com/xoxruns/deadend-cli | 265 | Python | 渗透 Agent | XBOW 黑盒 81%，本地化执行 | `repos/agents/deadend-cli` |
| 47 | BugTrace-AI | https://github.com/yz9yt/BugTrace-AI | 251 | TypeScript | 漏洞追踪 | 已归档，演进为 BugTraceAI v2 | `repos/agents/BugTrace-AI` |
| 48 | seclab-taskflow-agent | https://github.com/GitHubSecurityLab/seclab-taskflow-agent | 212 | Python | Agent 框架 | GitHub SecLab，YAML 多 Agent + CodeQL | `repos/agents/seclab-taskflow-agent` |
| 49 | VulnBot | https://github.com/KHenryAegis/VulnBot | 177 | Python | 渗透 Agent | 多代理协作自主渗透（arXiv:2501.13411） | `repos/agents/VulnBot` |
| 50 | tinyctfer | https://github.com/chainreactors/tinyctfer | 173 | Python | CTF Agent | antix 微型意图运行时 + 元工具 | `repos/agents/tinyctfer` |
| 51 | nyuctf_agents | https://github.com/NYU-LLM-CTF/nyuctf_agents | 151 | Python | CTF Agent | D-CIPHER + Baseline（NYU CTF Bench 配套） | `repos/agents/nyuctf_agents` |
| 52 | AI-OPS | https://github.com/antoninoLorenzo/AI-OPS | 143 | Python | 渗透助手 | 基于开源 LLM 的渗透助手 | `repos/agents/AI-OPS` |
| 53 | cochise | https://github.com/andreashappe/cochise | 126 | Python | AD 渗透 | 自主 Assumed Breach AD 渗透（TOSEM 2025） | `repos/agents/cochise` |
| 54 | mapta | https://github.com/arthurgervais/mapta | 102 | Python | 渗透 Agent | 多 Agent Web 评估 + 端到端利用验证（arXiv:2508.20816） | `repos/agents/mapta` |
| 55 | AI-VAPT | https://github.com/vikramrajkumarmajji/AI-VAPT | 100 | TypeScript | VAPT 框架 | 自主 AI 漏洞评估与渗透测试 | `repos/agents/AI-VAPT` |
| 56 | Cyber-Zero | https://github.com/amazon-science/Cyber-Zero | 99 | Python | 训练框架 | 无运行时训练网络安全代理（Amazon） | `repos/agents/Cyber-Zero` |

## 二、DARPA AIxCC 2025 决赛 CRS（7 队）

| 排名 | 队伍 | 系统 | 地址 | Stars | 本地路径 |
|------|------|------|------|-------|---------|
| 🥇 1 | Team Atlanta | ATLANTIS | https://github.com/Team-Atlanta/aixcc-afc-atlantis | 613 | `repos/aixcc/aixcc-afc-atlantis` |
| 🥈 2 | Trail of Bits | Buttercup | https://github.com/trailofbits/buttercup | 1.6k | `repos/agents/buttercup` |
| 🥉 3 | Theori | RoboDuck | https://github.com/theori-io/aixcc-afc-archive | — | `repos/aixcc/aixcc-afc-archive` |
| 4 | All You Need Is A Fuzzing Brain | FuzzingBrain | https://github.com/o2lab/afc-crs-all-you-need-is-a-fuzzing-brain | — | `repos/aixcc/afc-crs-all-you-need-is-a-fuzzing-brain` |
| 5 | Shellphish | ARTIPHISHELL | https://github.com/shellphish/artiphishell | 137 | `repos/aixcc/artiphishell` |
| 6 | 42-b3yond-6ug | BugBuster | https://github.com/42-b3yond-6ug/42-b3yond-6ug-crs | — | `repos/aixcc/42-b3yond-6ug-crs` |
| 7 | Lacrosse (SIFT) | Lacrosse CRS | https://github.com/siftech/afc-crs-lacrosse | — | `repos/aixcc/afc-crs-lacrosse` |

## 三、进攻型 AI Skill 库（3 个）

| # | 仓库 | 地址 | Stars | 要点 | 本地路径 |
|---|------|------|-------|------|---------|
| 1 | Anthropic-Cybersecurity-Skills | https://github.com/mukul975/Anthropic-Cybersecurity-Skills | 26.1k | 817 技能 / 29 安全域，六框架映射 | `repos/skills/Anthropic-Cybersecurity-Skills` |
| 2 | ctf-skills | https://github.com/ljagiello/ctf-skills | 2.8k | CTF 10 大类技能 + solve-challenge 调度 | `repos/skills/ctf-skills` |
| 3 | awesome-skills-security | https://github.com/Eyadkelleh/awesome-skills-security | 337 | SecLists 打包为 7 类技能 | `repos/skills/awesome-skills-security` |

## 四、安全工具类 MCP Server（7 个）

| # | 仓库 | 地址 | Stars | 语言 | 要点 | 本地路径 |
|---|------|------|-------|------|------|---------|
| 1 | PortSwigger mcp-server | https://github.com/portswigger/mcp-server | 990 | Kotlin | Burp 官方 MCP 桥接（SSE+Stdio） | `repos/mcp/mcp-server` |
| 2 | MCP-Kali-Server | https://github.com/Wh0am123/MCP-Kali-Server | 775 | Python | 已入 Kali 官方源，nmap/hydra/sqlmap/msf 等 | `repos/mcp/MCP-Kali-Server` |
| 3 | mcp-security-hub | https://github.com/FuzzingLabs/mcp-security-hub | 742 | Python | 38 个容器化 MCP / 300+ 工具 | `repos/mcp/mcp-security-hub` |
| 4 | MetasploitMCP | https://github.com/GH05TCREW/MetasploitMCP | 696 | Python | Metasploit 全流程 MCP 桥接 | `repos/mcp/MetasploitMCP` |
| 5 | BloodHound-MCP-AI | https://github.com/MorDavid/BloodHound-MCP-AI | 369 | Python | 75+ 工具，AD 攻击路径分析 | `repos/mcp/BloodHound-MCP-AI` |
| 6 | mcp-shodan | https://github.com/BurtTheCoder/mcp-shodan | 145 | TypeScript | Shodan + CVEDB 查询 | `repos/mcp/mcp-shodan` |
| 7 | pentest-mcp | https://github.com/DMontgomery40/pentest-mcp | 139 | JS/TS | nmap/hydra/sqlmap/nuclei/hashcat + SoW 授权范围 | `repos/mcp/pentest-mcp` |

## 五、Agent 能力评测 Benchmark 仓库（11 个，另有 2 个纯网站）

| # | Benchmark | 地址 | Stars | 时间 | 要点 | 本地路径 |
|---|-----------|------|-------|------|------|---------|
| 1 | CyberSecEval (PurpleLlama) | https://github.com/meta-llama/PurpleLlama | 4.2k | 2023-12 | Meta 出品，防/攻两端 | `repos/benchmarks/PurpleLlama` |
| 2 | XBOW Validation Benchmarks | https://github.com/xbow-engineering/validation-benchmarks | 611 | 2025-06 | 104 道 Web 漏洞挑战 | `repos/benchmarks/validation-benchmarks` |
| 3 | CyberGym | https://github.com/sunblaze-ucb/cybergym | 375 | 2025-06 | 真实漏洞分析（UCB，ICLR 2026） | `repos/benchmarks/cybergym` |
| 4 | Cybench | https://github.com/andyzorigin/cybench | 256 | 2024-08 | 40 道专业 CTF（Stanford，ICLR 2025） | `repos/benchmarks/cybench` |
| 5 | InterCode | https://github.com/princeton-nlp/intercode | 248 | 2023-06 | Bash/SQL/CTF 交互评测（Princeton） | `repos/benchmarks/intercode` |
| 6 | NYU CTF Bench | https://github.com/NYU-LLM-CTF/NYU_CTF_Bench | 153 | 2024-06 | 200 题 CSAW（NeurIPS 2024 D&B） | `repos/benchmarks/NYU_CTF_Bench` |
| 7 | AutoPenBench | https://github.com/lucagioacchini/auto-pen-bench | 86 | 2024-10 | 33 任务（22 In-Vitro + 11 CVE） | `repos/benchmarks/auto-pen-bench` |
| 8 | inspect_cyber | https://github.com/UKGovernmentBEIS/inspect_cyber | 29 | 2025-06 | UK AISI 官方 Agentic Cyber 评估 | `repos/benchmarks/inspect_cyber` |
| 9 | CVE-Bench | https://github.com/uiuc-kang-lab/cve-bench | — | 2025-03 | 40 个 critical CVE（ICML 2025） | `repos/benchmarks/cve-bench` |
| 10 | SEC-bench | https://github.com/SEC-bench/SEC-bench | — | 2025-06 | 200 个 C/C++ CVE（NeurIPS 2025） | `repos/benchmarks/SEC-bench` |
| 11 | CTFTiny | https://github.com/NYU-LLM-CTF/CTFTiny | — | 2025-08 | 50 题轻量 + CTFJudge（AAAI 2026） | `repos/benchmarks/CTFTiny` |

无独立仓库的 Benchmark：**TSecBench**（腾讯云鼎，https://tsecbench.zc.tencent.com/）、**BountyBench**（https://bountybench.github.io/）。

## 六、论文配套 / 研究代码（3 个）

| # | 仓库 | 地址 | 关联论文 | 本地路径 |
|---|------|------|---------|---------|
| 1 | VulnLLM-R | https://github.com/ucsb-mlsec/VulnLLM-R | arXiv:2512.07533 | `repos/research/VulnLLM-R` |
| 2 | UDora | https://github.com/AI-secure/UDora | arXiv:2503.01908（ICML 2025） | `repos/research/UDora` |
| 3 | Tsec-Hackathon | https://github.com/Yeti-791/Tsec-Hackathon | 腾讯云智能渗透黑客松官方资源仓 | `repos/research/Tsec-Hackathon` |

## 七、其他 Awesome 清单（交叉参考）

| # | 仓库 | 地址 | Stars |
|---|------|------|-------|
| 1 | fr0gger/Awesome-GPT-Agents | https://github.com/fr0gger/Awesome-GPT-Agents | 6.6k |
| 2 | jiep/offensive-ai-compilation | https://github.com/jiep/offensive-ai-compilation | 1.4k |
| 3 | ottosulin/awesome-ai-security | https://github.com/ottosulin/awesome-ai-security | 1.0k |
| 4 | TalEliyahu/Awesome-AI-Security | https://github.com/TalEliyahu/Awesome-AI-Security | 714 |
| 5 | raphabot/awesome-cybersecurity-agentic-ai | https://github.com/raphabot/awesome-cybersecurity-agentic-ai | 514 |
| 6 | EvanThomasLuke/Awesome-AI-Hacking-Agents | https://github.com/EvanThomasLuke/Awesome-AI-Hacking-Agents | 258 |
| 7 | ox01024/awesome-offensive-security-ai | https://github.com/ox01024/awesome-offensive-security-ai | 22 |
| 8 | gmh5225/awesome-ai-security | https://github.com/gmh5225/awesome-ai-security | 21 |

## 八、进攻型 / 安全专用开源模型（HuggingFace 权重，非克隆对象）

### A. 无安全对齐 / 弱审查进攻型模型（仅限授权隔离环境研究）

| # | 模型 | 权重地址 | 参数 | 基座 |
|---|------|---------|------|------|
| 1 | Qwythos-9B-Claude-Mythos-5-1M | https://huggingface.co/bestexhibitions/Qwythos-9B-Claude-Mythos-5-1M （Ollama 打包：https://github.com/mickyhq/qwythos） | 9B | Qwen3.5-9B 深度无审查 |
| 2 | WhiteRabbitNeo / DeepHat | https://huggingface.co/WhiteRabbitNeo （Ollama：https://ollama.com/DeepHat） | 7B–70B | Llama/Qwen/DeepSeek |
| 3 | Lily-Cybersecurity-7B-v0.2 | https://huggingface.co/segolilylabs/Lily-Cybersecurity-7B-v0.2 | 7B | Mistral-7B |
| 4 | BaronLLM | https://huggingface.co/AlicanKiraz0 | 7B/8B | — |
| 5 | CyberStrike-OffSec-35B | https://huggingface.co/oyildirim/CyberStrike-OffSec-35B | 35B MoE(A3B) | Qwen3.6-35B-A3B |
| 6 | BugTraceAI-CORE-Ultra-27B | https://huggingface.co/BugTraceAI/BugTraceAI-CORE-Ultra-27B-Q6 | 27B | Qwen3.6-27B |

### B. 安全领域专用模型（保留安全对齐，作检测内核/蓝方陪练）

| # | 模型 | 权重地址 | 参数 | 要点 |
|---|------|---------|------|------|
| 1 | VulnLLM-R-7B | https://huggingface.co/Mungert/VulnLLM-R-7B-GGUF | 7B | 漏洞挖掘推理（arXiv:2512.07533） |
| 2 | Foundation-Sec-8B-Reasoning | https://huggingface.co/fdtn-ai/Foundation-Sec-8B-Reasoning | 8B | Cisco 安全推理模型 |
| 3 | CyberSecQwen-4B | https://huggingface.co/athena129/CyberSecQwen-4B | 4B | CVE→CWE 映射，防御导向 |
| 4 | Meta-SecAlign-8B/70B | https://huggingface.co/facebook/Meta-SecAlign-8B （70B 代码：https://github.com/facebookresearch/Meta_SecAlign） | 8B/70B | 内建 prompt injection 防御 |
| 5 | Titus-CybersecurityLLM-v1.0 | https://huggingface.co/AlicanKiraz0/Titus-CybersecurityLLM-v1.0-mlx-4Bit | 35B MoE | SOC/DFIR 运营 |

## 九、学术论文地址（73 篇，链接速查）

> 详细表格（作者/机构/发表渠道/关联项目）见 landscape 快照。此处按原分组登记地址。

### A. 渗透测试 & 红队 Agent（37 篇）

- A1 Agents4Pentest 综述（2026-07）— https://arxiv.org/abs/2607.02605
- A2 ZERO-APT（2026-06）— https://arxiv.org/abs/2606.05567
- A3 Hackers or Hallucinators?（2026-04）— https://arxiv.org/abs/2604.05719
- A4 PenForge（2026-01）— https://arxiv.org/abs/2601.06910
- A5 PentestEval（2025-12）— https://arxiv.org/abs/2512.14233
- A6 AI vs 渗透测试师实证（2025-12）— https://arxiv.org/abs/2512.09882
- A7 AutoPentester（2025-10）— https://arxiv.org/abs/2510.05605
- A8 xOffense（2025-09）— https://arxiv.org/abs/2509.13021
- A9 攻击树结构化推理（2025-09）— https://arxiv.org/abs/2509.07939
- A10 CurriculumPT（2025-08）— https://www.mdpi.com/2076-3417/15/16/9096
- A11 MAPTA（2025-08）— https://arxiv.org/abs/2508.20816
- A12 Pentest-R1（2025-08）— https://arxiv.org/abs/2508.07382
- A13 PenTest2.0 提权（2025-07）— https://arxiv.org/abs/2507.06742
- A14 LLM 渗透有效性实证（2025-07）— https://arxiv.org/abs/2507.00829
- A15 AutoPentest 漏洞管理（2025-05）— https://arxiv.org/abs/2505.10321
- A16 RedTeamLLM（2025-05）— https://arxiv.org/abs/2505.06913
- A17 CAI（2025-04）— https://arxiv.org/abs/2504.06017
- A18 半自主渗透 Agent（2025-02）— https://arxiv.org/abs/2502.15506
- A19 RapidPen（2025-02）— https://arxiv.org/abs/2502.16730
- A20 PenTest++（2025-02）— https://arxiv.org/abs/2502.09484
- A21 LLM 黑 AD（cochise，2025-02）— https://arxiv.org/abs/2502.04227
- A22 D-CIPHER（2025-02）— https://arxiv.org/abs/2502.10931
- A23 Incalmo（2025-01）— https://arxiv.org/abs/2501.16466
- A24 VulnBot（2025-01）— https://arxiv.org/abs/2501.13411
- A25 HackSynth（2024-12）— https://arxiv.org/abs/2412.01778
- A26 Hacking CTFs with Plain Agents（2024-12）— https://arxiv.org/abs/2412.02776
- A27 PentestAgent（2024-11）— https://arxiv.org/abs/2411.05185
- A28 AutoPT（2024-11）— https://arxiv.org/abs/2411.01236
- A29 BreachSeek（2024-09）— https://arxiv.org/abs/2409.03789
- A30 Hacking, The Lazy Way（2024-09）— https://arxiv.org/abs/2409.09493
- A31 EnIGMA（2024-09）— https://arxiv.org/abs/2409.16165
- A32 CIPHER（2024-08）— https://arxiv.org/abs/2408.11650
- A33 PenHeal（2024-07）— https://arxiv.org/abs/2407.17788
- A34 From Sands to Mansions（2024-07）— https://arxiv.org/abs/2407.16928
- A35 AutoAttacker（2024-03）— https://arxiv.org/abs/2403.01038
- A36 PentestGPT（2023-08）— https://arxiv.org/abs/2308.06782
- A37 Getting pwn'd by AI（2023-08）— https://arxiv.org/abs/2308.00121

### B. 漏洞挖掘 / 利用 / 修复（19 篇）

- B1 FuzzingBrain V2（2026-05）— https://arxiv.org/abs/2605.21779
- B2 Web 漏洞自动复现实证（2025-10）— https://arxiv.org/abs/2510.14700
- B3 VulnRepairEval（2025-09）— https://arxiv.org/abs/2509.03331
- B4 SAST + LLM 协同（2025-09）— https://arxiv.org/abs/2509.15433
- B5 ATLANTIS（2025-09）— https://arxiv.org/abs/2509.14589
- B6 FuzzingBrain V1（2025-09）— https://arxiv.org/abs/2509.07225
- B7 智能合约 Exploit 生成（2025-08）— https://arxiv.org/abs/2508.01371
- B8 LLMxCPG（2025-07）— https://arxiv.org/abs/2507.16585
- B9 MalCodeAI（2025-07）— https://arxiv.org/abs/2507.10898
- B10 VADER（2025-05）— https://arxiv.org/abs/2505.19395
- B11 PwnGPT（2025-04）— https://aclanthology.org/2025.acl-long.562.pdf
- B12 CVE-Bench ICML（2025-03）— https://arxiv.org/abs/2503.17332
- B13 CVE-Bench NAACL（2025-03）— https://aclanthology.org/2025.naacl-long.212/
- B14 CASTLE（2025-03）— https://arxiv.org/abs/2503.09433
- B15 AI Cyber Risk Benchmark（2024-12）— https://arxiv.org/abs/2410.21939
- B16 eyeballvul（2024-07）— https://arxiv.org/abs/2407.08708
- B17 多 Agent 利用 0day（2024-06）— https://arxiv.org/abs/2406.01637
- B18 一日漏洞自动利用（2024-04）— https://arxiv.org/abs/2404.08144
- B19 LLM Agent 自主攻击网站（2024-02）— https://arxiv.org/abs/2402.06664

### C. 评测基准 & 训练方法 & 奠基（17 篇）

- C1 CTFusion（2026-05）— https://arxiv.org/abs/2605.11504
- C2 PACEbench（2025-10）— https://arxiv.org/abs/2510.11688
- C3 CTFTiny + CTFJudge（2025-08）— https://arxiv.org/abs/2508.05674
- C4 Cyber-Zero（2025-07）— https://arxiv.org/abs/2508.00910
- C5 CyberGym（2025-06）— https://arxiv.org/abs/2506.02548
- C6 SEC-bench（2025-06）— https://arxiv.org/abs/2506.11791
- C7 UDora（2025-06）— https://arxiv.org/abs/2503.01908
- C8 评测方法学（2025-04）— https://arxiv.org/abs/2504.10112
- C9 OCCULT（2025-02）— https://arxiv.org/abs/2502.15797
- C10 AutoPenBench（2024-10）— https://arxiv.org/abs/2410.03225
- C11 渗透 LLM 基准（2024-10）— https://arxiv.org/abs/2410.17141
- C12 CYBERSECEVAL 3（2024-08）— https://arxiv.org/abs/2408.10627
- C13 Cybench（2024-08）— https://arxiv.org/abs/2408.08926
- C14 AgentPoison（2024-07）— https://arxiv.org/abs/2407.12784
- C15 NYU CTF Bench（2024-06）— https://arxiv.org/abs/2406.05590
- C16 CyberSecEval v1（2023-12）— https://arxiv.org/abs/2312.04724
- C17 InterCode（2023-06）— https://arxiv.org/abs/2306.14898

## 十、商业产品（研究关注列表，非克隆对象）

**国外 Top**：Anthropic Claude Mythos（anthropic.com/claude/mythos）、Pentera（pentera.io）、XBOW（xbow.com）、Aikido（aikido.dev）、SPLX→Zscaler（splx.ai）、Horizon3.ai NodeZero（horizon3.ai）、Hadrian（hadrian.io）、RunSybil（runsybil.com）、Strix（usestrix.com）、Terra Security（terra.security）、CalypsoAI（calypsoai.com）、Corridor（corridor.dev）、Veria Labs（verialabs.com）、Dreadnode（dreadnode.io）、Mindgard（mindgard.ai）、Hex Security（hex.co）、Harmony Intelligence（harmonyintelligence.com）、Theori Xint（xint.io）、MindFort（mindfort.ai）、Hacktron（hacktron.ai）。

**国内**：绿盟 AI-PTS（nsfocus.com.cn）、京东云 AIPTS（jdcloud.com）、360 破阵子（360.cn）、阿里云 Agentic BAS（developer.aliyun.com/article/1748260）、万径千机/小智（megavector.cn）、长亭无锋（chaitin.cn）、斗象蛙池AI（digpool.cn）、奇安信 AI 加特林（qianxin.com）、安恒恒脑 3.0（dbappsecurity.com.cn）、悬镜灵脉 PTE（pte.xmirror.cn）。

---

*维护说明：索引源更新后（`repos/landscape` 内 `git pull`），同步 `scripts/repos.list` 并在本文件追加/修改对应条目；克隆状态与审计进度统一登记在根目录 `TRACKER.md`。*

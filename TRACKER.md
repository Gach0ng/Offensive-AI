# 进度跟踪总表（TRACKER）

> 由 `bash scripts/gen-tracker.sh` 生成：**克隆列**始终反映磁盘实际状态；
> **审计列/审计文档列**为手工维护（生成脚本不会覆盖已有进度，但请勿改动表格结构）。
> 审计状态建议值：`未开始` / `进行中` / `已完成`。

## 一、开源 Agent 主列表（agents，56）

| 仓库 | 本地路径 | 克隆 | 审计 | 审计文档 |
|------|---------|:----:|:----:|---------|
| [`KeygraphHQ/shannon`](https://github.com/KeygraphHQ/shannon) | `repos/agents/shannon` | ✅ | 已完成 | [docs/audits/KeygraphHQ-shannon.md](docs/audits/KeygraphHQ-shannon.md) |
| [`usestrix/strix`](https://github.com/usestrix/strix) | `repos/agents/strix` | ✅ | 已完成 | [docs/audits/usestrix-strix.md](docs/audits/usestrix-strix.md) |
| [`promptfoo/promptfoo`](https://github.com/promptfoo/promptfoo) | `repos/agents/promptfoo` | ✅ | 已完成 | [docs/audits/promptfoo-promptfoo.md](docs/audits/promptfoo-promptfoo.md) |
| [`vxcontrol/pentagi`](https://github.com/vxcontrol/pentagi) | `repos/agents/pentagi` | ✅ | 已完成 | [docs/audits/vxcontrol-pentagi.md](docs/audits/vxcontrol-pentagi.md) |
| [`GreyDGL/PentestGPT`](https://github.com/GreyDGL/PentestGPT) | `repos/agents/PentestGPT` | ✅ | 已完成 | [docs/audits/GreyDGL-PentestGPT.md](docs/audits/GreyDGL-PentestGPT.md) |
| [`0x4m4/hexstrike-ai`](https://github.com/0x4m4/hexstrike-ai) | `repos/agents/hexstrike-ai` | ✅ | 已完成 | [docs/audits/0x4m4-hexstrike-ai.md](docs/audits/0x4m4-hexstrike-ai.md) |
| [`aliasrobotics/cai`](https://github.com/aliasrobotics/cai) | `repos/agents/cai` | ✅ | 已完成 | [docs/audits/aliasrobotics-cai.md](docs/audits/aliasrobotics-cai.md) |
| [`NVIDIA/garak`](https://github.com/NVIDIA/garak) | `repos/agents/garak` | ✅ | 已完成 | [docs/audits/NVIDIA-garak.md](docs/audits/NVIDIA-garak.md) |
| [`OWASP/Nettacker`](https://github.com/OWASP/Nettacker) | `repos/agents/Nettacker` | ✅ | 已完成 | [docs/audits/OWASP-Nettacker.md](docs/audits/OWASP-Nettacker.md) |
| [`Ed1s0nZ/CyberStrikeAI`](https://github.com/Ed1s0nZ/CyberStrikeAI) | `repos/agents/CyberStrikeAI` | ✅ | 已完成 | [docs/audits/Ed1s0nZ-CyberStrikeAI.md](docs/audits/Ed1s0nZ-CyberStrikeAI.md) |
| [`elder-plinius/T3MP3ST`](https://github.com/elder-plinius/T3MP3ST) | `repos/agents/T3MP3ST` | ✅ | 已完成 | [docs/audits/elder-plinius-T3MP3ST.md](docs/audits/elder-plinius-T3MP3ST.md) |
| [`microsoft/PyRIT`](https://github.com/microsoft/PyRIT) | `repos/agents/PyRIT` | ✅ | 已完成 | [docs/audits/microsoft-PyRIT.md](docs/audits/microsoft-PyRIT.md) |
| [`GH05TCREW/pentestagent`](https://github.com/GH05TCREW/pentestagent) | `repos/agents/pentestagent` | ✅ | 已完成 | [docs/audits/GH05TCREW-pentestagent.md](docs/audits/GH05TCREW-pentestagent.md) |
| [`protectai/vulnhuntr`](https://github.com/protectai/vulnhuntr) | `repos/agents/vulnhuntr` | ✅ | 已完成 | [docs/audits/protectai-vulnhuntr.md](docs/audits/protectai-vulnhuntr.md) |
| [`samugit83/redamon`](https://github.com/samugit83/redamon) | `repos/agents/redamon` | ✅ | 已完成 | [docs/audits/samugit83-redamon.md](docs/audits/samugit83-redamon.md) |
| [`confident-ai/deepteam`](https://github.com/confident-ai/deepteam) | `repos/agents/deepteam` | ✅ | 已完成 | [docs/audits/confident-ai-deepteam.md](docs/audits/confident-ai-deepteam.md) |
| [`Armur-Ai/Pentest-Swarm-AI`](https://github.com/Armur-Ai/Pentest-Swarm-AI) | `repos/agents/Pentest-Swarm-AI` | ✅ | 已完成 | [docs/audits/Armur-Ai-Pentest-Swarm-AI.md](docs/audits/Armur-Ai-Pentest-Swarm-AI.md) |
| [`0xSteph/pentest-ai-agents`](https://github.com/0xSteph/pentest-ai-agents) | `repos/agents/pentest-ai-agents` | ✅ | 已完成 | [docs/audits/0xSteph-pentest-ai-agents.md](docs/audits/0xSteph-pentest-ai-agents.md) |
| [`oritera/Cairn`](https://github.com/oritera/Cairn) | `repos/agents/Cairn` | ✅ | 已完成 | [docs/audits/oritera-Cairn.md](docs/audits/oritera-Cairn.md) |
| [`msoedov/agentic_security`](https://github.com/msoedov/agentic_security) | `repos/agents/agentic_security` | ✅ | 已完成 | [docs/audits/msoedov-agentic_security.md](docs/audits/msoedov-agentic_security.md) |
| [`zakirkun/guardian-cli`](https://github.com/zakirkun/guardian-cli) | `repos/agents/guardian-cli` | ✅ | 已完成 | [docs/audits/zakirkun-guardian-cli.md](docs/audits/zakirkun-guardian-cli.md) |
| [`trailofbits/buttercup`](https://github.com/trailofbits/buttercup) | `repos/agents/buttercup` | ✅ | 已完成 | [docs/audits/trailofbits-buttercup.md](docs/audits/trailofbits-buttercup.md) |
| [`Gowtham-Darkseid/AutoPentestX`](https://github.com/Gowtham-Darkseid/AutoPentestX) | `repos/agents/AutoPentestX` | ✅ | 已完成 | [docs/audits/Gowtham-Darkseid-AutoPentestX.md](docs/audits/Gowtham-Darkseid-AutoPentestX.md) |
| [`0xSteph/pentest-ai`](https://github.com/0xSteph/pentest-ai) | `repos/agents/pentest-ai` | ✅ | 已完成 | [docs/audits/0xSteph-pentest-ai.md](docs/audits/0xSteph-pentest-ai.md) |
| [`utkusen/promptmap`](https://github.com/utkusen/promptmap) | `repos/agents/promptmap` | ✅ | 已完成 | [docs/audits/utkusen-promptmap.md](docs/audits/utkusen-promptmap.md) |
| [`CyberStrikeus/CyberStrike`](https://github.com/CyberStrikeus/CyberStrike) | `repos/agents/CyberStrike` | ✅ | 已完成 | [docs/audits/CyberStrikeus-CyberStrike.md](docs/audits/CyberStrikeus-CyberStrike.md) |
| [`ipa-lab/hackingBuddyGPT`](https://github.com/ipa-lab/hackingBuddyGPT) | `repos/agents/hackingBuddyGPT` | ✅ | 已完成 | [docs/audits/ipa-lab-hackingBuddyGPT.md](docs/audits/ipa-lab-hackingBuddyGPT.md) |
| [`bugbasesecurity/pentest-copilot`](https://github.com/bugbasesecurity/pentest-copilot) | `repos/agents/pentest-copilot` | ✅ | 已完成 | [docs/audits/bugbasesecurity-pentest-copilot.md](docs/audits/bugbasesecurity-pentest-copilot.md) |
| [`berylliumsec/nebula`](https://github.com/berylliumsec/nebula) | `repos/agents/nebula` | ✅ | 已完成 | [docs/audits/berylliumsec-nebula.md](docs/audits/berylliumsec-nebula.md) |
| [`SanMuzZzZz/LuaN1aoAgent`](https://github.com/SanMuzZzZz/LuaN1aoAgent) | `repos/agents/LuaN1aoAgent` | ✅ | 已完成 | [docs/audits/SanMuzZzZz-LuaN1aoAgent.md](docs/audits/SanMuzZzZz-LuaN1aoAgent.md) |
| [`splx-ai/agentic-radar`](https://github.com/splx-ai/agentic-radar) | `repos/agents/agentic-radar` | ✅ | 已完成 | [docs/audits/splx-ai-agentic-radar.md](docs/audits/splx-ai-agentic-radar.md) |
| [`ghostsecurity/reaper`](https://github.com/ghostsecurity/reaper) | `repos/agents/reaper` | ✅ | 已完成 | [docs/audits/ghostsecurity-reaper.md](docs/audits/ghostsecurity-reaper.md) |
| [`PentesterFlow/agent`](https://github.com/PentesterFlow/agent) | `repos/agents/agent` | ✅ | 已完成 | [docs/audits/PentesterFlow-agent.md](docs/audits/PentesterFlow-agent.md) |
| [`xalgord/xalgorix`](https://github.com/xalgord/xalgorix) | `repos/agents/xalgorix` | ✅ | 已完成 | [docs/audits/xalgord-xalgorix.md](docs/audits/xalgord-xalgorix.md) |
| [`ASCIT31/Dark-Moon`](https://github.com/ASCIT31/Dark-Moon) | `repos/agents/Dark-Moon` | ✅ | 已完成 | [docs/audits/ASCIT31-Dark-Moon.md](docs/audits/ASCIT31-Dark-Moon.md) |
| [`verialabs/ctf-agent`](https://github.com/verialabs/ctf-agent) | `repos/agents/ctf-agent` | ✅ | 已完成 | [docs/audits/verialabs-ctf-agent.md](docs/audits/verialabs-ctf-agent.md) |
| [`westonbrown/Cyber-AutoAgent`](https://github.com/westonbrown/Cyber-AutoAgent) | `repos/agents/Cyber-AutoAgent` | ✅ | 已完成 | [docs/audits/westonbrown-Cyber-AutoAgent.md](docs/audits/westonbrown-Cyber-AutoAgent.md) |
| [`crond-jaist/AutoPentest-DRL`](https://github.com/crond-jaist/AutoPentest-DRL) | `repos/agents/AutoPentest-DRL` | ✅ | 已完成 | [docs/audits/crond-jaist-AutoPentest-DRL.md](docs/audits/crond-jaist-AutoPentest-DRL.md) |
| [`0ca/BoxPwnr`](https://github.com/0ca/BoxPwnr) | `repos/agents/BoxPwnr` | ✅ | 已完成 | [docs/audits/0ca-BoxPwnr.md](docs/audits/0ca-BoxPwnr.md) |
| [`ARCANGEL0/EVA`](https://github.com/ARCANGEL0/EVA) | `repos/agents/EVA` | ✅ | 已完成 | [docs/audits/ARCANGEL0-EVA.md](docs/audits/ARCANGEL0-EVA.md) |
| [`m-sec-org/BreachWeave`](https://github.com/m-sec-org/BreachWeave) | `repos/agents/BreachWeave` | ✅ | 已完成 | [docs/audits/m-sec-org-BreachWeave.md](docs/audits/m-sec-org-BreachWeave.md) |
| [`SHAdd0WTAka/Zen-Ai-Pentest`](https://github.com/SHAdd0WTAka/Zen-Ai-Pentest) | `repos/agents/Zen-Ai-Pentest` | ✅ | 已完成 | [docs/audits/SHAdd0WTAka-Zen-Ai-Pentest.md](docs/audits/SHAdd0WTAka-Zen-Ai-Pentest.md) |
| [`transilienceai/communitytools`](https://github.com/transilienceai/communitytools) | `repos/agents/communitytools` | ✅ | 已完成 | [docs/audits/transilienceai-communitytools.md](docs/audits/transilienceai-communitytools.md) |
| [`aielte-research/HackSynth`](https://github.com/aielte-research/HackSynth) | `repos/agents/HackSynth` | ✅ | 已完成 | [docs/audits/aielte-research-HackSynth.md](docs/audits/aielte-research-HackSynth.md) |
| [`simon-p-j-r/LLM4Pentest`](https://github.com/simon-p-j-r/LLM4Pentest) | `repos/agents/LLM4Pentest` | ✅ | 已完成 | [docs/audits/simon-p-j-r-LLM4Pentest.md](docs/audits/simon-p-j-r-LLM4Pentest.md) |
| [`xoxruns/deadend-cli`](https://github.com/xoxruns/deadend-cli) | `repos/agents/deadend-cli` | ✅ | 已完成 | [docs/audits/xoxruns-deadend-cli.md](docs/audits/xoxruns-deadend-cli.md) |
| [`yz9yt/BugTrace-AI`](https://github.com/yz9yt/BugTrace-AI) | `repos/agents/BugTrace-AI` | ✅ | 已完成 | [docs/audits/yz9yt-BugTrace-AI.md](docs/audits/yz9yt-BugTrace-AI.md) |
| [`GitHubSecurityLab/seclab-taskflow-agent`](https://github.com/GitHubSecurityLab/seclab-taskflow-agent) | `repos/agents/seclab-taskflow-agent` | ✅ | 已完成 | [docs/audits/GitHubSecurityLab-seclab-taskflow-agent.md](docs/audits/GitHubSecurityLab-seclab-taskflow-agent.md) |
| [`KHenryAegis/VulnBot`](https://github.com/KHenryAegis/VulnBot) | `repos/agents/VulnBot` | ✅ | 已完成 | [docs/audits/KHenryAegis-VulnBot.md](docs/audits/KHenryAegis-VulnBot.md) |
| [`chainreactors/tinyctfer`](https://github.com/chainreactors/tinyctfer) | `repos/agents/tinyctfer` | ✅ | 已完成 | [docs/audits/chainreactors-tinyctfer.md](docs/audits/chainreactors-tinyctfer.md) |
| [`NYU-LLM-CTF/nyuctf_agents`](https://github.com/NYU-LLM-CTF/nyuctf_agents) | `repos/agents/nyuctf_agents` | ✅ | 已完成 | [docs/audits/NYU-LLM-CTF-nyuctf_agents.md](docs/audits/NYU-LLM-CTF-nyuctf_agents.md) |
| [`antoninoLorenzo/AI-OPS`](https://github.com/antoninoLorenzo/AI-OPS) | `repos/agents/AI-OPS` | ✅ | 已完成 | [docs/audits/antoninoLorenzo-AI-OPS.md](docs/audits/antoninoLorenzo-AI-OPS.md) |
| [`andreashappe/cochise`](https://github.com/andreashappe/cochise) | `repos/agents/cochise` | ✅ | 已完成 | [docs/audits/andreashappe-cochise.md](docs/audits/andreashappe-cochise.md) |
| [`arthurgervais/mapta`](https://github.com/arthurgervais/mapta) | `repos/agents/mapta` | ✅ | 已完成 | [docs/audits/arthurgervais-mapta.md](docs/audits/arthurgervais-mapta.md) |
| [`vikramrajkumarmajji/AI-VAPT`](https://github.com/vikramrajkumarmajji/AI-VAPT) | `repos/agents/AI-VAPT` | ✅ | 已完成 | [docs/audits/vikramrajkumarmajji-AI-VAPT.md](docs/audits/vikramrajkumarmajji-AI-VAPT.md) |
| [`amazon-science/Cyber-Zero`](https://github.com/amazon-science/Cyber-Zero) | `repos/agents/Cyber-Zero` | ✅ | 已完成 | [docs/audits/Cyber-Zero.md](docs/audits/Cyber-Zero.md) |

## 二、DARPA AIxCC 2025 决赛 CRS（aixcc）

| 仓库 | 本地路径 | 克隆 | 审计 | 审计文档 |
|------|---------|:----:|:----:|---------|
| [`Team-Atlanta/aixcc-afc-atlantis`](https://github.com/Team-Atlanta/aixcc-afc-atlantis) | `repos/aixcc/aixcc-afc-atlantis` | ✅ | 未开始 |  |
| [`theori-io/aixcc-afc-archive`](https://github.com/theori-io/aixcc-afc-archive) | `repos/aixcc/aixcc-afc-archive` | ✅ | 已完成 | [docs/audits/theori-io-aixcc-afc-archive.md](docs/audits/theori-io-aixcc-afc-archive.md) |
| [`o2lab/afc-crs-all-you-need-is-a-fuzzing-brain`](https://github.com/o2lab/afc-crs-all-you-need-is-a-fuzzing-brain) | `repos/aixcc/afc-crs-all-you-need-is-a-fuzzing-brain` | ✅ | 未开始 |  |
| [`shellphish/artiphishell`](https://github.com/shellphish/artiphishell) | `repos/aixcc/artiphishell` | ✅ | 已完成 | [docs/audits/shellphish-artiphishell.md](docs/audits/shellphish-artiphishell.md) |
| [`42-b3yond-6ug/42-b3yond-6ug-crs`](https://github.com/42-b3yond-6ug/42-b3yond-6ug-crs) | `repos/aixcc/42-b3yond-6ug-crs` | ✅ | 未开始 |  |
| [`siftech/afc-crs-lacrosse`](https://github.com/siftech/afc-crs-lacrosse) | `repos/aixcc/afc-crs-lacrosse` | ✅ | 未开始 |  |

## 三、Skill 库（skills）

| 仓库 | 本地路径 | 克隆 | 审计 | 审计文档 |
|------|---------|:----:|:----:|---------|
| [`mukul975/Anthropic-Cybersecurity-Skills`](https://github.com/mukul975/Anthropic-Cybersecurity-Skills) | `repos/skills/Anthropic-Cybersecurity-Skills` | ✅ | 未开始 |  |
| [`ljagiello/ctf-skills`](https://github.com/ljagiello/ctf-skills) | `repos/skills/ctf-skills` | ✅ | 未开始 |  |
| [`Eyadkelleh/awesome-skills-security`](https://github.com/Eyadkelleh/awesome-skills-security) | `repos/skills/awesome-skills-security` | ✅ | 未开始 |  |

## 四、MCP Server（mcp）

| 仓库 | 本地路径 | 克隆 | 审计 | 审计文档 |
|------|---------|:----:|:----:|---------|
| [`PortSwigger/mcp-server`](https://github.com/PortSwigger/mcp-server) | `repos/mcp/mcp-server` | ✅ | 未开始 |  |
| [`Wh0am123/MCP-Kali-Server`](https://github.com/Wh0am123/MCP-Kali-Server) | `repos/mcp/MCP-Kali-Server` | ✅ | 未开始 |  |
| [`FuzzingLabs/mcp-security-hub`](https://github.com/FuzzingLabs/mcp-security-hub) | `repos/mcp/mcp-security-hub` | ✅ | 未开始 |  |
| [`GH05TCREW/MetasploitMCP`](https://github.com/GH05TCREW/MetasploitMCP) | `repos/mcp/MetasploitMCP` | ✅ | 未开始 |  |
| [`MorDavid/BloodHound-MCP-AI`](https://github.com/MorDavid/BloodHound-MCP-AI) | `repos/mcp/BloodHound-MCP-AI` | ✅ | 未开始 |  |
| [`BurtTheCoder/mcp-shodan`](https://github.com/BurtTheCoder/mcp-shodan) | `repos/mcp/mcp-shodan` | ✅ | 未开始 |  |
| [`DMontgomery40/pentest-mcp`](https://github.com/DMontgomery40/pentest-mcp) | `repos/mcp/pentest-mcp` | ✅ | 未开始 |  |

## 五、Benchmark（benchmarks）

| 仓库 | 本地路径 | 克隆 | 审计 | 审计文档 |
|------|---------|:----:|:----:|---------|
| [`meta-llama/PurpleLlama`](https://github.com/meta-llama/PurpleLlama) | `repos/benchmarks/PurpleLlama` | ✅ | 未开始 |  |
| [`xbow-engineering/validation-benchmarks`](https://github.com/xbow-engineering/validation-benchmarks) | `repos/benchmarks/validation-benchmarks` | ✅ | 未开始 |  |
| [`sunblaze-ucb/cybergym`](https://github.com/sunblaze-ucb/cybergym) | `repos/benchmarks/cybergym` | ✅ | 未开始 |  |
| [`andyzorigin/cybench`](https://github.com/andyzorigin/cybench) | `repos/benchmarks/cybench` | ✅ | 未开始 |  |
| [`princeton-nlp/intercode`](https://github.com/princeton-nlp/intercode) | `repos/benchmarks/intercode` | ✅ | 未开始 |  |
| [`NYU-LLM-CTF/NYU_CTF_Bench`](https://github.com/NYU-LLM-CTF/NYU_CTF_Bench) | `repos/benchmarks/NYU_CTF_Bench` | ✅ | 未开始 |  |
| [`lucagioacchini/auto-pen-bench`](https://github.com/lucagioacchini/auto-pen-bench) | `repos/benchmarks/auto-pen-bench` | ✅ | 未开始 |  |
| [`UKGovernmentBEIS/inspect_cyber`](https://github.com/UKGovernmentBEIS/inspect_cyber) | `repos/benchmarks/inspect_cyber` | ✅ | 未开始 |  |
| [`uiuc-kang-lab/cve-bench`](https://github.com/uiuc-kang-lab/cve-bench) | `repos/benchmarks/cve-bench` | ✅ | 未开始 |  |
| [`SEC-bench/SEC-bench`](https://github.com/SEC-bench/SEC-bench) | `repos/benchmarks/SEC-bench` | ✅ | 未开始 |  |
| [`NYU-LLM-CTF/CTFTiny`](https://github.com/NYU-LLM-CTF/CTFTiny) | `repos/benchmarks/CTFTiny` | ✅ | 已完成 | [docs/audits/NYU-LLM-CTF-CTFTiny.md](docs/audits/NYU-LLM-CTF-CTFTiny.md) |

## 六、研究代码（research）

| 仓库 | 本地路径 | 克隆 | 审计 | 审计文档 |
|------|---------|:----:|:----:|---------|
| [`ucsb-mlsec/VulnLLM-R`](https://github.com/ucsb-mlsec/VulnLLM-R) | `repos/research/VulnLLM-R` | ✅ | 未开始 |  |
| [`AI-secure/UDora`](https://github.com/AI-secure/UDora) | `repos/research/UDora` | ✅ | 未开始 |  |
| [`Yeti-791/Tsec-Hackathon`](https://github.com/Yeti-791/Tsec-Hackathon) | `repos/research/Tsec-Hackathon` | ✅ | 未开始 |  |

## 七、Awesome 清单（awesome-lists）

| 仓库 | 本地路径 | 克隆 | 审计 | 审计文档 |
|------|---------|:----:|:----:|---------|
| [`fr0gger/Awesome-GPT-Agents`](https://github.com/fr0gger/Awesome-GPT-Agents) | `repos/awesome-lists/Awesome-GPT-Agents` | ✅ | 未开始 |  |
| [`jiep/offensive-ai-compilation`](https://github.com/jiep/offensive-ai-compilation) | `repos/awesome-lists/offensive-ai-compilation` | ✅ | 未开始 |  |
| [`ottosulin/awesome-ai-security`](https://github.com/ottosulin/awesome-ai-security) | `repos/awesome-lists/awesome-ai-security` | ✅ | 未开始 |  |
| [`TalEliyahu/Awesome-AI-Security`](https://github.com/TalEliyahu/Awesome-AI-Security) | `repos/awesome-lists/Awesome-AI-Security` | ✅ | 未开始 |  |
| [`raphabot/awesome-cybersecurity-agentic-ai`](https://github.com/raphabot/awesome-cybersecurity-agentic-ai) | `repos/awesome-lists/awesome-cybersecurity-agentic-ai` | ✅ | 未开始 |  |
| [`EvanThomasLuke/Awesome-AI-Hacking-Agents`](https://github.com/EvanThomasLuke/Awesome-AI-Hacking-Agents) | `repos/awesome-lists/Awesome-AI-Hacking-Agents` | ✅ | 未开始 |  |
| [`ox01024/awesome-offensive-security-ai`](https://github.com/ox01024/awesome-offensive-security-ai) | — | ❌ | 未开始 |  |
| [`gmh5225/awesome-ai-security`](https://github.com/gmh5225/awesome-ai-security) | `repos/awesome-lists/awesome-ai-security` | ✅ | 未开始 |  |

## 八、模型配套代码（models-code）

| 仓库 | 本地路径 | 克隆 | 审计 | 审计文档 |
|------|---------|:----:|:----:|---------|
| [`mickyhq/qwythos`](https://github.com/mickyhq/qwythos) | `repos/models-code/qwythos` | ✅ | 未开始 |  |
| [`facebookresearch/Meta_SecAlign`](https://github.com/facebookresearch/Meta_SecAlign) | `repos/models-code/Meta_SecAlign` | ✅ | 未开始 |  |

## 九、索引源（landscape）

| 仓库 | 本地路径 | 克隆 | 审计 | 审计文档 |
|------|---------|:----:|:----:|---------|
| [`Yeti-791/Awesome-Offensive-AI-Agentic-Landscape`](https://github.com/Yeti-791/Awesome-Offensive-AI-Agentic-Landscape) | `repos/landscape/Awesome-Offensive-AI-Agentic-Landscape` | ✅ | 未开始 |  |


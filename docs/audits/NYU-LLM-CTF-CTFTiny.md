# NYU-LLM-CTF/CTFTiny 逐行代码审计

> 审计对象：CTFTiny —— **AAAI'26 论文配套轻量基准**（《Towards Effective Offensive Security LLM Agents: Hyperparameter Tuning, LLM as a Judge, and a Lightweight CTF Benchmark》，arXiv:2508.05674）：50 道精选 CTF 题（六类：cry/for/pwn/rev/msc/web，从 CSAW 等真题遴选，难度 Very Easy→Hard 分级），每题带 `challenge.json` 元数据+`test_solver/`（求解器+test.sh 判分脚本）。**纯基准资产、零 agent 代码**——配套裁判模型 CTFJudge 另仓。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/NYU-LLM-CTF/CTFTiny |
| 本地路径 | `repos/benchmarks/CTFTiny/`（landscape 归入 benchmarks 类，非 agents） |
| 审计基线 commit | `f1c9531`（Create LICENSE） |
| 语言 / 规模 | 挑战资产 ~3,560 行 Python（求解器/服务端）+ 50 个 challenge.json + Dockerfile/docker-compose |
| Landscape 定位 | 类型：Benchmark / 一句话：轻量 CTF 基准（50 题六类分级+自带判分求解器） |
| License | MIT |
| 关联论文 | **AAAI'26 论文**（arXiv:2508.05674）；LLM4Pentest 清单收录同论文（"Hyperparameter Tuning, LLM as a Judge, and a Lightweight CTF Benchmark"带代码链接即本仓） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：LLM 进攻安全 agent 的**低成本评测**——大基准（Cybench 40 题/NYU 200 题）跑一轮成本高，CTFTiny 用 50 道精选题做轻量迭代评测（论文同时研究超参调优与 LLM-as-judge）。
- **AI 真伪核查**：**N/A（纯基准资产）**——无 agent/LLM 代码；挑战的 solver.py 是确定性解题脚本（供 test.sh 判分），非 AI。
- **差异化定位**：与 Cyber-Zero 的修复基准同源生态（NYU-LLM-CTF 组织），但方向相反——那边修复大基准，这边**精选小基准**；"轻量"是第一设计目标。

## 2. 结构与内容（盘点亲证）

```
ctftiny/{cry,for,msc,pwn,rev,web}/<challenge>/
  challenge.json（name/category/description/flag/points/files/reference——出处链接可溯源真题）
  原题资产（ciphertext/二进制/服务端 py/Dockerfile+docker-compose——网络题可起容器）
  test_solver/{solver.py,test.sh}（确定性求解器+判分脚本：set -euo pipefail+跑 solver）
```

- **50 题六类**：cry 12/for 2/pwn 11/rev 15/msc若干/web 若干；难度 Very Easy（puffin/checker/unvirtualization/whataxor）→ Hard（ecxor/baby_boi/roppity/unlimited_subway 等）；**真题溯源**（challenge.json 的 reference 指向 CSAW 2017-2023 等原始仓库——如 babycrypto 引 CSAW'18 Quals）。
- 挑战 Python 资产为原题服务端/求解器（如 Beyond-Quantum 的 lattice 加密服务 149 行+easy-malleability 变体、ECXOR 的 RFC8032 EdDSA 实现）——非 agent 代码。
- README 全表列出 50 题（类别/赛事年份/名称/难度）——即论文表 1 的机器可读形态。

## 3. 与本审计生态的交叉

- **LLM4Pentest（已审 #43）收录其母论文**（"Hyperparameter Tuning, LLM as a Judge…"带本仓代码链接）——学术资源库与基准实体的闭环。
- 配套 **CTFJudge**（LLM 裁判模型，另仓）——论文三贡献（调参/裁判/轻量基准）中裁判部分的载体；与 garak 的 SelfAsk 裁判、xalgorix 的验证器构成"裁判"谱系的学术端。
- 与 Cyber-Zero 修复基准、BoxPwnr 16 平台、HackSynth 200 题构成**基准光谱的"轻量精选"端**：大基准管全面性、小基准管迭代速度——论文用同一基准做超参扫描（观察长度等网格的又一消费者）。

## 4. 值得借鉴的设计与技巧

1. **轻量基准的自足判分**：每题自带确定性 solver+test.sh（`set -euo pipefail`）——判分不依赖平台（对照 BoxPwnr 的 CTFd 平台判旗），本地一条命令验一题。
2. **真题溯源字段**（challenge.json 的 reference 指原始赛题仓库）——基准的可溯源性（对照 BoxPwnr 诚信条款防 writeup 检索：真题公开 writeup 存在，论文的调参/裁判研究须自带此污染意识）。
3. 难度四级显式标注进 README 表——超参研究按难度分桶的现成维度。
4. 网络题带 Docker 起容器资产（docker-compose+Dockerfile+server.py）。

## 5. 局限与改进点

- 50 题容量小且类别不均（for 仅 2 题）；真题公开 writeup 的污染面（模型训练数据大概率见过 CSAW 解法）——作为"能力"基准可信度弱于后训练截止设计（对照 T3MP3ST CVE-Zero）。
- 无 harness/trace 采集（需配 CTFJudge 或自接 agent）；纯资产仓库按基准标准从简审计。

## 6. 与其他已审计项目的对比

| 维度 | CTFTiny（本项目） | Cyber-Zero 基准 | BoxPwnr | HackSynth |
|---|---|---|---|---|
| 定位 | **轻量精选基准** | 修复大基准×3 | 16 平台 harness | 新基准×2 |
| 规模 | 50 题 | 3 套大基准 | 4,749 题 | 200 题 |
| 判分 | **自带 solver+test.sh** | 平台 | 平台判旗 | 摘要含旗 |
| 溯源 | **真题 reference 字段** | 修复记录 | 公开 traces | 论文快照 |

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `README.md` | ✅ 亲读 | 50 题全表+论文链接 |
| `ctftiny/cry/babycrypto/` | ✅ 亲读 | challenge.json+test.sh 判分模式样本 |
| `ctftiny/` 其余 49 题 | ✅ 结构确认 | 清单+部分挑战资产抽读 |
| 挑战 Python 资产（solver/server） | ✅ 定性确认 | 原题代码非 agent 代码 |

## 8. 结论

**CTFTiny 是基准光谱"轻量精选"端的纯资产样本：50 道真题（六类/四级难度/出处可溯）各带 challenge.json 元数据与"确定性 solver+test.sh"自足判分，网络题附 Docker 起容器资产，服务于 AAAI'26 论文的超参调优与 LLM-as-judge 研究（裁判模型 CTFJudge 另仓）。** 其价值在于与本景观的交叉闭环（LLM4Pentest 收录其论文、与 Cyber-Zero 同组织互补大小基准），以及"自带判分"的基准自足性设计；真题 writeup 污染面是其作为能力基准的已知边界。按基准资产标准从简审计。

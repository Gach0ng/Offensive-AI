# westonbrown/Cyber-AutoAgent 逐行代码审计

> 审计对象：Cyber-AutoAgent —— **已归档**的自主渗透 agent（"85% XBOW 验证基准后归档"——作者转向全职专注而主动封存而非放任停滞）：Python ~48.9k 行，**AWS Strands 框架**底座（Bedrock/LiteLLM/Ollama 三通道）；招牌是 **"Ghost" 系统提示**（四问认知框架+0-100% 数值置信度带适应触发+证据军规）与 **Langfuse 提示管理**（本地模板自动 seed 到远端+TTL 缓存回退）+ **operation_plugins 模块化作战清单**（YAML 声明能力/目标/接口契约）。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/westonbrown/Cyber-AutoAgent |
| 本地路径 | `repos/agents/Cyber-AutoAgent/` |
| 审计基线 commit | `54897ff`（Update README to include experimental software warning——归档态） |
| 语言 / 规模 | Python ~48,868 行（react_bridge_handler 2,988+memory 1,682+config 1,445+evaluation 1,281+prompts/factory 1,261）+ React 终端前端（TS 1,321） |
| Landscape 定位 | 类型：渗透 Agent / Stars：中 / 一句话：Strands 底座的 Ghost 提示驱动自主渗透（85% XBOW 后归档） |
| License | 见仓库 |
| 关联论文 | 无（docs/ 九篇配套文档：prompt_management/prompt_optimizer/memory/observability-evaluation…） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：黑盒渗透的自主执行——自然语言推理+动态工具选择+证据收集；React 终端 UI 为默认界面。
- **AI 真伪核查**：真 AI（Strands agent 框架+三模型通道+提示工厂）。
- **差异化定位**：**提示工程的体系化**——认知框架/置信度算术/证据军规全进系统提示，配套 Langfuse 提示版本管理与模块化作战插件。

## 2. 架构总览

```
React 终端前端（DirectDockerService.ts 1,321——交互配置/实时监控/引导式设置）
   ▼
src/modules/
  agents/（cyber_autoagent+report_agent）
  handlers/react/react_bridge_handler(2,988 ★：agent 桥接——工具执行/记忆/评估接线)
  prompts/（factory 1,261 ★+templates/system_prompt.md ★Ghost/tools_guide/report_agent）
  operation_plugins/ ×5（general/ctf/threat_emulation/code_security/context_navigator——
      module.yaml 声明式能力清单）
  tools/memory(1,682 ★)/config(1,445)/evaluation(1,281+trace_parser——XBOW 评测接线)
  interfaces/react（前端）
benchmark_harness/ + docker/ + docs/×9
模型：AWS Bedrock（Strands 原生）/Litellm/Ollama
```

## 3. 核心模块精读（审计主体；49k 行大仓亲读计划：Ghost 提示+插件+提示工厂）

### 3.1 Ghost 系统提示（system_prompt.md 头 80 行亲读）——认知框架的提示词化范本

- **主指令集**："**目标优先**——每个动作前回答'这如何推进目标？'答不上=动作不必要"；"**操作边界**——你是外部操作者：工作区=工件目录路径，目标基础设施=仅经网络协议可达的远端；**对目标执行文件系统/容器命令违反操作约束**"（自检句："访问的是我的工作区还是目标基础设施？"）；"无工件路径不得声称结果；**绝不硬编码成功旗——运行时推导**"（反伪造：成功判定不准写死）；HIGH/CRITICAL 须 Proof Pack（工件路径+理由）否则标 Hypothesis。
- **认知框架（每次动作前显式推理）**：四问——"我知道什么（已确认观察）/我想什么（**带 0-100% 置信度的假设**）/我测什么（最小下一动作）/如何验证（预期 vs 实际）"；**推理句式模板**："[观察]提示[假设]。置信度：65%。测试：[动作]。预期：[结果]。"——把假设检验塞进每步输出格式。
- **置信度算术与适应触发**：证据确认+20%/证伪-30%/模糊-10%；**阈值带**——">80% 直接利用/50-80% 假设测试并行探索/<50% 收集信息或部署蜂群"；"同法 3 失败→置信降→触发适应"；"<50% 必须换法或部署蜂群/<30% 必须换能力类/>60% 预算+<50% 置信→立即蜂群"——deadend-cli 置信度 rubric 的更激进表亲（这边触发蜂群部署）。
- **执行原则**：进度测试（"每个能力后问：这推进目标吗？测试过直接使用吗？否→换能力不是迭代同法"）；最小动作（"选信息量最大化的最小动作"）；错误恢复三段（记录→归因→改计划再动）。
- **证据与验证军规**：证据标准（HIGH/CRITICAL 的 Proof Pack+**对照组**——"无工件=假设"）；通信规范（严重度先行/工具间最多两行/立即存储）；真实性（"绝不发明数据/不确定就声明并验证/**托管端点≠发现除非证明滥用**"——托管端点不算发现）；**Finding 写入仪式**（validation_status=verified|hypothesis+Proof Pack+[STEPS] 七要素：前置/命令/预期/实际/工件/环境/清理/注记）。

### 3.2 提示工厂与 Langfuse 管理（factory.py 头亲读）

- **本地模板→远端 Langfuse 的自动 seed**（REST /api/public/v2/prompts+Basic Auth）：本地 system_prompt.md 等映射到远端提示名，_lf_create_prompt_version 带 commit="seed"——**提示的版本管理外置**（对照 T3MP3ST verify-claims 的数字重推导：这边是提示资产的托管）；TTL 缓存（300s）+静默回退（Langfuse 不可用即用本地）。
- docs/prompt_optimizer.md——提示优化器文档（提示迭代工具链的组成部分）。

### 3.3 operation_plugins（ctf/module.yaml 亲读）

- **声明式模块清单**：name/version/cognitive_level(4)/configuration.approach（"家族驱动发现与利用+**精选优先探针+显式成功态终止**"）/capabilities ×9（旗模式识别/XSS sink 导向测试与成功态检测/系统化 IDOR 参数篡改/注入三态/文件路径控制/SSRF 最小请求/GraphQL/精选优先端点发现——**"先高产出路径后广谱 fuzz"**）/supported_targets/finding_categories——**作战知识以 YAML 插件分发**（对照 pentest-ai-agents 的 MD 技能：同为声明式，这边带接口契约 accepts_from/provides_to）。
- 五模块：general/ctf/threat_emulation/code_security/context_navigator。

### 3.4 其余（结构确认）

- react_bridge_handler 2,988 行（agent 桥接主体）；tools/memory 1,682（分层记忆——docs/memory.md）；evaluation 1,281+trace_parser（**XBOW 评测接线**——85% 的测量面）；React 前端 DirectDockerService。

## 4. 值得借鉴的设计与技巧

1. **认知框架进系统提示**（四问+置信度数值+推理句式模板+阈值适应触发含蜂群部署）——把科学方法做成 agent 的常驻思维格式的最完整实现之一（与 LuaN1aoAgent 契约式认识论对照：那边防错误结论、这边驱动动作选择）。
2. **"绝不硬编码成功旗——运行时推导"+"托管端点≠发现"**——反伪造与反通胀的两条硬措辞。
3. **Finding 写入仪式**（七要素 STEPS+validation_status+Proof Pack）。
4. **Langfuse 提示管理**（本地 seed 远端+TTL 缓存+静默回退）——提示资产的版本化托管。
5. 声明式 operation_plugins（cognitive_level/approach/capabilities/接口契约）；精选优先端点发现原则。
6. **归档决策本身**："达成 85% 后选择归档而非放任停滞"——项目治理的诚实姿态。

## 5. 局限与改进点

- 已归档（无维护）；49k 行仅提示/插件/工厂深读（react_bridge/memory/evaluation 未逐行）。
- Strands/Bedrock 生态绑定（Litellm/Ollama 通道存在但主推 AWS）；置信度算术为提示层（无执行校验——对照 deadend 同限）。
- 85% XBOW 为自报（benchmark_harness 在库但未逐个核验）。

## 6. 与其他已审计项目的对比

| 维度 | Cyber-AutoAgent（本项目） | deadend-cli | T3MP3ST | LuaN1aoAgent |
|---|---|---|---|---|
| 认知框架 | **四问+置信度+适应触发** | 五档带+rubric | COA 矩阵 | 因果边界+oracle |
| 置信度用途 | **驱动蜂群部署** | fail/expand/refine | — | — |
| 反伪造 | "禁硬编码旗" | 反例清单 | 引文核验 | ground claim |
| 提示管理 | **Langfuse 版本化** | jinja2 块 | sentinel 分界 | frontmatter 配置 |
| 形态 | Strands+React TUI | 自研 | 自研 | Pi SDK |

与 deadend-cli 构成置信度驱动的双样本（那边 rubric 算术、这边阈值带+蜂群触发）；Langfuse 提示管理是全景观唯一的提示资产托管实现。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `prompts/templates/system_prompt.md` | ✅ 亲读头 | 80/~150（主指令+认知框架+执行+证据） |
| `operation_plugins/ctf/module.yaml` | ✅ 亲读 | 声明式清单全文头 |
| `prompts/factory.py` | ✅ 亲读头 | Langfuse 管理函数族 |
| `handlers/` `tools/` `evaluation/` `agents/` 前端 | ✅ 结构登记 | 未逐行 |
| `README.md` | ✅ 亲读 | 归档声明/快速开始/文档表 |

## 8. 结论

**Cyber-AutoAgent 的核心实现思路是：以认知框架驱动的 Strands 底座自主渗透——Ghost 系统提示把四问假设检验（我知道/我想+置信度/我测/如何验证）、0-100% 数值置信度的阈值适应（低置信触发换法乃至蜂群部署）、证据军规（Proof Pack+对照组+"禁硬编码旗"+"托管端点≠发现"+七要素写入仪式）做成 agent 的常驻思维格式，提示资产经 Langfuse 版本化托管（本地 seed+缓存回退），作战知识以声明式 YAML 插件分发（能力/目标/接口契约），React 终端与 XBOW 评测接线配套。** 85% XBOW 后的主动归档是其治理注脚；认知框架的提示词化与 Langfuse 提示管理是两个可移植资产——置信度驱动的双样本之一（与 deadend-cli 并读）。

# msoedov/agentic_security 逐行代码审计

> 审计对象：Agentic Security —— 轻量级 LLM 漏洞扫描器（语料驱动 fuzzer + Web UI）：HF 越狱数据集语料 × 拒答启发式判定 × 贝叶斯早停 × many-shot 上下文注入。
>
> 审计方法注记：核心约 9k 行 Python。核心链（fuzzer 全文、拒答检测器全文、自适应攻击模板、数据集目录、MSJ 机制、默认值面）亲读。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/msoedov/agentic_security |
| 本地路径 | `repos/agents/agentic_security/` |
| 审计基线 commit | `1ef131421eef3fbcf69c942a68f7df456120931d`（2026-08-18，Python 3.14 基线，活跃维护） |
| 语言 / 规模 | Python（poetry），约 9,000 行（不含测试） |
| Landscape 定位 | 类型：渗透 Agent（实为 LLM 漏洞扫描器）/ Stars：约 1.3k+ / 一句话：pip 即装的 LLM 安全扫描器，UI 驱动、语料覆盖最广的轻量红队 fuzzer |
| License | Apache-2.0 |
| 关联论文 | 无（自适应攻击模板注明源自 tml-epfl/llm-adaptive-attacks） |
| 审计日期 / 人 | 2026-08-24 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：给 LLM API/端点做**越狱与注入压力测试**——用 40+ 个 HuggingFace 越狱数据集的语料轮番打靶，统计"未拒答率"（=越狱成功代理指标），Web UI 实时看板。
- **输入输出**：OpenAI 兼容 spec（或自定义 LLM spec）+ 勾选数据集 + 预算 → SSE 流式 ScanResult（module/tokens/cost/failureRate/prompt/latency）+ failures.csv/full_scan_log.csv + UI 图表。
- **差异化定位**：三个 LLM 红队工具里的**"轻量 UI 派"**——没有 garak 的插件统计体系、没有 promptfoo 的平台矩阵，取胜点是**开箱即用（pip install + UI）+ 语料覆盖广（40+ HF 数据集直连）+ 独门的贝叶斯早停与 many-shot 注入**。"agentic"主要在名字里——本体是语料 fuzzer。

## 2. 架构总览

```
FastAPI (routes/: scan UI + specs)
   ▼
probe_actor/fuzzer.py（核心 678 行★）
   ├─ perform_single_shot_scan: 数据集模块逐一打靶
   │    ├─ probe_data/（数据集目录 40+ HF 越狱库 + GPT fuzzer + DAN + 隐写术 + prompt-injections）
   │    ├─ 模态适配: image_generator/audio_generator（IMAGE/AUDIO 走请求改写适配器）
   │    ├─ 拒答判定★: REFUSAL_MARKS 字符串表 + ML 分类器 + PII 检测 + 沙箱逃逸检测（插件注册表，toml 配置）
   │    └─ 贝叶斯优化早停★: skopt GP 对 failure_rate 建模，>50% 的模块提前放弃
   ├─ perform_many_shot_scan: 多步对话 + probe 注入（概率 0.2 / ctx 10k 重置）
   └─ FuzzerState: 失败/拒答/输出全程记录 → CSV 导出
executor/concurrent + llm_providers/（anthropic 等）+ refusal_classifier/（hybrid/llm 双分类器）
probe_data/modules/: adaptive_attacks（tml-epfl PAIR 模板）+ rl_model（RL 攻击）
```

- **编排方式**：async 生成器流水线——`scan_module` 逐 prompt yield ScanResult JSON（SSE 推 UI），无 agent 循环、无多轮推理。
- **LLM 层**：目标侧是 httpx 直打 OpenAI 兼容端点（http_spec 的 request_factory）；**攻击语料是静态数据集**，无攻击者 LLM（除 adaptive_attacks 用论文成品模板）。
- **执行环境**：纯 API 客户端，无沙箱。

## 3. 目录结构逐层解读

```
agentic_security/
├── probe_actor/   # ★ fuzzer.py(678 核心) refusal.py(拒答检测插件) operator/ state/ cost_module
├── probe_data/    # ★ __init__.py(40+ HF 数据集目录) data.py unified_loader stenography_fn
│   │               image_generator audio_generator msj_data
│   └── modules/   # adaptive_attacks(tml-epfl 模板) rl_model
├── refusal_classifier/  # model/llm_classifier/hybrid_classifier/pii_detector/
│                        # sandbox_escape_detector/registry（toml 配置化插件注册表）
├── routes/        # FastAPI: UI + scan SSE + _specs(397 行 OpenAPI 规格驱动)
├── http_spec.py   # Modality 枚举 + request_factory（OpenAI 兼容）
├── executor/ llm_providers/ lib.py config.py report_chart.py
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 fuzzer 核心循环（probe_actor/fuzzer.py 全文亲读）

- **默认值面**（:50-64 亲读，全部可 toml 覆盖）：`max_prompt_length=2048`；**`budget_multiplier=100000000`**（用户给 1 即内部 1 亿"token"——预算本质是按响应词数累加的软上限）；`initial_optimizer_points=25`；`min_failure_samples=5`；**`failure_rate_threshold=0.5`**（早停阈值）；`failures.csv/full_scan_log.csv` 固定落盘路径；MSJ `max_injection_attempts=20`。
- **single-shot 主循环**：模块逐一 → 逐 prompt `process_prompt`（httpx 发送 → ≥400 记错误算失败 → 成功则 `refusal_heuristic` 判拒答 → FuzzerState 记录四类：refusals/errors/outputs/failures）→ 每条 yield 进度 ScanResult。
- **贝叶斯早停**（:329-338 亲读）：`skopt.Optimizer([Real(0,1)], base_estimator="GP")`，把累积失败率作为目标（取负求最大）在线建模；`optimizer.ask()/tell()` 逐点喂入，当**模型估计的最优失败率 > 50% 即放弃该模块**——"这个数据集已经打穿了，不用再打"的统计学表述。≥5 个样本才启用。
- **预算闸**：全局共享 token_counter（跨模块累计），超预算优雅停并报状态。
- **错误处理**：模块级异常 continue 不连坐；`with_error_handling` 包装保证生成器必然 yield 完成消息。
- **many-shot（MSJ）**（:483+ 亲读）：多步对话流中**按 probe_frequency=0.2 概率随机注入探针数据集**的 prompt，上下文超 10k 重置——模拟长上下文里的突袭注入；其余同单发。

### 4.2 拒答判定体系（probe_actor/refusal.py 全文亲读——本项目的"检测器"层）

- **插件注册表**（registry + toml `[detectors]` 配置）：默认启用两个——
  - `default`：**REFUSAL_MARKS 29 条字符串表**（"I'm sorry"/"As an AI"/"I cannot"/"Hello!"…"is illegal and unethical"）——经典的 PAIR 式"拒答信号"判定，**failureRate 实为"未出现拒答短语率"**（越狱成功的代理指标）；
  - `ml_classifier`：随包训练的 `RefusalClassifier`（模型文件本地加载）；
  - 另有 `pii`（PII/凭证泄漏信号）与 `sandbox_escape`（Docker/K8s 逃逸探针信号）检测器注册可选。
- 判定是对**整个响应 JSON 的字符串化**做包含检查（request_json→str）——粗但零成本。

### 4.3 攻击语料与模板

- **数据集目录**（probe_data/__init__.py 亲读清单）：40+ 个 HF 越狱数据集直连（advbench 变体、JailbreakBench/JailbreakHub、DAN、GPT fuzzer、ChatGPT-Jailbreak-Prompts、prompt-injections、JailbreakV-28K、多语言 aya、按模型微调数据集 llama-2/llama3.2/dolphin…）+ 隐写术模块（payload 藏进载体）+ 聚合 "AgenticBackend"——**语料广度是本体最大资产**。
- **adaptive_attacks**（亲读）：从 tml-epfl/llm-adaptive-attacks 拉 harmful_behaviors_pair.csv，套用论文四模板生成攻击——**`refined_best` 模板全文在代码里**（`<rule>` 块强制：以目标句开头、五步填充、禁说 "I"、禁用 "legal/safe/ethical/sorry/cannot/however" 等词、声明纯虚构纯研究目的）——GPT-4 越狱率 60%+ 的学术攻击原样产品化；另有 icl_one_shot/claude 变体。
- 模态适配：IMAGE/AUDIO 目标经 RequestAdapter 改写（图像生成器把 prompt 转图片输入）——多模态打靶。
- rl_model：RL 系攻击模块（README 宣传的 RL-Based Attacks）。

### 4.4 结果验证与去误报

- 验证=拒答启发式（字符串+ML 双通道）+ PII/沙箱逃逸专用检测器；无裁判 LLM、无 Se/Sp 校准、无去重。
- failureRate 语义脆弱：模型合规地讨论安全话题若不含拒答短语会被误计"越狱成功"——**字符串拒答表的假阳性问题**是本工具最大的方法论短板（对照 garak 的校准 CI）。

### 4.5 服务与 UI

FastAPI + 内嵌静态 UI（routes/static.py 209 行）+ `_specs.py`（397 行 OpenAPI 规格驱动——可从 API spec 构造请求工厂打任意 REST 端点）；report_chart.py 出图。

## 5. 值得借鉴的设计与技巧

1. **贝叶斯模块早停**：把"该数据集是否已打穿"交给 GP 在线回归（≥5 样本起判，>50% 失败率弃模块）——语料 fuzzer 的预算分配智能化，可移植到任何大批量打靶场景。
2. **拒答检测器插件注册表**：toml `[detectors]` 配置启用（默认字符串表+ML 分类器，PII/沙箱逃逸可选）——判定层可扩展且配置化。
3. **MSJ 概率注入**：多步对话流按 0.2 概率插入探针、10k 上下文重置——many-shot jailbreak 的最小实现。
4. **学术攻击模板直采**：tml-epfl refined_best 全文进代码（含 `<rule>` 禁词表结构）——研究成果到产品零翻译成本。
5. **SSE 生成器流水线**：整个扫描是 async 生成器逐条 yield JSON——UI 实时性与核心逻辑天然解耦。
6. 40+ HF 数据集目录直连（含按目标模型微调的专用语料）——语料即配置。

## 6. 局限与改进点

- **判定粗糙**（最大短板）：字符串拒答表 + 无校准无裁判——failureRate 的语义可靠性远低于 garak/promptfoo；"Hello!" 在拒答表里这类选择值得商榷。
- 无攻击者 LLM 迭代（静态语料为主）——adaptive/RL 模块是论文模板回放而非真迭代攻击。
- budget_multiplier=1e8 使"token 预算"语义模糊（实为响应词数软上限）。
- 名实落差：名字 agentic，本体是语料 fuzzer（与 hexstrike 相反方向的营销温和版）。

## 7. 与其他已审计项目的对比

| 维度 | agentic_security（本项目） | garak | promptfoo | PyRIT |
|---|---|---|---|---|
| 形态 | **轻量语料 fuzzer+UI** | 扫描器（插件统计） | 评测+红队平台 | SDK 库 |
| 攻击源 | 40+ HF 静态数据集+论文模板 | 192 声明式探针 | 插件×策略生成 | 多轮编排 |
| 判定 | 拒答字符串+ML 分类器 | 检测器+Se/Sp 校准 CI | 断言+裁判 | 裁判+元评估 |
| 独门 | **贝叶斯早停/MSJ 注入/多模态适配** | 多语言回路 | CI 平台化 | 树搜索 |
| 上手成本 | **最低（pip+UI）** | 低 | 中 | 高（编程） |

LLM 红队工具谱系就此完整：**PyRIT（库）→ garak（扫描器）→ promptfoo（平台）→ agentic_security（轻量 UI fuzzer）**——四者共享"越狱语料+拒答/裁判判定"骨架，差异在工程化程度与判定严谨度。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `probe_actor/fuzzer.py` | ✅ 亲读全文 | 678 行（1-560 逐段） |
| `probe_actor/refusal.py` | ✅ 亲读全文 | 179 行 |
| `probe_data/modules/adaptive_attacks.py` | ✅ 亲读 | 模板全文+数据源 |
| `probe_data/__init__.py` | ✅ 亲读清单 | 40+ 数据集目录 |
| `http_spec.py` `config.py` `routes/_specs.py` | ⬜ 部分 | 职责与默认值经 fuzzer 交叉 |
| `refusal_classifier/`（hybrid/llm/pii/sandbox_escape/registry） | ⬜ 部分 | 注册机制亲读，各分类器实现登记 |
| `probe_data/` 其余（stenography/image/audio/msj） | ⬜ 部分 | 机制登记 |
| `executor/` `llm_providers/` `routes/static.py` | ⬜ | 结构登记 |

## 9. 结论

**Agentic Security 的核心实现思路是：做一个语料驱动、UI 优先的 LLM 越狱 fuzzer——40+ 个 HuggingFace 越狱数据集（含按目标模型微调的专用语料与 tml-epfl 学术模板）经 async 生成器流水线逐条打向 OpenAI 兼容端点，用可配置的拒答检测器插件（字符串表+ML 分类器，PII/沙箱逃逸可选）把"未拒答率"当越狱成功代理指标，配贝叶斯（GP）在线建模实现"已打穿模块"的早停与全局预算闸，many-shot 模式按概率往多步对话里注入探针测长上下文抗性。** 它是 LLM 红队谱系的"轻量 UI 派"：上手成本最低、语料最广，代价是判定层粗糙（字符串拒答表、无校准无裁判）——适合快速摸底，不适合严谨评测。

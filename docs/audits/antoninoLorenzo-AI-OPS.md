# antoninoLorenzo/AI-OPS 逐行代码审计

> 审计对象：AI-OPS —— API+CLI 双件的模型无关渗透 agent（litellm 底座、"面向中等规模 LLM 设计"）：**白板即规范状态+双层上下文压缩**（pre-checkpoint/active-window 以白板写为检查点）+ **技能强制装载协议** + 终端命令准入策略（allow-list+确认）+ auto_pen_bench 基准。研究原型自述"实验工具，别指望替代真实能力"。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/antoninoLorenzo/AI-OPS |
| 本地路径 | `repos/agents/AI-OPS/` |
| 审计基线 commit | `8f5b362`（merge dependabot upload-pages-artifact-5，PR #11——维护活跃） |
| 语言 / 规模 | Python ~13,323 行（ai_ops API+测试）+ TypeScript CLI（sessionReducer 622）+ benchmark |
| Landscape 定位 | 类型：渗透 Agent / Stars：中低 / 一句话：API/CLI 双件白板态 agent（双层压缩+技能强制+命令准入） |
| License | MIT |
| 关联论文 | 无（活跃研究原型；auto_pen_bench 基准挂接） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：自托管渗透 agent 服务——API 容器（预装攻击工具）持有 agent/工具/会话态，CLI 终端驱动；BYO-LLM（litellm 全提供商，目标中等模型）。
- **AI 真伪核查**：真 AI（litellm+ReAct 提示+白板/技能/终端工具族）。
- **差异化定位**：**白板写入=上下文检查点**的架构耦合——状态工具与压缩策略一体设计（此前各项目二者独立）。

## 2. 架构总览

```
CLI（TS，state/sessionReducer 622）──HTTP──▶ API（FastAPI：api/run/auth/profile/model/config）
   ▼ ai_ops/core/
runner(439) + conversation + llm(349 litellm) + agent
context_management(347 ★：ContextView 协议——Raw/****Layered**** 双实现)
   ▼ prompt/local/（文件即提示：react ★ + tools/*（terminal/read_whiteboard/
     write_whiteboard ★/load_skill ★/write_file）+ examples/* + registry.json）
tools/：terminal（policy.py ★准入策略：AllowListPolicy 可执行文件白名单+DEFAULT 集）
        whiteboard（规范状态）/load_skill（内置+user_skills 双源）/think/write_file/stop
skills：SKILL.md 目录制（社区标准格式）；benchmark/auto_pen_bench+replay
```

- **提示词即文件树**（local/ 下 react 与 tools/* 各为纯文本+registry.json 索引）——提示资产与代码分离的注册表模式。

## 3. 核心模块精读（审计主体）

### 3.1 提示词（prompt/local 关键文件全文亲读）

- **react**："你是自主渗透 agent，运行在合法受控环境"——**行动前四问**（"目标已知什么（Whiteboard Index）/该测什么（Agent Skills）/**什么结果能证实或证伪假设**/最合理动作"——假设检验框架进日常循环）；"命令失败先推理再重试；**同一方法正确设置下失败两次、或三迭代无进展=兔子洞，换路或放弃**"。
- **read_whiteboard**："**Whiteboard Index 以紧凑摘要注入上下文——索引里有你要的就别重复推导**；只在需要全文时 read"——索引/全文两级读取。
- **write_whiteboard**："**白板是已验证发现与已确认死胡同的规范持久状态。验证后立即写**"——三字段契约（name 唯一键/description 一句/**content=怎么找到的：精确命令、输出、推理、值得记的失败尝试**）；"**不写未验证的发现**"。
- **load_skill**："**执行任何命令前必须装载当前阶段的合适技能**（从白板索引与任务上下文判断）"——技能装载是强制前置而非可选。
- **terminal**：持久会话（session_id 保持 env/cwd/后台进程）+interactive 标志+timeout 参数。

### 3.2 LayeredContextView（context_management.py 头 112 行亲读）——白板检查点式压缩

- 设计注释自述：**Conversation 是只追加记录，ContextView 给 LLM 压缩视图**——"分离允许编排器注入临时上下文（如可变索引）而不膨胀会话史"。
- **双层粒度**：`pre-checkpoint`（丢弃最后一次白板写之前的一切——**白板写=agent 完成了一串操作（正/负结果）的信号**，索引保留发现、全文保留过程）+`active-window`（检查点之后的窗口内压缩：只留最近 max_think 个 Think/max_file_write 个写文件调用、终端输出按 truncation_threshold=10% 上限截断）——**"pre-checkpoint 的效果取决于 agent 写白板的频率（依赖模型 IF 能力）；active-window 不依赖"**的双策略诚实评估。
- 诚实注释（"fucking benchmarks"的 alias 参数——跑基准的工程妥协直书；"file write 工具尚未实现因为跑 bench 优先"）。

### 3.3 终端准入策略（policy.py 头 30 行亲读）

- `CommandAdmissionPolicy` 抽象+`AllowListPolicy`：**从命令抽取可执行文件集合对照白名单**（配置 allowlist∪DEFAULT 集），不在名单→blocked 集合返回——README 对应"guarded command execution……**不在名单的需确认**"。

### 3.4 其余（结构确认）

- API 五路由（run/auth/profile/model/config——多模型档案管理）；MLflow 可选追踪；TS CLI 状态机；auto_pen_bench 基准+replay（含 patches——第三方基准适配痕迹）。

## 4. 值得借鉴的设计与技巧

1. **白板写入=上下文检查点**：状态工具与压缩策略架构耦合（写白板既固化发现又标记"此前的过程可丢弃"）——**让状态维护成为压缩的信号源**（对照 Cairn 图快照/ctf-agent 8192 硬闸：这里是"模型自愿写状态→系统据此裁剪"的激励相容设计）。
2. **索引/全文两级白板**（"索引有就别重复推导"+content 含失败尝试的完整契约+"不写未验证发现"）。
3. **行动前四问**（含"什么结果能证实或证伪假设"）+兔子洞两准则（同法两败/三迭代无进展）。
4. 双层压缩的依赖性诚实分析（pre-checkpoint 依赖模型 IF、active-window 不依赖）+注释级工程坦白。
5. 提示词文件树+registry；技能强制装载前置；可执行文件级命令准入。

## 5. 局限与改进点

- 研究原型自述（"别指望替代真实能力"）；write_file 工具未实现（注释承认）；runner/llm/CLI 未逐行。
- 白板频率依赖模型能力（作者自评）；auto_pen_bench 为第三方基准适配（patches 目录）。
- 中等模型目标意味着上限自限；无验证角色。

## 6. 与其他已审计项目的对比

| 维度 | AI-OPS（本项目） | Cairn | BreachWeave | deadend-cli |
|---|---|---|---|---|
| 状态 | **白板（规范态+检查点）** | 图三原语 | Idea/Memory 双板 | 置信度 |
| 压缩 | **白板检查点双层** | 图快照文件 | 体积预算 | 条件摘要 |
| 技能 | **强制装载前置** | skill 渐进加载 | 19 内置 | — |
| 命令闸 | **可执行文件白名单** | — | — | 纠偏四前提 |
| 形态 | API+CLI 服务 | 引擎 | 竞赛系统 | CLI |

与 Cairn 的黑板构成"状态"的轻/重两态；**白板=检查点**的激励相容设计（模型写状态→系统裁剪上下文）是全景观上下文管理的新变体。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `core/prompt/local/`（react+4 工具提示） | ✅ 亲读全文 | 关键六文件 |
| `core/context_management.py` | ✅ 亲读头 | 112/347（协议+Layered 设计注释） |
| `core/tools/terminal/policy.py` | ✅ 亲读头 | 30/~90（准入策略） |
| `core/` 其余（runner/llm/conversation/agent） `api/` | ✅ 结构登记 | 未逐行 |
| `cli/`（TS） `benchmark/` `static/` | ⬜ | 结构登记 |
| `README.md` | ✅ 亲读 | 定位/特性/架构 |

## 8. 结论

**AI-OPS 的核心实现思路是：以白板为架构枢纽的模型无关渗透 agent——白板既是"已验证发现+已确认死胡同"的规范持久状态（索引/全文两级、不写未验证、content 记录完整过程含失败），又是上下文压缩的检查点信号（pre-checkpoint 丢弃检查点前过程、active-window 独立于模型写板频率），技能装载为命令执行强制前置，终端按可执行文件白名单准入，API/CLI 分离部署、litellm 全提供商面向中等模型。** 其独有贡献是**状态维护与上下文压缩的激励相容耦合**（模型自愿写状态即自愿触发裁剪）——连同双层压缩依赖性的诚实分析，是长会话上下文管理的可抄新变体；原型完成度（write_file 未实现）与中等模型自限是其边界。

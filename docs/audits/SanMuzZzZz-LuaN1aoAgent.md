# SanMuzZzZz/LuaN1aoAgent 逐行代码审计

> 审计对象：LuaN1aoAgent v2 —— TypeScript+Pi SDK 的认知驱动自主安全 agent（**腾讯云 TCH 智能渗透挑战顶级排名项目**，与 Cairn 同赛事）：P-E-O 三角色（Planner-Executor-Observer，Observer 双模式 Supervisor/Projector）、持久事件与工件、证据背书的图记忆、**认识论严格到把科学方法写进提示词**（因果边界/判定信号审计/区分性实验/负面结论范围限定）。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/SanMuzZzZz/LuaN1aoAgent |
| 本地路径 | `repos/agents/LuaN1aoAgent/` |
| 审计基线 commit | `ac16a32`（fix: resume reopened task after completed outcome is superseded…） |
| 语言 / 规模 | TypeScript ~32,912 行（src 57 文件）+ Python/Go 网络沙箱镜像（gateway-tun/socks-connector 等 ~3.6k 行） |
| Landscape 定位 | 类型：渗透 Agent / Stars：中 / 一句话：P-E-O 架构的认识论严格自主渗透 agent（TCH 顶级排名） |
| License | AGPL-3.0 |
| 关联论文 | 无（README 声明 v1 战绩不自动归属 v2，须冻结版重跑后发布——可复现文化） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：授权安全研究的全自主执行：Root Goal→Task 图调度→隔离 workspace 内工具循环→图投影→监督，"每个重要结论可追溯到持久事件、工件与图证据"。
- **AI 真伪核查**：真 AI（Pi SDK 运行时+四系统提示词+LLM 配置层）。
- **差异化定位**：与 Cairn 同赛事不同哲学——Cairn 极简三原语，LuaN1aoAgent v2 走**重认识论**路线：把实验科学方法论（对照/单变量/区分性/边界）编码为 agent 行为契约。

## 2. 架构总览

```
CLI/TUI/Web（web-server 3219：live trace+推理图工作台）
   ▼ P-E-O
Planner（controller 6829：Task 图调度/预算/依赖/优先级；commands 五种图操作）
Executor（pi-runner 1187+executor-sandbox：单 Task 有界 Epoch 工具循环，Docker 隔离 workspace）
Observer ─ Supervisor（热路径：continue/redirect/handoff/stop_executor 保护执行时间）
         └ Projector（异步：observation→推理图/作战图 delta）
持久层：stores/（graph-store 2552 ★ 图 + runtime/execution-log/artifact/connectivity）
连通层：connectivity/（network-sandbox-manager 1228/route-manager 1091/host-egress-broker/
        mitm-flow-client/replay-gateway + network-image 镜像：scope_dns/流量分段捕获/回放）
预算：epoch-budget-clock（Epoch 切片不动态扩展）
```

## 3. 核心模块精读（审计主体；33k 行大仓亲读计划：prompts.ts 四系统提示全文+结构）

### 3.1 四系统提示词（prompts.ts 674 行之 330 行亲读——四提示全文）

**共同气质**：认识论契约式写作——每条规则都在限定"什么能证明什么"。

- **Planner 提示**：
  - Task 语义：**Task=同一 Executor 持续拥有的因果工作流，不是侦察/验证/利用等技术阶段**；技术阶段变化属 Executor；新必要结果用 `appendObjectives` 追加而非新任务（goal/successCriteria 创建后不可改、只能追加）；workspace/Session 延续用 `continueFromTaskRef`。
  - **证据边界规则簇**："Evidence 只证明其实际观察范围；不得把 Executor 建议、候选技术、Hypothesis 或漏洞情报直接升级为已确认事实"；"固定输入成功只证明其精确能力"（能力泛化须受控变量证明）；**"数量、时间和有限尝试只表示投入边界，不证明开放候选空间穷尽——Root Goal 的'全部/所有/每个'按开放集合处理，除非持久材料给出可验证的封闭边界"**。
  - refuted/superseded 假设是规划知识（同条件下不得重复已排除路径，除非 reopenConditions 满足）；报告必须走独立报告 Task+`artifact_write(kind="report")`，报告工件产生前不得判定 Root Goal 完成。
- **Executor 提示**（方法论最厚）：
  - **因果边界分层**："先锁定当前因果边界，只在同一层内验证：请求/路由是否到达→认证与分支是否进入→输入如何绑定→校验是否通过→目标能力是否执行→结果是否可见。**当前层未证明前，不用下一层 payload 的失败推断其机制无效**"。
  - **判定信号（oracle）审计**："只使用响应动态区域、状态码、重定向、稳定响应差异、时间差或可验证副作用。**页面本来就存在的说明文字、全局关键词和请求脚本自己打印的标签不能证明后端分支、过滤器或执行器已触发**"；DOM 行为须 browser_render 后 DOM 可观察变化（"curl 反射或 payload 出现在源码中不能单独确认"）。
  - **实验设计分类**：探索实验=无正向基线+多竞争解释时选"能排除至少一个解释的最小验证"；确认实验=有可复现基线时**单变量+保留正负对照**。
  - **负面结论范围限定**："只覆盖实际测试的输入类、前置条件和判定信号；基线失败、正对照失败、信号含糊、同时改变多个独立条件→只能 inconclusive"；批量枚举写 manifest（"达到阈值只表示本轮停止扩大，不表示攻击面不存在"）。
  - 反面知识复用（等价实验复用 refuted 结论）；行动理由≤80 汉字公开前置；checkpoint/abort 提交阶段结果。
- **Projector 提示**（投影纪律）：
  - **Ground claim 定义**："在明确条件下，对明确对象执行明确动作，观察到明确结果"——"命令中提到的候选、Executor commentary、静态页面文字和模型解释都不是结果"。
  - **图语义严格性**：Hypothesis 状态词汇表（open/inconclusive/confirmed/refuted/superseded——**无 contradicted 状态，反证用 contradicts 边表达**）；"只有完整、可绑定的正向结果证明受控输入突破安全边界时创建 Vulnerability；只有实际读取敏感数据/执行代码/创建会话时创建 succeeded Exploit。**一次固定成功只证明该固定能力**"；"负面结论不得大于实验范围"。
  - **边词汇表**（17 种有向边+作战图/推理图分域）；**秘密禁写 properties**（secret/token/password/cookie/authorization/privateKey/完整响应体）；校验错拒整稿→重交全量 delta。
- **Supervisor 提示**（热路径节制）：
  - 唯一工具 control_submit，四决策（continue/redirect/handoff/stop_executor）；**"进展=能支持或排除竞争解释的动态结果——新 URL、payload、字段名、工具输出或不同 stdout 文本本身不等于进展"**；"Runtime 独立处理预算边界，不得仅因 turn 数/有限枚举失败而 handoff"；stop_executor 仅用于 scope 风险；refuted 假设的等价性判定（target/method/preconditions/判定信号四要素）。
- 输入渲染：**Planner State 快照/增量（delta）双模式**（deliverySeq 事件序号+taskLedger 恒含 canonical definition）；repairFeedback（拒绝原因回灌）；固定上下文只在快照轮注入。

### 3.2 结构确认（清单级）

- controller 6,829 行（Runtime 核心：Task 生命周期/Epoch 切片/预算/steering）；graph-store 2,552（图持久化）；projection 2,028（投影协调）；connectivity 家族+network-image（scope DNS/分段捕获/回放/透明代理由 Runtime 持有——executor 提示明言"不得创建、替换或绕过"）。

## 4. 值得借鉴的设计与技巧

1. **认识论提示词工程**（全景观独一档）：因果边界分层、oracle 审计（静态文字/脚本自印标签不作证据）、单变量+正负对照、区分性实验（排除至少一个解释）、负面结论范围限定、开放集合处理（"全部"不因有限尝试而穷尽）、固定成功≠通用能力——**把科学方法做成 agent 行为契约**。
2. **Task=因果工作流而非技术阶段**+appendObjectives 追加语义（原始 goal 永久保留）——任务图语义的最精细定义（比 pentestagent finish 协议/CyberStrikeAI 任务更严）。
3. **Projector 的 ground claim 投影纪律**+无 contradicted 状态（反证是边不是状态）+秘密禁入图——图记忆的证据卫生。
4. **Supervisor 的进展重定义**（"新 payload/新 URL 不等于进展"）+四决策节制（预算归 Runtime、任务归 Planner——监督权刻意狭窄）。
5. Planner State 快照/delta 双模式+taskLedger canonical 恒在+repairFeedback 回灌。
6. README 的可复现声明（v1 战绩不归属 v2，须冻结版重跑）。

## 5. 局限与改进点

- 33k 行 TS 主干仅 prompts 全文亲读（controller/graph-store/projection 未逐行）；网络沙箱镜像（Go/Python ~3.6k 行）未读。
- 认识论规则全部提示词层（无执行层核验——对照 xalgorix 逐类证据标准+独立验证器）；Projector"校验错拒整稿"的 schema 校验细节未读。
- 中英混排提示词（系统提示中文、字段英文）对非中文模型的后效未知；重规则提示词的 token 成本未声明。

## 6. 与其他已审计项目的对比

| 维度 | LuaN1aoAgent v2（本项目） | Cairn | xalgorix | pentestagent |
|---|---|---|---|---|
| 赛事 | TCH 顶级排名 | TCH 唯一 AK（3rd） | — | — |
| 哲学 | **重认识论（科学方法契约）** | 极简三原语 | 独立验证 | 计划协议 |
| 图记忆 | **推理图+作战图分域（边词汇表）** | Fact/Intent/Hint | — | ShadowGraph |
| 反幻觉 | **oracle 审计+负面结论范围+ground claim** | 写入门槛 | 逐类标准+复测 | 军规 |
| 监督 | Supervisor 四决策（权力狭窄） | 反思路由 | — | COA |
| 任务 | **appendObjectives 因果工作流** | intent 即计划 | — | finish 协议 |

与 Cairn 构成同赛事的哲学两极（极简黑板 vs 重认识论契约），两者并读是"渗透 agent 该多重"的最佳对照实验。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `src/prompts.ts` | ✅ 亲读主体 | 330/674（四系统提示全文+渲染函数头） |
| `src/` 其余（controller/graph-store/projection/connectivity/…） | ✅ 结构登记 | 未逐行 |
| `network-image/`（gateway-tun/scope_dns/分段捕获/回放） | ✅ 结构登记 | 未读 |
| `README.md` | ✅ 亲读 | 定位/架构/可复现声明 |

## 8. 结论

**LuaN1aoAgent v2 的核心实现思路是：把科学方法论编码为多 agent 行为契约——Planner 以"Task=因果工作流、目标只追加不覆盖、证据只证其观察范围、开放集合不因有限尝试而穷尽"的规则调度任务图，Executor 在因果边界分层内做区分性实验（单变量+正负对照+oracle 审计：静态文字与脚本自印标签不作证据），异步 Projector 只投影 ground claim（反证是边不是状态、秘密禁入图、固定成功不泛化），热路径 Supervisor 以"进展=排除竞争解释的动态结果"重定义做四决策节制；一切结论锚定持久事件/工件/图证据。** 它是已审 34 项中认识论严格性最高的系统：与 Cairn（同赛事、极简哲学）构成渗透 agent 设计空间的两个极点，其提示词规则簇（因果边界/oracle 审计/负面结论范围/ground claim）可直接移植到任何需要"模型别把猜测当结论"的场景。

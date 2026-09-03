# SanMuzZzZz/LuaN1aoAgent 逐行代码审计

> 审计对象：LuaN1aoAgent v2 —— TypeScript+Pi SDK 的认知驱动自主安全 agent（**腾讯云 TCH 智能渗透挑战顶级排名项目**，与 Cairn 同赛事）：P-E-O 三角色（Planner-Executor-Observer，Observer 双模式 Supervisor/Projector）、持久事件与工件、证据背书的图记忆、**认识论严格到把科学方法写进提示词**（因果边界/判定信号审计/区分性实验/负面结论范围限定）。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/SanMuzZzZz/LuaN1aoAgent |
| 本地路径 | `repos/agents/LuaN1aoAgent/` |
| 审计基线 commit | `ac16a32`（初审）；`2efe2c5`（2026-09-03 补充深读，force-push 仅改 README star 图，源码与初审基线一致） |
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
  - **边词汇表**（实测 19 种有向边，初审记 17 系笔误，见 §9.3 更正；作战图/推理图分域）；**秘密禁写 properties**（secret/token/password/cookie/authorization/privateKey/完整响应体）；校验错拒整稿→重交全量 delta。
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

- ~~33k 行 TS 主干仅 prompts 全文亲读~~（2026-09-03 补充深读已补齐主体，见 §9；controller 6,829 行为关键段亲读非逐行通读，connectivity/network-image/web-server/tui 仍为结构登记）。
- 认识论规则中需要语义判断的部分（对照实验、oracle 审计、ground claim、秘密禁写）仍在提示词层无执行层核验——对照 xalgorix 逐类证据标准+独立验证器（见 §9.6 落点总表）。
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

---

## 9. 补充深读（2026-09-03，基线 2efe2c5）

> 初审留下的未读缺口本次补齐：llm-config.ts 全文、controller 关键段（预算常量/runOnce 决策循环/runExecutorTask/runSupervisorCheck）、epoch-budget-clock 与 planner-commands 全文、pi-runner 准入与结构化调用、projection/projector-coordinator/graph-store/agents.ts/execution-log（子代理深读）、executor-sandbox-docker 关键段、scope.ts 全文。

### 9.1 接入层：Pi SDK + 国产 OpenAI 兼容网关 + 四角色独立模型（llm-config.ts 全读）

- **底座是 `@earendil-works/pi-coding-agent` 的 `createAgentSession`**（agents.ts:346-357）：`AuthStorage.inMemory` + `ModelRegistry.inMemory`，系统提示经 `DefaultResourceLoader` 的 `systemPromptOverride` 注入，`SessionManager.inMemory`（无跨进程会话持久化，会话态靠自家 execution-log/graph-store）。
- **网关是国产 OpenAI 兼容中转**（provider 名 `baizhi-openai`，成本元数据 `costCurrency: "CNY"`，3/6/0.025 元每百万 token）；apiType 仅 openai-completions/openai-responses——**OpenAI 方言经网关，与 shannon 的 pi 用法同构**。
- **四角色（planner/executor/supervisor/projector）各自独立配模型**：`LLM_{ROLE}_MODEL/MAX_TOKENS/CONTEXT_WINDOW/THINKING/BASE_URL/API_KEY`，缺省回落 `LLM_DEFAULT_MODEL`（默认同模型，可分角色覆写）；角色按 baseUrl+key 自动分组建 provider。**supervisor 热路径默认只给 4,096 max tokens**（其余 16,384）——热路径节制从资源分配就开始了。
- **弱模型适配内置在思维方言层**：`LlmThinkingFormat` 十种（openai/openrouter/deepseek/together/zai/qwen/chat-template/qwen-chat-template/string-thinking/ant-ling，默认 zai）——国产模型 reasoning 兼容是 Pi 底座自带的，这层在 OpenAI 系 SDK 里要自己做（对照 strix 的 strict 降级三件套）。
- **provider 准入闸**（pi-runner.ts:49-210）：`ProviderAdmissionGate` 按 `provider@baseUrl` 键控并发（默认 3）+ 队列 + 按 provider 错误事件冷却；经 Pi 的 `before_provider_request` 扩展钩子接入（acquire 与 abort 信号联动）。**"循环归 SDK、纪律归钩子"的实物样本。**

### 9.2 Runtime 与预算（controller.ts 关键段 + 两个小文件全读）

**预算常量面**（controller.ts:153-249）：任务 maxTurns 默认 12（min 10/max 40）；**Epoch 轮切片=20**；运行墙钟 900s，任务 epoch 占运行剩余时间的 50%（TASK_EPOCH_RUN_TIME_SHARE）；provider 并发 3；Supervisor 窗口=8 轮（idle 60s/hard 90s）；Projector 窗口=16 次工具（idle 180s/hard 300s，批 16/catchup 32，输入目标 32KB，全局并发 2）；**BUDGET_STEER_TURN_INTERVAL=25——每 25 轮预算 steer 把 goal/successCriteria/constraints 重新落到上下文尾部**（注释引真实事故：a-18 在 157 轮 epoch 的第 40 轮后连续 3 次违反任务禁令）。

**EpochBudgetClock**（101 行全读）：纯墙钟死线——`deadlineAt = now + timeLimitMs`，`pause()/resume()` 把死线顺延暂停时长并持久化快照，到点触发 onExpire。"切片不动态扩展"由外部 Runtime 保证（新 epoch 新时钟）。

**runOnce 决策修复循环**（controller.ts:682-758）：Planner 决策经 `applyPlannerCommands` 图语义校验，`GraphValidationError` 触发至多 2 次修复重试，**三类错误三类定制反馈**（中文）：终态不明确（"不得只在 reason 中声明目标已完成"）/ 任务版本冲突（"基于刷新后的状态重新规划"）/ 图语义失败（"不要反转依赖，应创建新后继 Task"）。另有 `MISSING_SUBMIT_RETRY_FEEDBACK`：输出在 max_completion_tokens 截断无 planner_submit 时，反馈明示"先发起工具调用、参数保持简洁、不要在正文输出推理"——**截断修复也是协议的一部分**。

**五种图命令的协议层强制**（planner-commands.ts 全读）：create_tasks/patch_task/replace_dependencies/set_task_status/set_node_status；`patch_task` 的 patch **只有 additionalTurns/budget/priority/appendObjectives 四个字段——goal 与 successCriteria 根本不在可补丁集里**，"目标不可改只能追加"是 schema 层铁律（不是提示词）。任务状态机 open/completed/blocked/failed/archived。
**artifact ref 确定性自动修复**（planner-commands.ts:27-66）：模型习惯性截断 UUID，前缀无歧义时直接代写全 ref（注释原话："bouncing a deterministically fixable Ref back to the model only burns a Planner cycle"），歧义/未知才拒并附候选清单——比 strix 的幻觉 ID 白名单闸更进一步（**能确定性修的不回喂**）。

**runExecutorTask**（controller.ts:2055-2164）：预算预检（taskTurnCount≥maxTurns → persist "checkpointed" 可重试结果而非硬失败）；每 epoch 准备沙箱（workspaceKey 复用判定）；executor 输入分 initial/resume 两种渲染；结果经 `invokeStructured` 的 `task_result_submit` 工具 + `normalizeTaskResult` 校验（结构化提交）。**runSupervisorCheck**（3600-3719）：96 事件窗口 → 取最近 8 轮 executor 事件 → supervision 状态+预算快照+图知识闭包（projectionClosure 限 20 节点/32 边、压缩到 8 条）渲染输入 → `control_submit`；被取代的窗口直接 discard（准入控制）。

### 9.3 Projector 投影链（子代理深读 projection/projector-coordinator/runtime-store）

- **校验是纯手写**（`normalizeProjectionDraft`，非 zod；TypeBox 只管工具入参形状）：错误**编号累积后整稿拒绝**（`No part of the delta was accepted`），异常 message 即修复反馈经工具错误回流；重试两层——单次调用内 `maxRepeatedToolErrors: 2`（同 args+错误签名连错 2 次中止 invocation），任务级指数退避（2s×2ⁿ 封顶 60s）至多 6 次，耗尽后 `retryBlockedAtTarget` 阻塞直到水位前进才解锁。
- **异步解耦 = append-only 事件流 + 水位表 + 微任务泵**：Executor 热路径仅两钩子（每 16 次 tool_finished fire-and-forget 请求投影；task_end 时 terminal 投影最多等 drain 超时）；`projection_states` 表 `desired_seq = MAX(old, new)` 幂等合并，重复请求零成本；全局并发 2、每任务单飞行、terminal 优先；**连续失败批大小指数减半**（背压）；输入超 32KB 逐级压缩（compact 0.55x→0.4x→0.3x→单观测分片），仍超即硬失败。
- **更正：边类型 19 种不是 17**（projection.ts:45-50；tunnels_to/proxy_route 仅由 connectivity 工具产生）。分域靠 `graphKind`（reasoning/operation/task），**投影提交触碰 task 域直接整稿拒绝**（task 图只有 Planner 命令能改）。非法边型报错时按端点类型给建议（"for Host → Port, use has_port"）。
- **Vulnerability/Exploit 有代码级门槛（双处校验）**：创建 Vulnerability 必须带可解析 evidenceRef（本批 observation 别名或 sourceEventId；引用不解析直接丢弃为空数组触发报错），`succeeded` Exploit 同理；projection.ts:914-923 与 graph-store.ts:1928-1933 各查一次。**但"证据内容是否真证明突破"仍是模型判断——代码只管"有引用"，不管"引用了什么"**。
- **诚实更正：图 properties 无代码层 secret 过滤**。"秘密禁写"（prompts.ts:190）是纯提示词约束；properties 归一化只截断（20 键/键 80 字符/值 600 字符，projection.ts:1902-1923）。代码级敏感处理仅两处且都不在投影写路径：connectivity-store 的 `SENSITIVE_KEY` 正则（连通配置）、artifact-store 的敏感件随机文件名。

### 9.4 图存储（graph-store.ts 深读）

SQLite（`node:sqlite` DatabaseSync，WAL+busy_timeout 5000）+ JSONL delta 镜像（appendFileSync 非原子，仅审计用）。写路径全部 `BEGIN IMMEDIATE` 显式事务，**乐观并发三重校验**（committed_seq=fromSeq、active_generation、toSeq≤desired_seq）。幂等三机制：① 投影按 watermark 推进（claim 只取 committed_seq<desired_seq 区间，已提交不重放）；② operation 节点有稳定身份键表（`operation_identities`），重投影同一实体 rebase 到同一 node_id 合并；③ **边 ID 是确定性函数**（`from::type::to`，tunnels/proxy 加判别键），重复边 upsert 合并（properties/evidenceRefs merge 语义）。

### 9.5 沙箱与 scope

Docker 容器：`--memory 4g --cpus 2 --network <自定义> --dns <网络沙箱 DNS>`，CA 证书/resolver/skills 目录**只读挂载**，命令 `sleep infinity`（常驻等待 exec，executor-sandbox-docker.ts:153-174）。scope.ts 全读：**`normalizeInferredScopeCidrs` 强制"AI 推断的 scope CIDR 必须逐字出现在 --goal 文本里"否则抛错**——模型不能自扩 scope 的代码级强制；runUntilDone 启动时 `connectivityRuntime.configureAuthorizedScope` 把授权 scope 灌进网络沙箱。

### 9.6 认识论纪律的代码落点总表（本次深读的核心输出）

| 纪律 | 层级 | 证据 |
|---|---|---|
| goal 不可改只能追加 | **代码**（patch schema 无此字段） | planner-commands.ts:202-235 |
| 任务图只归 Planner | **代码**（投影触 task 域整稿拒） | projection.ts:693-697 |
| 19 种边词汇表/域分离 | **代码**（枚举+端点校验+建议） | projection.ts:45-50, 948-976 |
| Vulnerability/succeeded Exploit 需证据引用 | **代码**（双处校验），但证据内容仍靠模型 | projection.ts:914-923 + graph-store.ts:1928-1933 |
| 预算（轮次/墙钟/并发） | **代码**（预算预检/Epoch 时钟/准入闸） | controller.ts:153-249 + epoch-budget-clock + pi-runner |
| scope 不自扩 | **代码**（goal 文本逐字强制） | scope.ts:70-84 |
| 决策/投影错误回喂 | **代码**（三类反馈/编号错误/两层重试） | controller.ts:697-758 + projection + coordinator |
| 截断 UUID 确定性修复 | **代码**（无歧义前缀代写） | planner-commands.ts:27-66 |
| 对照实验/oracle 审计/因果边界/ground claim 语义 | **提示词**（无执行层核验） | prompts.ts 四提示 |
| 秘密禁写图 properties | **提示词**（无代码过滤，更正） | prompts.ts:190 |

### 9.7 深读结论

初审说它是"认识论严格性最高的系统"；深读后的补笔是：**它的严格性有一条清晰的代码/提示词分界线——凡是能做成 schema/枚举/状态机的纪律全部下沉到了代码（含"目标不可改"这种最容易被提示词化的规则），凡是需要语义判断的（这个证据证明不证明突破、这个对照算不算区分性）留给提示词**。这条分界线本身就是可移植的设计原则。对 VackBot 类平台的第二重意义在接入层：它证明了"Pi SDK 当库二次开发 + 国产 OpenAI 兼容网关 + 四角色分模型 + 准入钩子"是一条走得通的生产路线（controller 6,829 行的领域 Runtime 全部自研，LLM 管道零自研）——与 strix 之于 OpenAI Agents SDK 构成两种 SDK 底座的对称样板。

### 9.8 文件级审计进度（更新）

| 路径 | 状态 | 备注 |
|---|---|---|
| `src/prompts.ts` | ✅ 亲读主体 | 四系统提示全文（初审） |
| `src/llm-config.ts` | ✅ 全文亲读 | 接入层全貌（本次） |
| `src/epoch-budget-clock.ts` / `src/planner-commands.ts` / `src/scope.ts` | ✅ 全文亲读 | 本次 |
| `src/controller.ts` | ✅ 关键段亲读 | 常量面/runOnce/runExecutorTask/runSupervisorCheck/steering 段；6,829 行未逐行通读（事件记账/指标段略读） |
| `src/pi-runner.ts` | ✅ 结构+关键段 | 准入闸/invokeStructured/事件白名单 |
| `src/projection.ts` / `src/projector-coordinator.ts` / `src/stores/graph-store.ts` / `src/stores/execution-log.ts` / `src/agents.ts` | ✅ 子代理深读 | 校验/重试/水位/事务/幂等/agent 构造 |
| `src/executor-sandbox-docker.ts` | ✅ 关键段 | 容器参数/只读挂载 |
| `src/connectivity/*`、`network-image/`、`src/web-server.ts`、`src/tui/*` | 结构登记 | 未深读（连通层细节/前端不在本次范围） |

# oritera/Cairn 逐行代码审计

> 审计对象：Cairn —— 腾讯云 TCH 黑客马拉松 AI 渗透挑战（第二届）**唯一 AK 队（54/54 全解，总排名第三）**的开源系统。自称"通用状态空间搜索引擎"：渗透测试只是其首个验证域——无角色、无工作流、零 MCP、零 RAG，给定 origin 与 goal 在未知状态空间里搜路。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/oritera/Cairn |
| 本地路径 | `repos/agents/Cairn/` |
| 审计基线 commit | `8f702c5`（2026-08 前后，merge feat/code-based-healthcheck） |
| 语言 / 规模 | Python 3.12+，单包 cairn（dispatcher + server）约 6,430 行（不含测试）；另有 worker 容器镜像 |
| Landscape 定位 | 类型：渗透 Agent / Stars：2.0k / 一句话：黑板架构 + OODA 工作循环的通用状态空间搜索渗透引擎 |
| License | **AGPL-3.0**（商业需另购许可——已审 18 项中唯一强传染协议） |
| 关联论文 | 无（有微信公众号赛后复盘两篇） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：任何"起点已知、终点已定义、路径未知"的问题——渗透测试（拿 shell/夺旗）、漏洞研究、数学证明、CTF。竞赛实证：610 队 1345 人中唯一全解。
- **输入输出**：项目（origin 事实 + goal 事实 + 可选 hints）→ 事实-意图图不断生长直至某条 intent 的终点是 goal（项目完成）。
- **差异化定位**：**反 Agent 框架的 Agent 系统**。没有角色（Reconner/Exploiter/Reporter 之类）、没有 pipeline、没有 planner——只有一种 Worker（ Claude Code/Codex/Pi CLI 的进程包装）和三种任务（bootstrap/reason/explore），全部协调经黑板（Stigmergy 间接通信）。README 明言比赛当天凌晨 4 点全链路首次跑通、零训练零调优零领域工具。

## 2. 架构总览

```
Cairn Server（FastAPI + SQLite：Facts/Intents/Hints 表 + 认领租约 + 过期回收）
   ▲ Read/Write API（claim/heartbeat/conclude/complete/create_intent/hint）
   │
Dispatcher（轮询调度循环，interval=3s）
   ├─ 四闸公平调度：max_workers(8) / max_running_projects(3) / max_project_workers(4) / 轮转游标
   ├─ checkpoint 差分触发 reason（facts/hints 增长 或 open_intents 归零才重推理）
   ├─ explore 取最新未认领 intent（深搜偏置）；bootstrap 只在初始项目
   └─ 容器管理：每项目一容器（或 local 模式复用宿主 CLI）；完成/停止容器异步清理
        │ exec（agent CLI 进程 + 心跳租约 + 取消信号）
        ▼
Worker = claude --session-id <uuid> --dangerously-skip-permissions -p <提示词>
         （conclude 阶段用 claude -r <session> 原生续接）
```

- **三原语**（server/models + services 亲读）：**Fact**（已确认客观发现）/ **Intent**（声明的探索方向，from=若干 facts，to=结论 fact 或 null）/ **Hint**（人类随时注入的判断，下次读图被吸收）。图上每条边都是 intent：**"完成"本身被建模为 to='goal' 的 intent**（完成也要图一致——get_completion_intent_or_409 要求完成项目恰有一条完成 intent）；goal 不允许作 from。
- **ID 体系**：每项目 scoped 计数器（f001/i001/h001），SQLite 单库。
- **执行环境**：每项目独立 worker 容器（network host）；local 模式直接跑宿主 CLI（无沙箱，明示授权前提）；`--dangerously-skip-permissions` 全开 agent 权限。

## 3. 目录结构逐层解读

```
cairn/src/cairn/
├── dispatcher/                 # ★ 调度域（全部核心逻辑）
│   ├── scheduler/loop.py(935)  # ★ 调度主循环（亲读全文）
│   ├── scheduler/worker_select.py(17)  # 优先级→最少负载→随机
│   ├── tasks/bootstrap.py(481) reason.py(284) explore.py(407) common.py(247) # ★ 三任务（亲读全文）
│   ├── prompts/default/*.md ×5 # ★ 提示词全文（39-55 行/个，极简）
│   ├── contracts.py(170)       # ★ 输出契约：accepted/data 信封 + 反停滞不变量
│   ├── workers/ base.py + adapters/(claudecode/codex/pi/mock) # 驱动抽象
│   ├── runtime/ (containers/process/heartbeat/cancellation/…) # 容器执行/心跳/取消
│   ├── config.py(424)          # ★ 配置 + mock 混沌测试设施（亲读全文）
│   └── output_parser.py(47)    # 栅栏块+逐{扫 JSON 打捞
└── server/                     # 黑板服务：models/db/services.py(257 亲读)/routers ×5
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 调度主循环（scheduler/loop.py 935 行全文亲读）

- **轮询骨架**（interval=3s）：reap futures → reap 清理 futures → 列项目 → 初始化 reason checkpoints → 刷新运行项目集 → **取消非活跃项目的在跑任务** → 排队容器清理 → 派发。Server RequestException 降级为 warn+sleep 重试。
- **四闸公平调度**：全局 max_workers；每项目 max_project_workers；max_running_projects 限制"同时在跑的项目数"（运行中项目轮转优先，空闲项目逐个准入——游标轮转防饿死）；`max_project_workers ≤ max_workers` 启动校验。
- **每项目任务优先级**：bootstrap（仅初始项目：facts 恰为 {origin,goal}）→ reason（由 checkpoint 差分触发）→ explore（**未认领 intent 中取 created_at 最新者**——后进先出的深搜偏置；已排除本机在跑与 bootstrap 意图）。
- **checkpoint 差分触发 reason**（_reason_trigger）：记上次成功 reason 时的 (fact 数, hint 数, open_intent 数)；只有 facts 增长 / hints 增长 / open_intents 从正数归零 才再推理——事件驱动，不轮询空转。reason 成功才更新 checkpoint。
- **worker 选择四过滤**：task_types 白名单 → 每 worker max_running → unhealthy 冷却（5s）→ **rejected 冷却按 (project, task_type, worker) 三元组**（5s）→ choose_worker（priority 升序 → 当前负载升序 → 随机打破平局）。
- **认领协议**：reason 走 claim_reason；explore/bootstrap 走**心跳即认领**（heartbeat 端点顺手 claim）。403（项目非 active，INFO 级）与 409（冲突，WARNING 级）区别对待；提交失败 best-effort release。
- **reap 状态机**：outcome ∈ cancelled/unhealthy/rejected/failed/success；unhealthy→worker 冷却、rejected→三元组冷却、success+reason→checkpoint 更新；异常捕获全兜底。
- **`_log_changed` 轮询日志去重**：按 (level, message, args) 状态记忆，相同 skip 消息不刷屏——轮询系统的日志卫生小设计。
- **跨组件时序契约启动校验**（_validate_server_settings）：server 的 intent_timeout/reason_timeout 必须 > dispatcher interval（心跳数学），< 2× 则警告余量紧——**分布式租约的一致性前置检查**。

### 4.2 三任务与 conclude 兜底（tasks/*.py 全文亲读）

- **统一执行骨架**（common.py）：HeartbeatLease（后台线程按 interval 心跳维持认领）+ TaskCancellation（attach 进程）+ run_worker_process（容器 exec、timeout+15s 宽限）。**图快照写进容器内文件**（`/tmp/cairn-prompts/<phase>-<uuid>/graph.yaml`），提示词只给路径并令 agent "先整读该文件"——**上下文经文件引用而非内联**，大图不撑爆提示词。
- **bootstrap**：初始直解。成功→conclude 写 fact 再 complete（引用新 fact；403/409/写失败都算 success——fact 已落袋）；**失败/超时/解析失败→conclude 兜底**。
- **reason**：全图判定。结果四态：complete（from 必须引用合法 fact，goal 被排除）/ intents（逐条创建，**409=竞态输掉优雅跳过**；全部失败才算 failed）/ noop / rejected。
- **explore**：单意图执行。正常返回一条 description→conclude 成 fact；**超时或输出不可解析→conclude 兜底**。
- **★ conclude 兜底（本项目的招牌设计）**：execute 阶段超时/坏输出时，**用 `claude -r <session>` 续接同一会话**再发一份"立即停止、只总结已确认事实"的 conclude 提示词，把已学到的知识 salvage 成 Fact 写回黑板——**长探索超时 ≠ 知识丢失**。前置守卫齐全：driver 不支持/无 session、心跳已丢、已取消、项目非 active 都直接放弃兜底。
- 输出阶梯（三任务一致）：cancelled → 心跳丢失 → 超时 → 非零退出 → 解析失败（→兜底）→ rejected → 业务写回；每步都 best-effort release。

### 4.3 输出契约（contracts.py 170 行全文亲读）

- **双格式容忍**：接受裸 payload 或 `{"accepted": bool, "data": {...}}` 信封（_looks_like_* 嗅探）——信封是提示词要求的正路，裸格式是对模型的兜底。
- **rejected 是一等结果**：worker 可拒绝任务（提示词又写"任何情况下都不许拒绝"——机制上允许、措辞上劝阻）。
- **反停滞不变量**：open_intents 为空时 reason **必须**给非空 intents（否则 ValueError→failed→换 worker 重试）；open_intents 非空时允许空 noop。
- 向后兼容：单数 "intent" 自动转列表；intents 截断到 max_intents；conclude 载荷多余键拒绝。

### 4.4 提示词设计（prompts/default/*.md 五个全文亲读——每个仅 39-55 行）

- **极简到惊人**：没有角色扮演、没有思维链脚手架、没有工具说明——只有 Task/输出格式/Rules/Context 四段。全部智能押在"黑板状态 + CLI agent 自带能力"上。
- **conclude 覆盖条款提前播种**（bootstrap/explore 主提示词里就写）："若同一会话后续收到 conclude 阶段指令，该指令**立即覆盖**本任务的持续工作要求"——防僵尸 agent 的逃生门在第一阶段就预告，conclude 提示词再以"立即停止、不得再跑任何命令、只总结已确认信息"三重强制收口。
- **反重复增量约束**（explore/conclude）："description 只含最新增量事实，不得重复图快照已有信息"——黑板增量写入的提示词侧保障。
- **长数据文件化**（全部提示词）："不要把大数据块放 description，写文件后引用路径"。
- **reason 的图判定军规**：先判 goal 是否已满足→反思是否方向漂移→对照 hints/facts 判断现有 open intents 是否覆盖所有线索→"Open Intents 为空时必须提案"→最多 {max_intents} 条高价值不重叠**可并行**方向。
- 契约与提示词互锁：config 启动时校验提示词组含全部必需占位符（自定义提示词组也要过契约检查）。

### 4.5 Worker 驱动层（workers/ 全亲读）

- 两族驱动：**SeedSessionDriver**（预生成 uuid4 会话——claudecode `--session-id`）与 **RegexSessionDriver**（从 stderr 正则抓会话——codex 系）。
- **claudecode 适配器**（62 行）：execute = `claude --session-id <uuid> --dangerously-skip-permissions -p -- <prompt>`；**conclude = `claude -r <session>`（原生 resume）**——会话连续性完全委托给 CLI 原生能力；健康检查=直打 Anthropic /v1/messages 的 max_tokens=10 "ping"（in-process，无 curl 依赖）。
- worker_select：`(priority, 负载, random)` 排序——优先级、负载均衡、随机打散三合一。

### 4.6 黑板服务语义（server/services.py 257 行全文亲读；models/routers 经调用面确认）

- **认领即租约**：intents.worker / projects.reason_worker 都是认领位 + last_heartbeat_at；**expire_workers / expire_reason_leases 用 SQL 扫描按超时自动清空认领**（心跳停了租约自动回收，意图重新可认领）——与 dispatcher 侧 HeartbeatLease 和启动时序契约构成完整租约协议。
- 状态门：只有 active 项目可写 fact/intent；**hint 在 active/stopped/completed 都可写**（赛后复盘还能补人类判断）；complete 需 completed 状态。
- claim 语义：open（to 为空）且未认领或认领者是自己；否则 409。
- 完成一致性：完成项目必须恰有一条 to='goal' 的完成 intent。

### 4.7 配置与默认值面（config.py 424 行全文亲读 + dispatch.example.yaml 亲读）

- 默认面：interval=3s / max_workers=8 / max_running_projects=3 / max_project_workers=4 / bootstrap timeout 300s+conclude 90s / reason 300s+max_intents **2** / explore 300s+conclude 90s / worker_healthcheck=startup_only / 容器 completed_action=stop（保留现场供检查）/ priority 升序优先。local 示例：max_workers=3、explore 600s、bootstrap 120s（无 Docker 面向单机）。
- **mock worker = 完备混沌测试设施**：每阶段可配延迟区间 + **结果概率分布（Decimal 精度校验必须精确和为 1）** + 条件规则（fact 数 ≥/≤ 阈值或 open_intents 为空时 force 指定结果）——不用真 LLM 就能对调度器做故障注入测试（invalid_json/command_fail/rejected 都是可注入的结果）。
- common_env 继承合并进每个 worker env；容器模式按 worker 类型强制 env 键（claudecode 要 ANTHROPIC_MODEL/BASE_URL/AUTH_TOKEN），local 模式免（复用宿主 CLI 登录态）。

### 4.8 结果验证与去误报

- **验证哲学：黑板只收"已确认的客观事实"**——提示词反复强调"confirmed/objective/no plans, guesses"；完成需要 reason 再判定（complete.from 必须引用非 goal 的合法 fact 并给充分性论证），bootstrap 的完成也要 conclude 先落 fact。
- 无独立 verifier/scorer 组件——信任模型对图的自评 + 人类用 hint 纠偏。这是与 buttercup（三重机器闸）/theori（微内核验证）的明确分野：**Cairn 把验证压在"事实必须可复述"的写入门槛上，而非出口闸上**。

### 4.9 安全与隔离

- 每项目独立容器（host 网络）；`--dangerously-skip-permissions` 全开——隔离全靠容器；local 模式无沙箱（README 明示"以你的用户权限运行，仅限授权环境"）。
- AGPL-3.0 + 商业双许可；免责声明完整。

## 5. 值得借鉴的设计与技巧

1. **黑板三原语 + 完成即图边**：Fact/Intent/Hint 三个概念撑起整个多 agent 协调（Stigmergy），连"完成"都是一条 to='goal' 的 intent——图一致性贯穿始终。角色、工作流、planner 全部不需要。
2. **conclude 兜底 + 会话原生续接**：execute 超时/坏输出→`claude -r` 同会话发"立即停止只总结"指令→知识 salvage 成 fact。**超时不丢知识**，且覆盖条款在首提示词预告、conclude 提示词三重收口——防僵尸的双保险设计。
3. **checkpoint 差分触发 reason**：只在图变化（facts/hints 增长、open_intents 归零）时重新推理——事件驱动调度，对"何时思考"的克制。
4. **心跳租约的完整协议**：dispatcher 后台心跳 → server SQL 过期回收 → 启动时校验 timeout > interval——三件套缺一不可的参考实现。
5. **图快照容器内文件化**：提示词只给路径让 agent 自己读——上下文管理的文件引用模式（对大状态比内联健壮）。
6. **反停滞不变量进契约**：open_intents 空时 reason 必须提案（否则 failed 换人重试）——把"系统不能停下"写成校验规则而不是期望。
7. **mock worker 混沌设施**：概率分布（精确和为 1）+ 条件 force 规则，对调度器做无 LLM 故障注入——分布式 agent 系统的测试范本。
8. **rejected 按 (项目,任务,worker) 三元组冷却**：比全局冷却细——不同 worker 的拒绝互不连坐。
9. **_log_changed 轮询日志去重** + 403/409 分级日志（INFO/WARNING）——长跑服务的日志卫生。
10. **提示词极简主义**：39-55 行/任务、零角色扮演零 CoT 脚手架——把智能押在状态与模型上而非提示词工程上（与 garak 192 探针、pentagi 多角色形成光谱两极）。

## 6. 局限与改进点

- **验证层薄弱**（自觉的取舍）：无机器闸验证 fact 真伪（CTF 判旗在比赛环境有外部裁判，开源通用场景下 fact 质量完全依赖 worker 自律）；reason 的 goal 判定是自评。
- 提示词与实现强耦合 CLI 会话语义（-r 续接），换非 CLI 后端（纯 API agent）需要重做会话层。
- SQLite 单库 + 全表 expire 扫描——规模上限明显（对竞赛场景足够）。
- AGPL 双许可对二次使用者是门槛；仓库无 tests 之外的文档，架构知识全在代码里（本文档即从代码重建）。
- runtime 层（容器 exec/心跳线程实现 ~900 行）经调用面确认语义，未逐行亲读（见 §8）。

## 7. 与其他已审计项目的对比

| 维度 | Cairn（本项目） | shannon | theori-aixcc | buttercup |
|---|---|---|---|---|
| 形态 | **黑板搜索引擎** | DAG 流水线 | 微内核循环 | LangGraph 状态机 |
| 协调 | **Stigmergy（共黑板）** | 结构化输出接力 | 顺序循环 | 反思路由器 |
| 角色 | **无角色（3 任务同 Worker）** | 专化 agent | 无角色 | 6 专职代理 |
| 计划 | **intent 即计划（图上声明）** | DAG 预定义 | 无计划 | 策略→实施分离 |
| 验证 | 写入门槛（事实自律） | 五道闸 | 形式校验 | 三重机器闸 |
| 上下文 | **图快照文件引用** | 证据摘录 | 增量拉取 | 片段集+reducer |

Cairn 补上多 agent 攻防的第四种协调范式：shannon 的**管道**、pentagi 的**计划修订**、buttercup 的**反思路由**之外，它是**黑板涌现**——最接近经典分布式 AI（Hearsay-II 传统）的现代表达，且用"比赛当天凌晨首次全链路跑通就 AK"证明了这种极简在实战中的鲁棒性。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `README.md` | ✅ 亲读全文 | 定位/战绩/架构图/双许可 |
| `dispatcher/scheduler/loop.py` | ✅ 亲读全文 | 935/935 调度主循环 |
| `dispatcher/tasks/` common/reason/bootstrap/explore | ✅ 亲读全文 | 247+284+481+407 |
| `dispatcher/prompts/default/` ×5 | ✅ 亲读全文 | 全部提示词（39-55 行/个） |
| `dispatcher/contracts.py` `output_parser.py` `prompting.py` | ✅ 亲读全文 | 170+47+32 |
| `dispatcher/workers/` base/claudecode/worker_select | ✅ 亲读全文 | 71+62+17 |
| `dispatcher/config.py` + 两个 example.yaml | ✅ 亲读全文 | 424 行默认值面+mock 设施 |
| `server/services.py` | ✅ 亲读全文 | 257/257 黑板语义/租约回收 |
| `server/` models/db/routers、`dispatcher/protocol/client.py` | ✅ 部分 | 经调用面与 services 确认语义 |
| `dispatcher/runtime/`（containers/process/heartbeat/cancellation 等 ~900 行） | ✅ 部分 | 语义经 loop/tasks 调用面确认，未逐行 |
| `workers/adapters/` codex/pi/mock | ⬜ | 同构推定（mock 行为已从 config 侧亲读） |
| `tests/` | ⬜ | 未读 |

## 9. 结论

**Cairn 的核心实现思路是：把渗透测试还原为状态空间搜索，用黑板三原语（Fact/Intent/Hint）与三类同构任务（直解/推理/探索）驱动无角色的 CLI agent 群——调度器做四闸公平派发与事件驱动的重新推理，心跳租约与 SQL 过期回收保证认领一致性，execute 超时后用会话续接的 conclude 兜底把已获知识 salvage 回黑板，"完成"本身也是一条指向 goal 的图边。** 它是已审 18 项中协调范式最古老（黑板/Stigmergy）而工程最克制（提示词 40 行级、三原语、零框架）的系统，用 TCH 唯一 AK 的战绩证明了"少即是多"在进攻型 agent 上的可行性——与 buttercup 的重验证、shannon 的重管道互为反命题，三者合起来构成"多 agent 攻防怎么做"的完整光谱。

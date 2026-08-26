# m-sec-org/BreachWeave 逐行代码审计

> 审计对象：BreachWeave —— **腾讯云 TCH 黑客马拉松（第二期）冠军系统（初赛 1/613+决赛一等奖+TsecBench 公开评测成功率第二 2/14）**：TypeScript/Bun monorepo（Pi 框架派生），**Manager/Solver/Observer 三角色**（Manager 调度题目与 solver 池/Solver 并行解题/Observer 旁路监督看板），Idea/Memory 双板状态 + 19 个内置技能 + pentest 增强分支。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/m-sec-org/BreachWeave |
| 本地路径 | `repos/agents/BreachWeave/` |
| 审计基线 commit | `f5d76b6`（docs: update README.md；main=CTF 基础版，pentest 分支为渗透增强版） |
| 语言 / 规模 | TypeScript/Bun ~31,725 行（packages core/ui-web/ui-tui/libs）+ 技能字典 Python |
| Landscape 定位 | 类型：渗透 Agent / Stars：中高 / 一句话：TCH 二期冠军多 agent 系统（Manager/Solver/Observer+Idea/Memory 双板） |
| License | 见仓库 |
| 关联论文 | 无（战绩表：1/613 初赛+一等奖+TsecBench 2/14） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：CTF 赛场与实际渗透（pentest 分支加资产管理/自动 Planner/项目级 Memory/Attack Flow 回放）的多 agent 协作解题。
- **AI 真伪核查**：真 AI（Pi coding-agent 会话+五类内置提示词+Observer sidecar agent）。
- **差异化定位**：与 Cairn（三期 AK 系统）同为 TCH 赛场样本但**方向相反**——Cairn 极简三原语，BreachWeave 重调度（Manager 控制平面+多 Solver 并行+Observer 监督）；两者合看是同赛事两期冠军的架构演进切面。

## 2. 架构总览

```
Bun monorepo（packages/）
core（运行时 ★）
 ├─ challenge/manager.ts(1684)：题目推进/solver 分配回收/多 agent 协作编排（Manager 控制平面）
 ├─ runtime/runtime.ts(882)：Pi agent 会话运行时
 ├─ solver/：session + extension/
 │    ├─ challenge-observer/（observer-agent 388 ★+observer-loop 376+tools 472：旁路监督 sidecar）
 │    └─ scope-guard.ts(323)：作用域守卫扩展
 ├─ config/：prompts（frontmatter 元数据驱动的提示词 CRUD+内置释放机制）
 │    ├─ builtin/：CHALLENGE_PLANNER ★/kimi-security ★（solver 主提示）
 │    ├─ skills/builtin/ ×19（recon/nuclei/ffuf/jwt/ssrf/payloads-all-the-things/内网/redis RCE…）
 │    └─ tools/（security-kimi-search 612：网络安全搜索工具）
 libs/pi-mcp-adapter（MCP 面板/代理模式） ui-web(1084 server) ui-tui(solver-app 557)
.claude/skills/（bun-dev/pi-mono-framework/shadcn/ui-ux-pro-max——开发用技能，AI 协作开发痕迹）
```

- **提示词即配置**：PromptFile=frontmatter 元数据（model/observer 开关/mcps/tools/skills/subagents 白名单）+Markdown 正文=系统提示；内置释放到用户目录+删除记录（.deleted-builtins.json）——提示词的全生命周期管理。

## 3. 核心模块精读（审计主体；31.7k 行大仓亲读计划：五提示词+Observer+结构）

### 3.1 Observer sidecar（observer-agent.ts 头 140 行亲读）——**全景观最精的看板维护提示词**

- **默认立场序列**：`NO_CHANGE > update existing > delete superseded > add new`——"先闭环已有主线、后收缩、最后才扩张"；"没有足够强的新证据时直接 NO_CHANGE"。
- **Idea/Memory 双板模型**：idea="接下来值得测试什么"（不是事实不是过程；好例子"检查上传点能否 polyglot php 绕过"/坏例子"已经下载了 binary""需要再想想"——**好坏例对照教学**）；memory=durable facts/evidence/failures/hints/constraints（"合并重于累加；同一攻击面新证据优先改写旧记录"）；**failed 最保守**——标 failed 前必答三问（"否定的是整条路线还是只某个 payload/编码/子分支？"、"是否仍有合理变体/未验证前提？"、"是否更适合把失败边界写进 result/memory 而非关闭主线？"）；failure memory 须写清**失败边界**（参数被过滤/403/命中 WAF/逻辑死路）而非动作流水。
- **Board Pressure（体积预算）**："memory ≤12 条、ideas ≤8 条——超体积时压缩本身就是优先动作"；"solver 打开上下文时先看到最值得保留的结论，而不是完整流水账"——**看板即上下文预算**的显式声明。
- **send_efficiency_reminder 四前提**（最后手段非常规动作：明显低效+已持续+不在合理推进期+提醒后未改线；典型低效模式清单：手工逐个 fuzz/列目录/重复试错/已证失败 payload 重试）——**纠偏的克制规范**。

### 3.2 CHALLENGE_PLANNER（Manager 提示全文亲读）——调度器提示词

- "你是比赛调度 planner。**你不解题**，只负责稳定地调度 challenge 实例和 solver"；两目标（当前可见题目内尽快提分/避免调度抖动）。
- **硬约束**：最多 3 个 challenge 实例、solver 总数上限、只用状态里出现过的 id、"不猜隐藏题目、不输出假设性预案"、stale=no 的题不许停、"不自己算时间差只使用状态字段"（防模型时间幻觉）。
- **稳定性原则**："稳定优先于频繁变更、增量补充优先于替换、保持阵型优先于可能更优的大幅重排"——调度抖动的显式抑制。

### 3.3 kimi-security（Solver 主提示头+frontmatter 亲读）

- frontmatter 白名单（bash/read/edit/write/grep/find/ls/security_kimi_search 七工具+16 技能）——**每提示词级的工具/技能白名单**。
- 正文精简（"安全分析专家，借助工具拿 flag；写 python 只写解决当前问题的脚本不写很多代码"；"循环发包用脚本或 shell for，而非逐个命令执行"）；TCH 赛场语境直书。

### 3.4 其余（结构确认）

- scope-guard 扩展（323 行：solver 级作用域守卫）；observer-loop（提醒去重指纹/完成检测/消息摘要）；challenge/manager 1,684 行（控制平面主体）；pi-mcp-adapter（MCP 面板）；security-kimi-search 工具（612 行，"服务于已授权 CTF 与渗透场景"的网安搜索）；19 内置技能（含 Arjun/ffuf 字典等 Python 资产）。

## 4. 值得借鉴的设计与技巧

1. **Observer 看板协议**（NO_CHANGE 默认序+failed 三问+失败边界 memory+体积预算+纠偏四前提）——**旁路监督角色的最完整规范**（与 LuaN1aoAgent 的 Supervisor 互补：那边管"该不该继续"，这边管"状态板别腐化"）；好坏例对照教学法。
2. **提示词即配置文件**（frontmatter 元数据：模型/observer 开关/工具技能白名单/子代理权限+内置释放与删除记录）——提示词全生命周期管理的干净实现。
3. **调度抖动抑制**（稳定优先/增量优先/不猜隐藏题目/不算时间差）——多 agent 资源调度的提示词级防抖。
4. Idea/Memory 双板分离（方向 vs 事实）与"合并重于累加"。
5. 竞赛战绩全披露（1/613+一等奖+TsecBench 2/14 公开评测）。

## 5. 局限与改进点

- 31.7k 行仅五提示词+Observer 深读（challenge/manager 1,684 行控制平面未逐行）；pentest 增强分支未审（main 为 CTF 基础版）。
- Observer 纠偏仅效率提醒（无强制手段）；scope-guard 细节未读。
- .claude 开发技能与产品技能分层清晰（对照 Zen-Ai-Pentest 的混杂）；solver 主提示极简（智能押在技能包与 Observer 上）。

## 6. 与其他已审计项目的对比

| 维度 | BreachWeave（本项目） | Cairn | LuaN1aoAgent | communitytools |
|---|---|---|---|---|
| 赛事 | **TCH 二期冠军** | TCH 三期 AK（3rd） | TCH 顶级排名 | — |
| 角色 | Manager/Solver/Observer | 同构 worker | P-E-O | 协调/执行/验证 |
| 状态 | **Idea/Memory 双板+体积预算** | 图三原语 | 推理/作战图 | attack-chain.md |
| 监督 | **看板维护+纠偏四前提** | 心跳租约 | Supervisor 进展重定义 | 交错盲验证 |
| 提示词管理 | **frontmatter 配置化+内置释放** | 极简 40 行 | 契约式 | CI 校验 |

与 Cairn 构成 TCH 两期冠军的架构对照（黑板极简 vs 调度重装）；其 Observer 看板协议是"状态腐化"这一长程 agent 通用问题的最佳提示词级答案。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `solver/extension/challenge-observer/observer-agent.ts` | ✅ 亲读头 | 140/388（系统提示主体） |
| `config/prompts/builtin/CHALLENGE_PLANNER.md` | ✅ 亲读头 | 50/~120（硬约束+调度序+稳定性） |
| `config/prompts/builtin/kimi-security.md` | ✅ 亲读头 | frontmatter+正文头 |
| `config/prompts/index.ts` | ✅ 亲读头 | 150/239（PromptFile 模型+释放机制） |
| `config/tools/security-kimi-search.ts` | ✅ 定位 | 系统提示头确认 |
| `packages/` 其余（challenge/runtime/libs/ui） | ✅ 结构登记 | 未逐行 |
| `README.md` | ✅ 亲读 | 战绩+架构声明 |

## 8. 结论

**BreachWeave 的核心实现思路是：以调度为中心的多 agent 竞赛系统——Manager 只做控制平面（题目推进/solver 分配/调度抖动抑制：稳定优先、增量优先、不猜隐藏、不算时间差），多 Solver 并行攻坚（frontmatter 白名单化的提示词+19 内置技能），Observer 旁路 sidecar 以"NO_CHANGE>更新>删除>新增"的默认序维护 Idea/Memory 双板（failed 三问保守判定、失败边界入 memory、≤12/≤8 体积预算、四前提才发的效率提醒），提示词经 frontmatter 配置化并带内置释放与删除记录。** 它是 TCH 二期冠军的实战检验样本：Observer 看板协议（状态防腐+克制纠偏）与提示词配置化管理是两个可直接移植的资产；与 Cairn 的对照揭示同赛事两期冠军从黑板极简向调度重装的架构漂移。

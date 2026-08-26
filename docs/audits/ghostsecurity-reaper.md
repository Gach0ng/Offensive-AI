# ghostsecurity/reaper 逐行代码审计

> 审计对象：Ghost Security Reaper —— ~2.3k 行 Go 的 **MITM HTTPS 代理 + 流量检索 CLI**：只拦截 in-scope 流量、请求/响应落 SQLite、CLI 检索检查。**AI 真伪核查结论：零 AI**——但属新变体"**AI 相邻工具**"（README 明示"为人与 AI agent 同样易用"，agent 集成经外部 ghostsecurity/skills 仓库提供，本体无任何模型调用）。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/ghostsecurity/reaper |
| 本地路径 | `repos/agents/reaper/` |
| 审计基线 commit | `5f00c2a`（Add least-privilege permissions to test workflow） |
| 语言 / 规模 | Go ~2,314 行（proxy/daemon/storage/cli 四包） |
| Landscape 定位 | 类型：渗透 Agent（**误分类——实为 AI 相邻的流量捕获工具，零 AI**）/ Stars：中 |
| License | Apache-2.0 |
| 关联论文 | 无（ghostsecurity.ai 文档站） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：安全测试的**流量取证层**——MITM 拦截授权范围内的 HTTPS、结构化落库、CLI 检索（search/get/req/res/tail/logs），供人或 agent 消费。
- **AI 真伪核查**：`grep llm|openai|anthropic|gpt|prompt` 于 Go 源码零命中；无模型调用、无提示词。README 的 agent 关联是"接口友好"声明（输出结构化、CLI 可脚本化），智能在消费侧（外部 skills 仓库）。

## 2. 架构与核心实现（结构+关键段亲读）

```
reaper start（daemon 化，unix/windows 分支）→ MITM 代理（127.0.0.1）
   ├─ Scope（scope.go 35 行亲读）：hosts 精确 + domains 后缀匹配（acme.com 匹配 api.acme.com）
   │   —— handleConnect 先查 scope：不在内则**盲转发不拆密**（只对授权域名做 MITM）
   ├─ 证书：动态签发（cert.go，CA 安装）+ getCertForHost
   ├─ 落库：storage/sqlite（258 行，请求/响应结构化存储）
   └─ CLI：search/get/req/res/tail（实时跟踪）/logs/format/clear/shutdown —— JSON/表格输出
```

- **设计要点**：scope 门在 CONNECT 隧道建立前——出 scope 流量直接盲转发（不解密不落库），MITM 仅施于授权域——**捕获范围的强制执行在代理层**（对照 T3MP3ST/xalgorix 的工具执行层拦截：同一 scope 思想的不同层位）。
- 工程质量：golangci-lint+测试工作流（最近提交即"least-privilege permissions to test workflow"——CI 权限最小化意识）；goreleaser 发布链。

## 3. 与已审计项目的关系

| 维度 | reaper（本项目） | hexstrike-ai | AutoPentestX | Nettacker |
|---|---|---|---|---|
| AI 真伪 | **零 AI（AI 相邻：为 agent 设计）** | 零 LLM（营销 AI） | 零 AI（虚构 Neural Core） | 零 AI（索引误差） |
| 本体 | MITM 流量捕获+检索 | MCP 工具服务器 | 漏扫管线 | YAML DSL 扫描器 |

**零 AI 四例谱系就此完整且出现第四类**：营销文案型（hexstrike，README 吹 AI）/虚构组件型（AutoPentestX，打印不存在的 Neural Core）/索引误差型（Nettacker，纯登记错误）/**AI 相邻型（reaper，本体无 AI 但刻意为 agent 消费设计）**——第四类与前三种性质不同：它不是虚假宣称，而是"agent 生态的周边工具"，landscape 将其归入 agents 更像归类宽松而非误导。对审计方法论而言，这提示 AI 真伪核查需要区分"声称有 AI""假装有 AI""没有 AI"与"服务 AI"四种情况。

## 4. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `internal/proxy/scope.go` | ✅ 亲读全文 | 35/35 |
| `internal/proxy/proxy.go` | ✅ 结构+关键段 | CONNECT/scope/MITM 分流确认 |
| `internal/` 其余（daemon/storage/cli） | ✅ 结构登记 | 清单+职责确认 |
| `README.md` | ✅ 亲读 | 定位声明 |

## 5. 结论

**Reaper 是一个零 AI 的 MITM 流量捕获与检索工具：scope 门在 CONNECT 隧道前（授权域内才 MITM 解密落库，域外盲转发），SQLite 结构化存储加检索 CLI，工程质量规范（lint/测试/最小权限 CI）。** 对本研究的价值在于补全零 AI 谱系的第四类——"AI 相邻"（为 agent 消费设计但本体无模型），与前三种虚假/误差型划清性质界限；其 scope-before-decrypt 的层位选择（代理层强制）是 scope 思想在流量捕获场景的正确落地，可与其在工具执行层（xalgorix/T3MP3ST）的同类实现互为参照。小项目从简：核心分流与 scope 已亲读确认。

# ASCIT31/Dark-Moon 逐行代码审计

> 审计对象：DarkMoon —— 开源自主渗透平台（媒体广泛报道，Juice Shop 57 真实漏洞基准）：**隐私网关（可逆本地令牌化）是头号卖点**——"模型永远看不到你的真实 IP/主机名/凭据"；50 个技术栈专员提示词语料 + MCP 受控执行层 + OpenCode 作 agent 运行时。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/ASCIT31/Dark-Moon |
| 本地路径 | `repos/agents/Dark-Moon/` |
| 审计基线 commit | `5bdd43f`（fix(orchestrator): resolve subagent files via registry, never guess <id>.md） |
| 语言 / 规模 | Python ~7,095 行（mcp/）+ **50 个 agent 提示词 Markdown（conf/agents/，pentest 2,348 行）** + 工具脚本 |
| Landscape 定位 | 类型：渗透 Agent / Stars：中高 / 一句话：隐私优先的自主渗透平台（可逆令牌化网关+50 技术栈专员） |
| License | GPL-3.0 |
| 关联论文 | 无（Darkmoon-Benchmarks 仓库+媒体报道） |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：企业级自主渗透（Web/AD/K8s/网络/CMS 等多技术平面）+ **数据主权**：目标敏感值不出本地边界去 LLM 提供商。
- **AI 真伪核查**：真 AI（OpenCode 作 agent 运行时[entrypoint-opencode.sh]+DarkMoon MCP 服务器提供工具/工作流/隐私网关+50 agent 提示词语料）。
- **差异化定位**：全景观唯一的**隐私架构优先**渗透 agent——把"渗透数据进云模型"（redamon DISCLAIMER 披露的风险）直接架构性消除。

## 2. 架构总览

```
OpenCode（agent 运行时，读 conf/agents/*.md 50 个技术栈专员提示词）
   ▼ MCP
DarkMoon MCP 服务器（mcp/src/server.py 774：execute_command/workflows/dashboard 战役）
   ├─ PrivacyVault（privacy/vault.py 273 ★：可逆本地令牌化）
   ├─ CommandGateway（privacy/gateway.py ★：上下文感知回水+渗出阻断）
   ├─ 工具执行（tools/core/executor 350 + docker_client 354：50+ 工具，容器内）
   ├─ Workflows（tools/workflows/：list/apply 417+379）
   └─ Dashboard API（api/live_push 1050：战役/发现/基础设施节点推送+报告去劣保留）
运行时组装：conf/（darkmoon-mcp/opencode.json/entrypoint×2）；tools/agent-build（生成 agent profile）
```

## 3. 核心模块精读（审计主体）

### 3.1 PrivacyVault（vault.py 头 90 行全文亲读）——可逆本地令牌化

- **设计不变量**（docstring 明文）：确定性（同值同占位符 `10.42.1.5→IP_PRIVATE_001`）；**仅本地可逆**（真实值 Fernet 加密存内存、映射永不落盘明文、永不入日志）；**无明文留存**（去重键=HMAC 指纹，唯一可恢复副本是密文，按需 `rehydrate()` 解密）；TTL/会话域（过期拒绝回水）；**LLM 永远无法解析占位符**——不存在反向映射的 MCP 工具，回水只发生在本地执行路径内。
- 九类占位符（IP_PRIVATE/IP_PUBLIC/HOST_INTERNAL/DOMAIN/URL/EMAIL/PATH/USER/CRED）；检测正则从特异到一般排序（URL→EMAIL→IPv4→FQDN→路径）；内部后缀域（.local/.internal/.corp/.lan/.home/.intra/.test）归类 HOST_INTERNAL；`__repr__` 永不泄漏映射。

### 3.2 CommandGateway（gateway.py 头 80 行全文亲读）——上下文感知回水+渗出控制

- 定位：LLM 与本地执行之间的闸——"回水**不是**朴素全局串替换：占位符只在**被证明安全的 shell 上下文位置**、且只对会话 vault 已知的 token 才还原"。
- **渗出阻断面**：`_PRINT_SINKS`（echo/printf/cat/tee/logger/write——会把值直接打印回给 LLM 的命令）；`_NET_SINKS`（curl/wget/nc/ssh/scp/socat…）+ **curl/wget 出站数据旗标集**（-d/--data* /-F/-T——把占位符值放进请求体=外传）；`/dev/tcp` 与进程替换重定向正则；**shell 元字符注入守卫**（回水值含 `;|&`$…` 即拒——占位符值本身不能变成注入载荷）。
- **秘密占位符绝对禁入执行命令**（"即使粘在旗标上（-pCRED_001）也拒"——对 CRED 类做无词边界扫描）；BLOCK 理由**只含占位符不含真实值**（给 LLM 看也安全）；执行后 stdout/stderr **再消毒**回给 LLM（结果侧同样令牌化）。

### 3.3 pentest.md 状态资格块（2,348 行提示词之头部亲读）——对抗性自我质疑

- **三态按已演示影响赋值**：EXPLOITED（端到端执行了影响）/CONFIRMED（精确请求+原始响应+提取数据或执行轨迹）/UNCONFIRMED（真实线索但影响未演示——**照报不误**，severity≤low、CVSS≤3.9）——"更好地的资格认定，而非更少的发现"。
- **反通胀清单**（写 CONFIRMED 前先 adversarially 挑战自己的声明）：裸 200/可达路由（SPA 任何路径都 200）；仅差分响应；payload 存进或回显在 JSON（"XSS 需要在渲染 sink 中执行"）；文件被服务但未执行；密钥/客户端代码的存在（client trust≠server trust）；**公开即设计的秘密**（Stripe pk_/Sentry DSN/NEXT_PUBLIC_）→info/低；**带就地免责声明的密钥**（附近注释含 demo/example/intentionally public）→info 且**须引用该声明**——"即使字段名叫 privateKey 也要读上下文，绝不按字段名抬级"；CORS 反射任意 Origin+credentials:true=HIGH vs 通配符+credentials=低（"浏览器拒绝通配符来源的凭据"）的浏览器语义级区分。
- 角色定位：审计导体（ISO 27001/NIST 800-115/EBIOS/ATT&CK 对齐），"auditor first, tactician second, router last"。

### 3.4 其余（结构确认）

- 50 技术栈专员语料（php 1393/springboot 1321/flask 1319/aspnet 1315…覆盖 AWS/Azure/GCP/K8s/EntraID/Vault/Jenkins/GitLab/固件/MDM/邮基/边缘代理/无头浏览器等——**全景观最大的技术栈专项提示词语料**）；编排器经注册表解析子代理文件（基线提交即修"never guess <id>.md"）。
- Dashboard API（live_push 1050：战役初始化/发现推送/基础设施节点/战役收尾——**报告去劣保留**："保留已有的更好报告——agent 交了更短更差的版本就不替换"）；工具执行走 Docker 容器。

## 4. 值得借鉴的设计与技巧

1. **可逆本地令牌化的隐私架构**：确定性占位符+HMAC 去重+Fernet 内存密文+TTL+**无反向 MCP 工具**（模型侧结构性不可解析）——"敏感数据不出边界去 LLM"的完整实现，任何要把半敏感环境交给云模型的服务都可抄。
2. **上下文感知回水**：位置安全证明+打印 sink/网络 sink/出站数据旗标/进程替换/dev-tcp 全阻断+回水值元字符守卫（防占位符值变注入）+结果侧再消毒——**令牌化系统的双向完备**（去程消毒容易，回程控制才是难点）。
3. **对抗性状态资格**（UNCONFIRMED 照报不删+反通胀清单含"公开即设计/就地免责/CORS 浏览器语义"）——severity 卫生的最深提示词实现之一（与 xalgorix 逐类标准呼应，方向相反：那边防漏报侧、这边防通胀侧，互补）。
4. 50 技术栈专员语料（分技术平面的专家提示词库）+ 报告去劣保留。
5. "AI 永不直接执行工具，一切经 MCP 受控接口"的执行面声明。

## 5. 局限与改进点

- 令牌化依赖正则检测（九类之外的敏感形态如 base64/JWT/内网 FQDN 变体可能漏检；FQDN 正则会吞公共域名——靠归类为 DOMAIN 而非 HOST_INTERNAL 缓解）；gateway 阻断面是黑名单式（新 exfil 向量如 DNS 查询工具、脚本语言直连不在 sink 集内）。
- mcp 主体（server/executor/workflows/live_push）结构确认未逐行；50 agent 语料仅 pentest.md 深读。
- OpenCode 运行时的会话/预算治理未审；GPL-3.0 对商用有传染约束。
- 基准（Juice Shop 57 vulns）未随仓提交可重推导工件（对照 BoxPwnr/T3MP3ST 可复现文化）。

## 6. 与其他已审计项目的对比

| 维度 | Dark-Moon（本项目） | redamon | xalgorix | guardian-cli |
|---|---|---|---|---|
| 隐私 | **可逆令牌化+回水闸（架构性）** | DISCLAIMER 披露 | — | — |
| 注入防御 | **回水值元字符守卫+exfil 黑名单** | wrap_untrusted | scopeguard | schema 伪造防御 |
| 反通胀 | **对抗性状态资格+免责声明细则** | 加权表 | 逐类证据标准（防漏报侧） | 辩论分诊 |
| 语料 | **50 技术栈专员** | 14 漏洞包 | — | — |
| 运行时 | OpenCode+MCP | 自研 Eino | 自研 Go | 自研 |

它是"数据主权"维度的唯一实现：redamon 用 DISCLAIMER 承认风险、T3MP3ST 的 PLINIAN 教义要求操作员自查，DarkMoon 把"模型看不到真实值"做成架构事实；其状态资格块与 xalgorix 逐类标准构成反幻觉的两翼（防通胀 vs 防漏报）。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `mcp/src/privacy/vault.py` | ✅ 亲读头+函数清单 | 90/273（设计不变量+检测层） |
| `mcp/src/privacy/gateway.py` | ✅ 亲读头 | 80/~300（阻断面+回水策略） |
| `conf/agents/pentest.md` | ✅ 亲读头 | 状态资格块+角色（~90/2348） |
| `conf/agents/` 其余 49 | ✅ 清单登记 | 技术栈覆盖确认 |
| `mcp/src/`（server/executor/workflows）`api/` | ✅ 结构登记 | 未逐行 |
| `README.md` | ✅ 亲读头 | 定位/卖点/媒体 |

## 8. 结论

**DarkMoon 的核心实现思路是：以隐私为第一架构事实的自主渗透平台——PrivacyVault 把九类敏感值确定性令牌化为本地可逆占位符（Fernet 内存密文+HMAC 去重+TTL，且不存在任何模型可调用的反向映射），CommandGateway 只在被证明安全的参数位置回水真实值、对打印/网络/出站数据/进程替换面全阻断并对回水值做注入守卫，结果侧再消毒回模型；智能层由 OpenCode 运行时驱动 50 个技术栈专员提示词（pentest 编排者带对抗性状态资格：UNCONFIRMED 照报、反通胀清单细至'公开即设计/就地免责/CORS 浏览器语义'），执行全走 MCP 受控接口与容器。** 它是已审 35 项中唯一把"LLM 数据主权"做成机制而非声明的系统：令牌化双向完备（去程消毒+回程控制）与对抗性状态资格是两个高移植价值设计；检测正则的漏检面与 exfil 黑名单的开放性是其已知边界。

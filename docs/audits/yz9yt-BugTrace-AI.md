# yz9yt/BugTrace-AI 逐行代码审计

> 审计对象：BugTrace-AI（v1，**已归档**）——浏览器端 React AI 辅助安全分析套件：~20 个单功能分析组件（JWT/XSS/SQL/SSTI/headers/子域/privesc 路径等）经用户自带 OpenRouter key 调 LLM，JSON 约束输出+自修复。README 明示项目已整体重写为 BugTraceAI v2（多 agent 平台，另仓）——景观收录的是本 v1。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/yz9yt/BugTrace-AI |
| 本地路径 | `repos/agents/BugTrace-AI/` |
| 审计基线 commit | `26d0470`（docs: redirect to BugTraceAI v2） |
| 语言 / 规模 | TypeScript/React ~8,055 行（components/services/utils/hooks）；无后端（纯浏览器直调 API） |
| Landscape 定位 | 类型：渗透 Agent（实为浏览器端 AI 辅助分析套件）/ Stars：中 / 一句话：自带 key 的网页版 Web 安全 AI 工具箱（已归档，v2 另仓） |
| License | 见仓库 |
| 关联论文 | 无 |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：把"贴代码/贴请求→AI 分析→结构化结果"做成一组网页小工具：URL 分析器、JWT 分析、headers 报告、JS recon、文件上传审计、代码分析器、XSS/SQL/SSTI 利用助手、payload 锻造/测试、子域发现、DomXSS/PrivEsc 路径finder、通用 WebSec Agent 聊天。
- **AI 真伪核查**：真 AI（浏览器 fetch 直调 OpenRouter chat/completions；19 个提示词模块 938 行）。**架构特征**：零后端——API key 存浏览器、调用在浏览器、密钥不出本机（也算隐私卖点）。
- 归档声明对照表有价值：v1=手动 AI 辅助/无侵入侦察/单遍分析 vs v2=自主多 agent/主动利用+无头浏览器验证/五阶段管线——**作者自己给出的"AI 辅助→agent 化"演进光谱**。

## 2. 架构总览

```
React SPA（App/MainMenu → ~40 组件）
 ▼ 各组件 → services/Service.ts（451 行：统一 callApi）
OpenRouter chat/completions（用户 key；response_format json_object；限速+连续失败计数+AbortSignal）
 ▼
extractJson（markdown 栅栏→首尾大括号回退）→ parseJsonWithCorrection（JSON.parse 失败→把错误与原文喂回模型自修复）
 ▼ 类型化结果 → VulnerabilityCard/severity 样式渲染 → reportExporter（Markdown 报告导出）
提示词层：services/prompts/ 19 模块（chat/consolidation/dast/deepAnalysis/domXss/fileUpload/headers/
         jsRecon/jsonFix/jwt/payloadForge/privesc/sast/sql/ssti/validation/xss + systemPrompts）
payloads/xsspayloads.txt：本地种子语料（喂给生成提示做参考）
```

## 3. 核心模块精读（审计主体）

### 3.1 服务层（Service.ts 关键段亲读）

- **callApi 统一入口**：限速（enforceRateLimit+时间戳）、API 调用计数、AbortSignal 可取消、连续失败计数（成功清零）——浏览器端的调用治理三件套；`response_format: json_object` 结构化约束按需附加。
- **extractJson 两级兜底**：先匹配 ```json 栅栏，再退到首 `{` 到尾 `}` 的子串。
- **parseJsonWithCorrection（JSON 自修复环）**：JSON.parse 抛 SyntaxError → **把解析错误与原始文本回喂模型要求修复**（"Attempting self-correction"）——LLM 结构化输出的自愈闭环（对照 garak 的平衡括号扫描/PyRIT 的 retry-rollback：这里是模型自修而非解析器兜底）。
- 空响应显式报错："模型可能被过滤或拒绝"——对拒绝场景的诚实处理。

### 3.2 提示词层（systemPrompts 全文 + xss.ts 全文亲读；19 模块清单确认）

- **WebSec Agent 系统提示**：'精英进攻性安全专家/资深红队与赏金猎人'人设；**"Offensive First：永远先讲怎么利用再讲怎么修——用户来这就是为了进攻指导"**——用交互规则把模型推向进攻侧的措辞（合规越狱味最浓的一条，但同提示含第 5 条伦理边界："绝不生成破坏性 payload；PoC 一律非破坏（alert/whoami/id）"）；"Assume Expertise 免幼稚化"。
- **XSS payload 生成提示**（payloadForge 范本）：**注入上下文分析先行**（HTML 属性？引号类型？直接进 HTML？JS 字符串内？）→ 三层 payload 要求（简单 alert PoC/cookie 展示 PoC/编码绕过）→ 严格 JSON schema（payload/description/mechanism/encoding 四字段）+ **转义预告**（"payload 里的双引号必须转义为 \\""——把 JSON 转义失败这个最常见失效前置警告）；本地种子语料可选注入做参考（"交叉参考你的上下文分析选择适配"）。
- 其余 17 模块同构（各工具一提示一 schema）；consolidation（多发现合并）/validation（AI 复核）/jsonFix（自修复专用）三模块服务管线语义。

### 3.3 组件层（清单确认）

- ~40 组件按"一个工具一组件"组织（ToolLayout 统一壳）；VulnerabilityCard+severity 六级样式；报告导出 Markdown；ApiKeyWarning/Disclaimer/NoLightMode（彩蛋模态）等体验件。

## 4. 值得借鉴的设计与技巧

1. **JSON 自修复环**：解析失败→错误+原文回喂模型修复——比纯解析器兜底多一层"让模型自己改"的闭环，浏览器端零依赖实现。
2. **注入上下文先行+转义预告的 payload 生成提示**：先分析上下文再生成、把 JSON 转义失效前置警告——小工具级的提示词严谨度。
3. 零后端架构（key 不出浏览器）+ 限速/失败计数/可取消的调用治理。
4. 本地种子语料（xsspayloads.txt）作生成的参考注入。

## 5. 局限与改进点

- "Offensive First"是对齐偏置措辞（依赖模型端伦理条自我约束）；浏览器端 key 与 CSP 面暴露于 XSS。
- 已归档（v2 另仓，本审计对象即景观收录物）；19 提示模块仅 2 份全文亲读（其余同构推定）。
- 无自动化验证（payload 生成了但测试是人工点 PayloadTester）；无记忆/会话态（每工具独立单遍）。

## 6. 与其他已审计项目的对比

| 维度 | BugTrace-AI v1（本项目） | promptmap | guardian-cli | BoxPwnr |
|---|---|---|---|---|
| 形态 | **浏览器 AI 辅助工具箱** | 条件式扫描器 | CLI 框架 | 基准 harness |
| LLM 角色 | 分析/payload 生成（人在环） | 裁判 | 全链 agent | 求解 agent |
| 结构化 | JSON schema+**自修复环** | 条件对 | 各类 schema | 标签/工具调用 |
| 验证 | 人工 | 程序化+裁判 | 辩论 | 平台判旗 |

它是"AI 辅助（非 agent）"形态的基准样本：与 AutoPentestX（无 AI 的自动化）构成光谱两端——人机分工里 LLM 只做单步分析/生成、判断与执行都留给人；README 的 v1→v2 对照表恰好是这条光谱向 agent 化演进的作者自述。

## 7. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `services/systemPrompts.ts` `prompts/xss.ts` | ✅ 亲读全文 | 31+57 |
| `services/Service.ts` | ✅ 亲读关键段 | callApi/extractJson/自修复（~120/451） |
| `services/prompts/` 其余 17 模块 | ✅ 同构推定 | 清单+职责确认 |
| `constants.ts` README.md | ✅ 亲读 | 模型回退表/归档对照表 |
| `components/` ~40 个 `utils/` `hooks/` | ✅ 结构登记 | 未逐行 |

## 8. 结论

**BugTrace-AI v1 的核心实现思路是：把 AI 辅助安全分析压进零后端的浏览器小工具矩阵——约 20 个单功能组件各配一份"上下文分析先行+严格 JSON schema"的提示词，经用户自带 OpenRouter key 直调，JSON 解析失败回喂模型自修复，限速/失败计数/可取消的调用治理齐备，人负责粘贴、判断与验证。** 它是已审 29 项中"人机分工最保守"（LLM 单步辅助）与"部署最轻"（纯前端）的样本：JSON 自修复环与转义预告是可抄的小设计；"Offensive First"人设是提示词级对齐偏置的直白案例；其归档 README 的 v1→v2 对照表为景观提供了"AI 辅助→自主多 agent"演进的作者视角注脚。

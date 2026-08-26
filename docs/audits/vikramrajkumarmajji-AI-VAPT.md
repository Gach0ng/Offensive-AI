# vikramrajkumarmajji/AI-VAPT 逐行代码审计

> 审计对象：AI-VAPT —— README 自称"自主 AI 驱动漏洞评估与渗透测试框架"（AI 层/ML 利用预测/智能报告引擎），但**本体只是一个 React 前端壳**：~1.8k 行 TSX 组件（shadcn/ui 全家桶）+ **全硬编码演示数据**（CVE-2023-1234 假漏洞/unsplash 截图占位/target-app.com 假端点）+ 空的 supabase 类型文件。**AI 真伪核查结论：零 AI、零后端、零数据通路**——README 声称的六层架构（AI/Recon/Vuln/Exploit/Reporting…）无一存在于代码。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/vikramrajkumarmajji/AI-VAPT |
| 本地路径 | `repos/agents/AI-VAPT/` |
| 审计基线 commit | `36b603f`（Update README.md，单提交初始化） |
| 语言 / 规模 | TypeScript/React ~1,836 行（src 组件）；无后端/无脚本/无扫描器代码 |
| Landscape 定位 | 类型：渗透 Agent（**严重误标——纯 UI 原型**）/ Stars：低 |
| License | 未见（无 LICENSE 文件） |
| 关联论文 | 无 |
| 审计日期 / 人 | 2026-08-26 / ZCode |

## 1. 项目解决什么问题（声明 vs 实况）

- **README 声明**：六层架构（AI 层 NPL 分析/侦察层/漏洞层/利用层/报告层）+ 集成 Amass/Nmap/Nikto/Burp/Metasploit + "ML-based CVE Exploitability Model"+"AI-generated executive summaries"+"零数据存储的隐私设计"。
- **代码实况**：
  - 唯一的"功能"是三个仪表盘组件（VulnerabilityDashboard 1,390 行/TargetSpecificationPanel 配置面板/EnhancedReconnaissance 侦察视图）——**纯展示层**；
  - **无任何 API 调用**（grep fetch/axios 只命中 UI placeholder 类名）；无后端目录/无 Python/Go/脚本；`src/types/supabase.ts` 为**空文件**（曾打算接 Supabase 未做）；
  - **全部数据硬编码**：VulnerabilityDetail 的演示漏洞（CVE-2023-1234/CVSS 9.8/proofOfConcept "admin'--"/截图用 **unsplash 图片**/端点 target-app.com）；EnhancedReconnaissance 的主机表（192.168.1.102 等）；home.tsx 的 sample.org/placeholder.com。

## 2. AI 真伪核查（审计核心结论）

- `grep llm|gpt|openai|claude` 于 src **零命中**；README 的"AI"字样（neural pattern recognition/ML exploit prediction/NLP-driven analysis）**无任何对应实现**——连 API 客户端都不存在。
- **零 AI 谱系第六类：纯 UI 原型型**——比营销文案型（hexstrike，至少有真工具服务器）更进一步：**只有界面没有系统**。六类谱系就此完整：营销文案/虚构组件/索引误差/AI 相邻/非生成式 AI/**纯 UI 原型**。

## 3. 组件实况（结构亲证）

```
src/
├─ App.tsx(19)：路由壳
├─ components/
│   ├─ dashboard/：VulnerabilityDashboard(1390 ★假数据仪表盘)/
│   │              VulnerabilityDetail(演示漏洞详情卡片)/
│   │              TargetSpecificationPanel(扫描配置面板——rapid/深度的
│   │              配置选项 UI，无执行)
│   ├─ EnhancedReconnaissance(427)/ProfessionalReconnaissance：主机列表假视图
│   └─ ui/：shadcn 全家桶（40+ 组件）
└─ types/supabase.ts：空文件
```

- 目标规范面板的"assessmentProfile"（rapid/deep 等配置档）是可交互的——但配置**无处可去**（无提交目标）。

## 4. 对本审计的价值

1. **零 AI 谱系终态样本**：第六类（纯 UI 原型）补全谱系——landscape 的"AI 渗透 Agent"标签的最差实况：**概念验证的皮都不算，只是皮的概念图**。
2. **README 驱动开发的警示**：文档声明的六层架构与 1.8k 行 UI 壳的落差是本全景最大的一次（超 Zen-Ai-Pentest 的目录蔓延——那边至少有真 AI）。
3. 与 BugTrace-AI v1（真做分析的浏览器工具）对照：同为学生/个人作品，一个极简但真实、一个华丽但空心。

## 5. 局限与说明

- 按从简标准审计（纯前端+假数据，无核心链可读）；若后续补后端可复审。
- 不排除作者确有后续计划（supabase 类型文件的空壳是意图痕迹）——本审计只对当前代码实况负责。

## 6. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `src/components/dashboard/`（三组件） | ✅ 结构+数据源核查 | 假数据确认 |
| `src/components/EnhancedReconnaissance.tsx` `home.tsx` | ✅ 数据源核查 | 硬编码主机/域名 |
| `src/types/supabase.ts` | ✅ 确认 | 空文件 |
| `README.md` | ✅ 亲读 | 六层架构声明（与实况对照） |

## 7. 结论

**AI-VAPT 是一个只有前端的 UI 原型：README 声明六层 AI 架构与工具集成，代码实况是 ~1.8k 行 React 仪表盘组件加全量硬编码演示数据（假 CVE/unsplash 截图/占位端点），零 AI、零后端、零数据通路（连 API 客户端都不存在）。** 它把零 AI 谱系补到第六类"纯 UI 原型型"——本全景审计 55 项中声实落差最大的样本；按从简标准处理，其价值是谱系学完整性（六类齐）与"README 驱动开发"的警示价值。

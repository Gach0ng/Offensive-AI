# OWASP/Nettacker 逐行代码审计

> 审计对象：OWASP Nettacker —— 老牌模块化自动化渗透测试框架（YAML 声明式模块引擎）。**重要分类学发现：全库零 AI/LLM 内容**——它被 Yeti landscape 收进"进攻型 AI/Agent"清单属于误分类，本体是传统自动化扫描器。
>
> 审计方法注记：核心引擎（base.py 全文、http 引擎、模块 DSL、模块清单全量）亲读；分类结论经全库 grep 交叉验证（无 llm/openai/anthropic/gemini/模型调用等任何命中，仅 socket 模块等子串假阳性）。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/OWASP/Nettacker |
| 本地路径 | `repos/agents/Nettacker/` |
| 审计基线 commit | `103ef3a1f5d04bcf319fa0834c140cc9d9e5b174`（2026-08-22，活跃维护） |
| 语言 / 规模 | Python（poetry），57 个 .py（核心约数千行）+ **128 个 YAML 模块** |
| Landscape 定位 | 类型：渗透 Agent（**实为传统模块化扫描器，误分类**）/ Stars：4k+ OWASP 旗舰 / 一句话：YAML 声明式模块引擎的自动化渗透框架——侦察/漏扫/爆破，无任何 AI |
| License | Apache-2.0 |
| 关联论文 | 无 |
| 审计日期 / 人 | 2026-08-24 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：自动化渗透测试与信息收集——端口/服务/子域枚举、目录发现、CVE 漏洞验证（89 个 CVE 模块）、协议爆破（ftp/ssh/smb/smtp/pop3/telnet）。
- **输入输出**：目标（IP/段/CIDR/域名/URL 混合）+ 模块选择 + 线程数 → HTML/JSON/CSV/文本报告 + d3 树状攻击图 + Web UI/API/数据库。
- **差异化定位（在本清单语境下）**：它不是 AI agent，而是 **AI agent 们要驱动的"传统工具层"样本**——landscape 收录它的合理动机应是"渗透 Agent 的工具底盘/对照基线"。审计价值：看懂 AI 层之下这代工具的模块 DSL 与多阶段链式机制。

## 2. 架构总览

```
nettacker.py CLI ──▶ core/app.py（扫描编排: 多线程/目标解析/SOCKS 代理/进度）
                       ▼
              core/module.py（模块装载: YAML → 引擎调用）
                       ▼
     core/lib/*（协议引擎族: BaseEngine 抽象基类 ─ http/ftp/ftps/ssh/smb/smtp/
                smtps/pop3/pop3s/telnet/ssl/socket 各实现 run()）
                       ▼
     模块 YAML（128 个: scan×30 / vuln×89 / brute×9）
       payload.steps ── nettacker_fuzzer 笛卡尔积展开 ──▶ 条件判定(and/or+regex)
       dependent_on_temp_event ──▶ 步骤间依赖（经 DB 临时事件 + 忙等轮询）
                       ▼
     database（事件/临时事件落库）+ graph（d3_tree 报告）+ web（UI/API）
```

- **编排方式**：**YAML DSL 数据驱动**——每个模块声明 payloads（library 协议 + steps 步骤序列 + response 条件），引擎解释执行；无 LLM、无 agent 循环、无规划。
- **执行环境**：本机直连（可选 SOCKS 代理），多线程并行目标/子域。

## 3. 目录结构逐层解读

```
nettacker/
├── core/           # app.py(编排) module.py(装载) fuzzer.py(载荷文件读取) graph.py ip.py
│   └── lib/        # ★ base.py(313 行引擎基类: 条件判定/依赖替换) + 13 个协议引擎
├── modules/        # ★ 128 个 YAML: scan(30: port/dir/subdomain/版本探测/CMS) 
│                   #   vuln(89: CVE 检查至 2026) brute(9: 协议爆破)
├── lib/            # payloads(wordlists/User-Agents) graph(d3 树) html_log icmp(纯 Python ping) compare_report
├── database/ api/ web/ locale/
```

## 4. 核心模块逐行精读（审计主体）

### 4.1 模块 DSL（以 apache_cve_2021_41773.yaml 全文亲读为范本）

- **info 段**：name/author/severity（数字评分）/**profiles 标签体系**（vuln/http/critical_severity/cve2021/cve/**cisa_kev**/apache/path_traversal/lfi）——标签即检索维度，CISA KEV 编目直连。
- **payloads 段**：`library: http` 选协议引擎 → steps 列表（method/timeout/headers/ssl/url）。
- **nettacker_fuzzer**（核心机制）：`input_format: "{{schema}}://{target}:{{ports}}/{{path}}"` 模板 + data 变量表（path 4 条编码变体 × schema 2 × ports 2）——**笛卡尔积展开成 16 个请求**（对同一 CVE 的多种绕过编码一次打全）。
- **response 判定**：`condition_type: and` + conditions（status_code regex 200 **且** content regex `root:(\S+):`）——**证据导向**（必须真读到 /etc/passwd 内容才算命中，非仅状态码）；`reverse` 支持否定条件。

### 4.2 引擎基类（core/lib/base.py 全文亲读）

- **BaseEngine/BaseLibrary 抽象**：每协议一个引擎实现 run()，模块 YAML 驱动。
- **多阶段依赖机制**（最有意思的设计）：步骤可声明 `dependent_on_temp_event`——上游步骤结果写入 DB 临时事件表，下游步骤**忙等轮询**（0.1s 间隔）取回并做字符串替换注入自己的参数（:49-107）；`find_and_replace_dependent_values` 递归遍历步骤字典做模板替换。这使单模块能表达"先枚举→再用枚举结果打第二轮"的链式逻辑——**YAML DSL 里的小型数据流**。
- `process_conditions`：and/or 组合 + regex + reverse 的统一判定器。
- `filter_large_content`：响应超 150 字符截断到词边界（日志防炸）。

### 4.3 执行与报告

- app.py：目标解析（IP/段/CIDR/域名混合）、多线程扫描编排、SOCKS 代理支持；http 引擎（lib/http.py 亲读）：aiohttp 请求 + `response_conditions_matched` 判定。
- 结果三路：数据库（事件/临时事件）、graph d3 树可视化、HTML/JSON/CSV/文本报告；Web UI + API 可远程驱动。

### 4.4 AI 内容核查（本审计的核心问题）

- 全库 grep：`llm|openai|gpt|gemini|claude|anthropic|ai_module` ——**仅 2 个假阳性**（`socket` 模块名含子串、icmp 注释），**无任何模型调用/提示词/agent 代码**。
- README 自述也完全不含 AI 主张（"automated penetration testing and information-gathering framework"）——**误分类在 landscape 侧，不在项目营销侧**（与 hexstrike-ai 相反：那是 README 吹 AI 代码没有，这里是代码干净清单收错）。
- 对照清单语境的合理定位：Nettacker 属于"**AI 渗透 Agent 的工具底座与对照基线**"——strix/cai 的 Kali 工具栈、pentagi 的 40+ 工具封装，本质都是在 AI 层重新包装这代能力；Nettacker 的 YAML 模块 DSL 恰是"无 AI 版的探针声明"（对照 garak 的 probe 声明式设计，同构不同层）。

### 4.5 安全观察（顺带）

- `find_and_replace_dependent_values` 用 **`eval()`** 执行模块 YAML 里的依赖表达式（:79/:100 `key_value = eval(key_name)`）——**模块文件等价于代码**：加载不可信 YAML 即 RCE。对自带模块库无碍，但自定义模块面需警惕。

## 5. 值得借鉴的设计与技巧

1. **YAML 模块 DSL + 笛卡尔积 fuzzer**：一个 CVE 模块声明多编码变体×协议×端口一次打全——攻击面声明的数据化（garak 探针/promptfoo 插件的同思想在传统扫描器的前身）。
2. **证据导向判定**：必须匹配漏洞实际产出内容（/etc/passwd 的 root 行）而非仅状态码——误报控制的老派正确答案。
3. **dependent_on_temp_event 步骤链**：DB 临时事件 + 忙等取回的模块内数据流——让声明式模块表达两阶段攻击（枚举→利用）。
4. **profiles 标签体系**（含 cisa_kev）：模块检索即威胁情报编目。
5. 128 模块全 YAML（89 个 CVE 至 2026）：**知识库与引擎彻底分离**——社区可纯数据贡献。
6. 150 字符词边界截断：最朴素的日志防爆。

## 6. 局限与改进点

- **零 AI 内容**（按清单预期读此审计者请注意）：若要找 agent 设计，本项目无可借鉴处；其价值是底座与对照。
- eval() 于模块表达式：不可信模块=代码执行。
- 忙等轮询依赖（0.1s 循环）在高并发下的 DB 压力；severity 用裸数字非 CVSS 向量。
- 多线程模型（非 asyncio 为主），协议引擎族重复样板较多。

## 7. 与其他已审计项目的对比

| 维度 | Nettacker（本项目） | hexstrike-ai | garak | strix |
|---|---|---|---|---|
| 形态 | **传统模块化扫描器（零 AI）** | MCP 工具服务器（零 LLM） | LLM 探针扫描器 | LLM 蜂群 |
| 攻击声明 | YAML 模块 DSL（128） | Flask 端点（156） | Python 探针类（192） | 提示词+工具 |
| 判定 | regex 证据条件 | stdout 原样 | 检测器+Se/Sp CI | 报告校验 |
| 在 AI 栈中的位置 | **被驱动层/底座** | 被驱动层（MCP 化） | 驱动层 | 驱动层 |

两个"零 AI"样本对照成趣：hexstrike 是"把传统工具暴露给 LLM"的桥，Nettacker 是"AI 出现之前就把攻击声明数据化"的根——**landscape 把根与桥都算作进攻型 AI，是分类噪声**；本审计如实记录并校准。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `core/lib/base.py` | ✅ 亲读全文 | 引擎基类+依赖机制 |
| `core/lib/http.py` | ✅ 亲读头+结构 | 请求引擎 |
| `modules/vuln/apache_cve_2021_41773.yaml` | ✅ 亲读全文 | DSL 范本 |
| `modules/`（128 个） | ✅ 清单亲读 | scan/vuln/brute 分类计数 |
| `core/app.py` `module.py` `fuzzer.py` | ⬜ 部分 | 职责确认 |
| `database/` `web/` `api/` `lib/graph` | ⬜ | 结构登记 |
| AI 内容核查 | ✅ 全库 grep | 零命中（2 假阳性已排除） |

## 9. 结论

**OWASP Nettacker 的核心实现思路是：把渗透测试能力做成"协议引擎 + YAML 模块 DSL"的数据驱动扫描器——128 个模块（89 个 CVE 检查）各自声明笛卡尔积模糊模板与证据导向的 regex 判定条件，模块内经 DB 临时事件表达"枚举→利用"两阶段依赖，多线程编排输出图/报告/库三路结果；它没有任何 AI 成分，被 landscape 收入进攻型 AI 清单属误分类。** 对本研究的价值有二：其一，作为 AI 渗透 Agent 的"工具底座与无 AI 对照基线"（strix/pentagi 的工具栈本质是对这代能力的 AI 包装）；其二，其 YAML 攻击声明 DSL 与 garak 探针声明、promptfoo 插件声明同构——"攻击知识数据化"在 AI 前后一脉相承。

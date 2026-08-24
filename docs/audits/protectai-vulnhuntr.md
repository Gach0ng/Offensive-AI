# protectai/vulnhuntr 逐行代码审计

> 审计对象：VulnHuntr —— ProtectAI 出品的 LLM 驱动 Python 漏洞扫描器（自治上下文获取式 SAST），以"在流行 Python 包里挖出 22 个 0-day"闻名的实战派工具。
>
> 审计方法注记：全库仅 4 个 Python 文件共 1,334 行，**100% 逐行亲读**——本项目是九个已审项目中唯一达到全覆盖的。

## 0. 元信息

| 项 | 值 |
|---|---|
| 仓库地址 | https://github.com/protectai/vulnhuntr |
| 本地路径 | `repos/agents/vulnhuntr/` |
| 审计基线 commit | `ead88c5adba4279dae5c56d65124c530a9a1c5ae`（2025-02-06，unredact-vulns；此后无提交，项目实质冻结） |
| 语言 / 规模 | Python，4 个文件 1,334 行（`__main__.py` 489 + `prompts.py` 394 + `symbol_finder.py` 261 + `LLMs.py` 190） |
| Landscape 定位 | 类型：渗透 Agent（实为 LLM SAST 扫描器）/ 一句话：LLM 按需拉取符号定义的迭代式白盒漏洞挖掘，找到过 22 个真实 0-day |
| License | AGPL-3.0 |
| 关联论文 | 无（战果在 ProtectAI 博客：7 个流行 PyPI 包 22 个 0-day，含 LFI/RCE/SSRF/SQLI/AFO） |
| 审计日期 / 人 | 2026-08-24 / ZCode |

## 1. 项目解决什么问题

- **目标场景**：对 Python 仓库做**面向远程可利用漏洞**的静态分析——LFI/RCE/SSRF/AFO/SQLI/XSS/IDOR 七类，要求漏洞链从"远程用户输入"走到"危险 sink"。
- **输入输出**：`python vulnhuntr -r <repo> [-a 路径] [-l claude|gpt|ollama]`；输出每文件的 JSON 报告（scratchpad 推理过程 / analysis 结论 / **poc 演进代码** / confidence_score 0-10 / vulnerability_types / context_code 请求清单）+ structlog JSON 日志。
- **差异化定位**：核心洞见是**"LLM 按需拉代码"替代"整仓塞上下文"**——模型先看入口文件，然后像人类审计员一样点名要它需要的类/函数源码，用 jedi 精确取回，最多迭代 7 轮拼出完整污点链。README 警告"可能烧掉大额 API 账单"——它的上下文策略是贪心的。小而锋利，与 cve-bench（本清单 benchmarks 组）同源生态。

## 2. 架构总览

```
RepoOps（文件收集）
   ├─ get_relevant_py_files: rglob("*.py") 排除 test/example/docs/venv/dist
   └─ get_network_related_files: ★ 100+ 条正则识别 ~25 个 Python Web 框架的
        入口特征（路由装饰器/handler 签名/服务器启动调用）——只分析"有远程面"的文件
   ▼
README 总结调用（一次 LLM：README → 安全视角的攻击面摘要）
   ▼
系统提示 = SYS_PROMPT（"世界首席 Python 安全专家"人设+七类漏洞清单）
           + <readme_summary>（攻击面上下文）
   ▼
逐文件循环:
   ① 初始分析: 文件代码 + 指令 + 分析方法 + 报告规范 + Response JSON schema → Response
   ② 若 confidence>0 且有漏洞类型: 对每个 vuln_type 进入二级循环（≤7 轮）:
        模型在 Response.context_code 里点名要代码（name/reason/code_line）
        → SymbolExtractor（jedi 三级搜索）取定义源码
        → 重组 prompt: 文件代码+已收集定义+该漏洞专属模板+★示例绕过 payload+上一轮 analysis
        → 直到不再请求新代码（容忍一次重复）或 7 轮
```

- **编排方式**：固定两层循环（文件级 × 漏洞类型级 × 7 轮上下文获取），无 agent 框架、无工具调用协议——**"工具调用"被降维成 JSON 输出里的一个字段**（context_code 列表），宿主解析后喂回下一轮。
- **LLM 层**（LLMs.py 亲读）：三个客户端——Claude（**prefill 技巧**：messages 里预置 assistant 消息 `{    "scratchpad": "1.` 强迫续写合法 JSON 开头，LLMs.py:88；响应 `replace('\n','')` 剥掉全部换行——因为 schema 字段描述明确要求"no line breaks"，配合 pydantic 解析）、ChatGPT（json_object response_format）、Ollama（temperature=1）。历史列表只追加不回传（每轮实际无状态，跨轮记忆全靠 `<previous_analysis>` 标签显式传递）。
- **执行环境**：纯静态分析，无沙箱（不执行目标代码），唯一外呼是 LLM API。

## 3. 目录结构逐层解读

```
vulnhuntr/
├── __main__.py       # ★ 全部编排：RepoOps 正则筛文件、pydantic_xml 提示组装、
│                     #   两级分析循环、CLI（亲读全文）
├── prompts.py        # ★ 系统提示/初始分析/分析方法/报告规范 + 7 个漏洞专属模板
│                     #   + 每类示例绕过 payload 语料（亲读全文）
├── symbol_finder.py  # ★ jedi 三级符号检索器（亲读全文）
└── LLMs.py           # ★ Claude(prefill)/ChatGPT/Ollama 三客户端（亲读全文）
```

## 4. 核心模块逐行精读（审计主体，100% 覆盖）

### 4.1 入口与初始化（__main__.py）

- structlog 全 JSON 日志落 `vulnhuntr.log` + faulthandler（崩溃可诊断——小工具的健壮性自觉）。
- **文件收集双闸**：路径排除（/test、/docs、site-packages、.venv…+ 文件名 test_/conftest）→ **网络面正则**（`__main__.py:98-215`，亲读）：100+ 条模式覆盖 async request 处理器、Gradio/Flask/FastAPI/Django/Pyramid/Bottle/Tornado/WebSocket/aiohttp/Sanic/Falcon/CherryPy/web2py/Quart/Starlette/Responder/Hug/Dash/GraphQL(graphene/strawberry)/Lambda/Azure Functions/GCP Functions 的入口特征，外加 ~15 种服务器启动调用（gunicorn/waitress/hypercorn/daphne/gevent/grpc…）。**"只审有远程攻击面的文件"是这个工具的第一道精度闸**，也是成本闸。Django 的 `url(.*?\)` 模式旁标注 "Too broad?" ——作者自己的诚实存疑。
- `--analyze` 可指定单文件/目录绕过网络筛选（定向审计入口）。

### 4.2 提示词体系（prompts.py，394 行全文亲读）

- **系统提示**："世界首席 Python 安全分析专家"人设 + 七类漏洞 + 四条分析要求（追踪远程输入到 sink、多步绕过链、非显见向量、组件交互性漏洞）+ **"你有多次机会请求补充上下文，善用它们"**（把迭代获取上下文写进角色）+ README 摘要注入 `<readme_summary>`。
- **初始分析模板**：找入口点→找七类 sink→记录安全控制（为绕过做准备）→标记需补上下文区域；**"宁可多报"**："只要存在可能性就放进 vulnerability_types——后续步骤会继续分析"（召回优先，精度交给二级循环）。
- **七个漏洞专属模板**：各含高危函数清单（open/eval/pickle.loads/requests.get/cursor.execute…）、间接向量（插件加载、日志查看器、云元数据、模板引擎）、考量清单（净化有效性、编码技巧、TOCTOU、CSP、数据库方言差异）；SQLI 模板最详（7 步法：入口→流→SQL 位置→输入处理→控制评估→绕过→影响）。
- **示例绕过语料**（每类 5-7 条真实 payload）：RCE 含 `getattr(__import__('os'),'system')`、`${IFS}`、pickle RCE 串；XSS 含 Jinja2 SSTI 全链 `{{request.application.__globals__.__builtins__...}}`；SSRF 含 gopher/dict/file 协议——**给模型的"绕过风格提示"而非字典**。IDOR 无 payload（本质是逻辑缺陷，给了判定要点：ID 类参数+必须邻近鉴权检查）。
- **报告规范**（GUIDELINES）：单 JSON 合并所有发现、未知填 None、**scratchpad 在 analysis 前**（先推理后结论的输出结构）、请求上下文的格式约定（`ClassName` vs `func_name,ClassName.method_name`、**禁止请求标准库/三方库代码**）、**置信度军规："PoC 若不是从远程网络调用开始的，confidence 封顶 6"**（远程性硬约束进评分）、PoC 必须针对被分析代码且要绕过代码路径上的安全控制。
- 组装用 pydantic_xml：每个片段（file_code/instructions/guidelines/response_format…）都是带 XML 标签的模型实例——**提示词工程数据化**，与 PyRIT 的种子提示 YAML 同思想。

### 4.3 二级分析循环（__main__.py:400-486 亲读）

- 触发条件：`confidence_score > 0 and len(vulnerability_types)`；逐漏洞类型独立循环（同一文件对每类各走一遍）。
- **上下文获取协议**：首轮不取代码（用初始分析上下文）；第 2 轮起解析上轮 `context_code` 请求（name+reason+**code_line**——模型必须给出它看到该符号的那行代码，用于定位），SymbolExtractor 取回后**累积**进 stored_code_definitions（去重：已请求的不再取）；重组 prompt 时全部已收集定义 + 该类模板 + 示例绕过 + `<previous_analysis>`（上轮 analysis 文本）注入。
- **终止三条件**：模型不再请求新代码即停；**容忍一次重复请求**（same_context 标志——第二次还重复才断，防误停）；硬顶 7 轮。
- 循环末尾有一个孤立的 `pass`（:486）——无害残留，代码卫生注记。

### 4.4 符号检索器（symbol_finder.py 全文亲读——本项目工程含金量最高处）

- **三级递降搜索**：①`jedi.Script.search`（先用模型给的 code_line **规范化 grep**（去空格/换行/引号统一）定位候选文件再搜——注释直言 "uses the code_line from bot to grep"）；②`jedi.Project.search`（处理 `var = ClassName(); var.method()` 实例模式）；③`Script.get_names(all_scopes)` 全名字扫描，兜底再把 code_line 与 name.description 互相规范化匹配。
- **六类边界情况文档化在 docstring**（:16-31）：变量方法调用、类实例变量、别名导入、纯模块符号（`from api.apps import app`）、以及"code_line 出现在 jedi description 里"的怪例（举的是真实目标 gpt_academic 的例子）——**踩坑清单即注释**。
- 类型分支处理 statement/function/class/instance/module 各自的匹配与 infer/goto 策略；`/third_party/` 或空路径命中时返回占位符："Third party library. Claude, use what you already know about {full_name}"——**三方库零读取，靠模型先验**（与提示词禁令呼应，成本与噪声双控）。
- 排除 /test、_test/、/docs、/example；定义源码按 jedi 起止行列精确切出。

### 4.5 LLM 客户端（LLMs.py 全文亲读）

- Claude 的 **prefill 强制 JSON**：messages 追加 assistant 前缀 `{    "scratchpad": "1.`（:88），响应剥换行后 `prefill + text` 交 `model_validate_json`——与 Anthropic 官方 cookbook 的 JSON mode 配方的直接落地（extract_between_tags 的 docstring 也注明出处）；README 总结调用豁免 prefill（自由文本+自取 `<summary>` 标签）。
- ChatGPT 走原生 json_object；Ollama 无结构化保障（temperature=1，解析靠 pydantic 兜底）。
- 异常体系：RateLimit/APIConnection/APIStatus 三类包装；**校验失败直接抛**（注释掉的"截取首个 { 重试"修复代码留在原地——诚实的不完善）；Anthropic 客户端 max_retries=3 交给 SDK。

### 4.6 结果验证与去误报

- **置信度军规**（PoC 非远程入口起手→封顶 6）是唯一的评分约束；无机器复核、无去重、无 schema 外校验——验证哲学是"上下文完备性换置信度"（schema 描述明言 10 分="拥有完整输入到输出代码链"）。
- 召回优先的两段式（初始宁多报→二级逐类精化）+ 7 轮上下文拼链，误报控制靠"链是否拼得完整"的人工判读。

### 4.7 配置默认值面（亲读汇总）

模型默认 claude-3-5-sonnet-latest / chatgpt-4o-latest / ollama llama3；`ANTHROPIC/OPENAI/OLLAMA_BASE_URL` 可指自托管端点；max_tokens 4096；二级循环 7 轮；同一上下文容忍 1 次重复；README 建议 Claude 优于 GPT（实测结论写进文档）+ 账单警告。

### 4.8 安全与隔离

无执行面（纯静态）；密钥走 .env；无目标仓库大小/类型限制（rglob 全仓）——大仓成本风险由 README 警告兜底。

## 5. 值得借鉴的设计与技巧

1. **上下文按需拉取协议（LLM 点名+宿主取码）**：把 RAG 的"检索"变成"模型显式请求符号"，配 jedi 精确定义提取——白盒审计场景对向量检索的降维打击；**code_line 随请求携带**（模型给定位锚点）是协议的关键细节。
2. **prefill 强制 JSON**（Anthropic 配方）+ 剥换行 + schema 字段描述写"no line breaks"：三件套把弱结构化模型驯成 JSON 输出器。
3. **网络面正则文件筛**：100+ 模式覆盖 25 框架——"远程可利用"约束转化为入口工程，兼作成本闸与精度闸。
4. **三方库占位符**："use what you already know about {name}"——把模型先验当依赖文档用，零 token 零噪声。
5. **示例绕过语料**：每漏洞类 5-7 条风格化 payload（含 SSTI 全链、IFS 绕过）——教"绕过思维"而非穷举。
6. **置信度军规**：远程性硬约束进评分（非远程 PoC 封顶 6）——一句话防住最常见的误报类别。
7. **召回优先两段式**：初始宁滥勿缺、二级逐类拼链精化——把"精度问题"转化为"上下文完备性问题"。
8. **踩坑即文档**：symbol_finder 的六边界 docstring 全部来自真实目标（gpt_academic 例）。
9. **终止的重复容忍**：请求重复一次不断、两次才断——防抖动误停。

## 6. 局限与改进点

- **项目冻结**（2025-02 后无提交）：模型默认已过时、无多模态/agent 目标支持。
- 无验证闭环：PoC 不执行、置信度不自检、多文件漏洞（跨文件入口→sink 链只能靠 context_code 拉齐，入口文件选错即漏）。
- 单文件为分析单元：入口选择依赖正则筛——框架覆盖外（如纯 gRPC/自定义协议服务器部分覆盖）会整仓漏报；Django url 模式作者自注 "Too broad?"。
- Claude 响应剥全部换行的 hack 脆弱（模型输出含换行语义的 PoC 会被破坏）；Ollama 路径无结构化保障。
- LLM history 只存不用（无状态调用），跨文件不共享任何记忆。

## 7. 与其他已审计项目的对比

| 维度 | vulnhuntr（本项目） | garak | PyRIT | shannon |
|---|---|---|---|---|
| 形态 | **LLM SAST**（按需拉码白盒） | 探针扫描器 | 红队编排库 | 渗透流水线 |
| 攻击对象 | 源代码 | 模型行为 | 模型行为 | 运行中的应用 |
| 上下文策略 | **模型点名+jedi 取码**（≤7 轮） | 静态探针语料 | 对抗对话+DB | 文件黑板+子代理 |
| 结构化输出 | prefill+pydantic JSON | 检测器打分 | 规范化 schema 裁判 | TypeBox collector |
| 验证 | 置信度军规+人工 | Se/Sp 校准 CI | 裁判元评估 | 五道闸 |
| 战果可信度 | **22 真实 0-day**（实证） | — | — | — |

它证明了"小而锋利"路线：无框架、无沙箱、无编排器，4 个文件拿下 22 个 0-day——**核心资产是提示词协议与符号检索器，不是架构**。

## 8. 文件级审计进度

| 路径 | 状态 | 备注 |
|---|---|---|
| `vulnhuntr/__main__.py` | ✅ 亲读全文 | 489 行逐行 |
| `vulnhuntr/prompts.py` | ✅ 亲读全文 | 394 行逐行 |
| `vulnhuntr/symbol_finder.py` | ✅ 亲读全文 | 261 行逐行 |
| `vulnhuntr/LLMs.py` | ✅ 亲读全文 | 190 行逐行 |
| `README.md` `LICENSE` `.env.example` `Dockerfile` | ✅ 已读 | 关键事实核对 |

**覆盖率：100%（全库逐行亲读）。**

## 9. 结论

**VulnHuntr 的核心实现思路是：把白盒审计还原成"人类审计员的工作方式"——先用 25 框架正则筛出有远程攻击面的入口文件，LLM 以世界首席安全专家人设做宁滥勿缺的初判，再对每个漏洞类型进入最多 7 轮的"点名要码"循环（jedi 三级符号检索按模型给的 code_line 锚点精确取回定义、三方库一律用模型先验替代），配合每类示例绕过语料与"Poc 非远程入口封顶 6 分"的置信度军规，把完整污点链拼进上下文直到模型不再索要新代码。** 全部精髓浓缩在 1,334 行里：prefill 强制 JSON、pydantic_xml 提示组装、踩坑即文档的符号检索器——零框架依赖却产出 22 个真实 0-day，是"提示词协议+精确工具"胜过"重架构"的最佳实证。

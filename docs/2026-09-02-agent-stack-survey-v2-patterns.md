# 进攻性 AI Agent 技术栈调研·第二卷：实现模式手册

> **日期**：2026-09-02
> **定位**：第一卷 `docs/2026-09-02-agent-stack-survey.md` 回答"成熟方案用什么"，本卷回答"具体怎么写"。八个机制、七个范本项目、全部 verbatim 代码节选带 `文件:行号`，可直接按图索骥去仓库核对原文。
> **取证方法**：三个并行取证通读源码，逐机制定位实现文件；节选保留原注释，`...` 为省略。**本卷还包含对第一卷与原审计文档的三处复核更正（见 §8）**。
> **代码基准**：repos/ 下浅克隆的当前 HEAD；行号以该版本为准。

---

## 目录

1. [接入层三式](#1-接入层三式)：统一客户端 / 回退链 / 网关预算账本 / 重试分级
2. [循环与协议](#2-循环与协议)：微内核 / 模型三用法 / 生命周期协议 / 上报即工具
3. [解析与修复](#3-解析与修复)：exact-keys / 回喂自修复 / 工具错误回注 / trace 打捞
4. [上下文治理](#4-上下文治理)：两段式压缩 / 工具输出三重闸 / 摘要闸 / 空补全恢复
5. [预算与续跑](#5-预算与续跑)：渐进预算协议 / 四维层级预算 / 会话续跑
6. [弱模型适配](#6-弱模型适配)：三级规约降级 / schema 拍平 / strict 降级与参数矫正
7. [组装顺序](#7-组装顺序对照双车道-phase-2-的落地路线)
8. [复核更正记录](#8-复核更正记录)

---

## 1. 接入层三式

### 1.1 统一客户端：枚举 + 单工厂（buttercup）

26 个模型（Azure/OpenAI/Claude/Gemini 四家）全部收敛为 LiteLLM 网关里的 deployment 名，客户端永远只用一个类。`buttercup/common/src/buttercup/common/llm.py:18-45`（节选）：

```python
class ButtercupLLM(Enum):
    """Enum for LLM models available in LiteLLM."""
    OPENAI_GPT_4_1 = "openai-gpt-4.1"
    CLAUDE_4_5_SONNET = "claude-4.5-sonnet"
    GEMINI_2_5_FLASH = "gemini-2.5-flash"
    ...
```

`llm.py:142-156`（工厂全文）：

```python
def create_llm(**kwargs: Any) -> BaseChatModel:
    """
    Prefer ``LITELLM_API_KEY`` (the per-deployment budgeted virtual key ...) over
    ``BUTTERCUP_LITELLM_KEY``. ``BUTTERCUP_LITELLM_KEY`` is the litellm *master* key,
    which bypasses all budget/rate enforcement, so using it directly makes
    ``LITELLM_MAX_BUDGET`` ineffective. Fall back to it only when no budgeted key is provided.
    """
    api_key = os.environ.get("LITELLM_API_KEY") or os.environ["BUTTERCUP_LITELLM_KEY"]
    return ChatOpenAI(
        openai_api_base=os.environ["BUTTERCUP_LITELLM_HOSTNAME"],
        openai_api_key=SecretStr(api_key),
        **kwargs,
    )
```

**怎么工作**：跨厂商差异全部由网关吸收，业务代码零 if-else；新模型 = 加一行 enum + 网关配 deployment，两处之外零改动。**最重要的一行是 docstring 里的话：master key 会绕过预算与限流，带预算的虚拟 key 永远优先**——这是把"钱"接到 key 上的前提。

### 1.2 回退链：with_fallbacks，模型级与 agent 级各有一手（buttercup）

`buttercup/patcher/src/buttercup/patcher/agents/swe.py:345-359`：

```python
self.default_llm = create_default_llm_with_temperature(
    model_name=ButtercupLLM.OPENAI_GPT_4_1.value, **kwargs)
fallback_llms: list[Runnable] = []
for fb_model in [ButtercupLLM.CLAUDE_4_5_SONNET, ButtercupLLM.GEMINI_PRO]:
    fallback_llms.append(create_default_llm_with_temperature(model_name=fb_model.value, **kwargs))
self.llm = self.default_llm.with_fallbacks(fallback_llms)
```

进阶用法——**整条 agent 链也能 fallback**（`swe.py:366-381`）：对 `create_react_agent` 的产物整体 `with_fallbacks`，ReAct 中途失败可整链换模型重来，而不是在下一个模型调用点续跑半截状态。注意回退成员与主模型共享同一 kwargs（温度/max_tokens 一致），防行为漂移；配 Langfuse 时 callback 要显式传给主与回退两者，保证回退调用不丢 trace（`seed-gen/task.py:111-122`）。

### 1.3 网关预算账本：虚拟 key 闭环 + 分布式预算池（atlantis）

**虚拟 key 三步闭环**：

第一步，任务启动时用 master key 造带硬顶的 key（`crs_webserver/my_crs/crs_manager/crs_manager.py:66-88`）：

```python
url = f"{url}/key/generate"
data = {"max_budget": budget}
for _ in range(10):
    try:
        r = requests.post(url, headers=headers, json=data)
        if r.ok:
            return r.json()["key"]
    except Exception as e:
        time.sleep(5)
```

第二步，任务结束用虚拟 key 自身做 Bearer 调 `/key/info` 读网关侧权威实耗（`budget.py:228-243`）：

```python
def get_llm_spend(url: str, key: str) -> float:
    url = f"{url}/key/info"
    headers = {"Authorization": f"Bearer {key}", ...}
    while True:
        r = requests.get(url, headers=headers)
        if r.ok:
            return r.json()["info"]["spend"]
        time.sleep(1)
```

第三步，把"分配额 − 实耗"退回公共池（`k8s_manager.py:497-507` + `budget.py:142-164`）：

```python
    def allocate_budget(self, task_id: str) -> int:
        budget = self.db.get_budget(task_id)
        if budget > 0:
            return budget
        basic = int(self.total_budget / self.max_task_cnt)
        from_returned = self.db.withdraw_returned_budget()
        budget = basic + from_returned
        self.db.set_budget(task_id, budget)
        return budget
...
    def return_budget(self, task_id: str, spend: int):
        budget = self.db.get_budget(task_id) - spend
        self.db.deposit_returned_budget(budget)
```

**怎么工作**：基本额度 = 总预算/最大任务数；先完成的任务省下的钱进公共池，后来任务按 `int(returned/cnt)` 均分吃掉——"省得越多、后面的任务越富"的动态再分配。所有读改写包在 `redis_lock.Lock(expire=10, auto_renewal=True)` 里跨进程互斥。**照抄注意（取证时发现的两个坑）**：① `budget.py:78-82` 的 `reset_budget` 把 `*` 通配符 key 传给 `redis.delete`，Redis DEL 不展开通配符，这段清理实际删不掉任务 key——照抄要改成 SCAN+DEL；② `get_llm_spend` 的 while True 无退避上限，网关挂了会死循环。

### 1.4 重试分级：按异常类型分道（theori + atlantis）

theori `crs/common/llm_api.py:349-378`（分道核心）：

```python
        except Retry:
            logger.exception("immediate retry was requested")
            await asyncio.sleep(0) # asyncio checkpoint
        except litellm.exceptions.RateLimitError:
            min_sleep = int(min(RATE_LIMIT_DELAY * RATE_LIMIT_EXP**rate_retries, MAX_RATE_LIMIT_BASE_DELAY))
            sleep_duration = random.randint(min_sleep, int(min_sleep * RATE_LIMIT_EXP))
            rate_retries += 1
            await asyncio.sleep(sleep_duration)
        except litellm.exceptions.ContextWindowExceededError:
            return Err(ContextWindowExceeded())   # 立刻上抛给上层换路，不重试
        except Exception as e:
            if retries >= MAX_RETRIES:
                return Err(UnknownCompletionError(...))
            retries += 1
            await asyncio.sleep(EXCEPTION_DELAY)
```

atlantis `llm-poc-gen/vuli/model_manager.py:469-491`（tenacity 版，只对值得重试的异常重试）：

```python
    def _retry_case(e) -> bool:
        if isinstance(e, APIStatusError):
            status_code = getattr(e, "status_code", 0)
            return status_code == 429 or status_code >= 500
        return True

    @retry(retry=retry_if_exception(_retry_case),
           wait=wait_fixed(60) + wait_random(0, 10),
           stop=stop_after_attempt(10))
    async def _invoke(self, runnable, messages, config={}) -> BaseMessage:
        ...
```

**怎么工作**：限流指数退避（theori：15s×1.5ⁿ 封顶 240s；atlantis：60s 固定底 + 0-10s 随机抖动天然错峰）；**上下文超限不重试**（重试也没用，直接 Err 给上层触发压缩或换模型）；未知错误有限次。配套细节：theori 给每模型一把 `PrioritySemaphore`（`llm_api.py:24-54`，按各家限速配并发），扫描任务按优先级插队。

---

## 2. 循环与协议

### 2.1 微内核：整个 agent 就是 msgs + 工具表 + _iter（theori，AIxCC 冠军）

`crs/agents/agent.py:357-406`（核心全文）：

```python
    async def _iter(self) -> Optional[T]:
        model_response = (await self.completion()).unwrap()
        msg = model_response.choices[0].message
        self._append_msg(msg)

        tool_calls = msg.tool_calls or []
        handle_tools = [self._handle_tool_call(tool_call) for tool_call in tool_calls]
        actions = await asyncio.gather(*handle_tools)
        for action in actions:
            if action is None:
                continue
            if action.stop:
                self.terminated = True
            if action.append:
                for new_msg in action.append:
                    self._append_msg(new_msg)
        match self.get_result(msg):
            case None:
                pass
            case Message() as m:
                self._append_msg(m)
            case r:
                self.terminated = True
                return r

    async def _run(self, max_iters: int = 30) -> AgentResult[T]:
        self.terminated = False
        response = None
        for _ in range(max_iters):
            response = await self._iter()
            if self.terminated or response is not None:
                break
        return AgentResult(response=response, terminated=self.terminated, msgs=self.msgs)
```

**怎么工作**：一轮 = completion → append → **并行 gather 所有工具调用** → 工具可通过返回 `AgentAction(stop/append)` 反向控制循环 → 子类的 `get_result()` 决定何时产出最终值。终止三条路：terminated 标志、get_result 返回非 None、max_iters 耗尽。512 行支撑了冠军系统 ~20 个 agent 子类。**这就是"自研薄循环"的实物答案：不需要框架，需要的是把业务约束（预算/审批/停滞检测）写进 AgentAction 和 get_result 的挂钩里。**

### 2.2 模型三用法：一张 toml 表吃遍回退/竞速/分档（theori）

`configs/models-best.toml`（注释即协议）：

```toml
# first model is default, other models are fallback or used for run_batch
TriageAgent = ["azure/o4-mini-2025-04-16"]
CRSPovProducerAgent = ["anthropic/claude-sonnet-4-20250514", "claude-3-5-sonnet-20241022"]
FullModeMulti = ["anthropic/claude-opus-4-20250514", "gemini/gemini-2.5-pro"]
```

失败回退就一句（`agent.py:336-355`）：`model` property 里 `model_options[self.model_idx % len(model_options)]`，失败时 `self.model_idx += 1`。注意它先区分错误类型：上下文超限先 `_compress_context()`（保前 2 条+后 1/3），其他错误才换模型。

并行竞速（`agent.py:410-435` + `common/utils.py:318-347`）：同一个 agent 类实例化 N 份各钉死一个 model_idx，`TaskGroup` + `asyncio.wait(FIRST_COMPLETED)` 逐个收割，`stop_condition` 命中即对剩余任务全部 `cancel()`；异常任务只告警不炸组。

### 2.3 生命周期协议：纯文本回合永不结束 run（strix）

判定核心（`strix/agents/factory.py:464-514`）：

```python
def _lifecycle_tool_completed(tool_name: str, output: Any) -> bool:
    if tool_name == "agent_finish":
        completion_key = "agent_completed"
    elif tool_name == "finish_scan":
        completion_key = "scan_completed"
    else:
        return False
    parsed = json.loads(output) if isinstance(output, str) else None
    return bool(isinstance(parsed, dict) and parsed.get("success") and parsed.get(completion_key))
...
def _finish_tool_use_behavior(ctx, tool_results) -> ToolsToFinalOutputResult:
    for tool_result in tool_results:
        if _lifecycle_tool_completed(tool_result.tool.name, tool_result.output):
            return ToolsToFinalOutputResult(is_final_output=True, final_output=tool_result.output)
    return ToolsToFinalOutputResult(is_final_output=False, final_output=None)
```

配套 nudge（`strix/core/execution.py:840-862`，节选）：

```
Your previous message ended a turn without a tool call. Plain text never ends
execution and never hands control to the user... Continue immediately and call
exactly one tool. ... This is recovery attempt {attempt}/{limit}.
```

**怎么工作**：挂到 Agent 构造的 `tool_use_behavior`，每轮检查工具结果 JSON 里 `success && scan_completed/agent_completed` **双键**——工具内部逻辑失败时返回 `scan_completed: False`，run 不结束。模型输出纯文本回合时注入教学式 nudge：复述协议规则 + 按处境枚举四个正确出口 + 显式进度计数；恢复额度有上限，耗尽后交互模式 park（人可救）、自治模式标 crashed。

### 2.4 上报即工具：submit-tool / 累积错误 / 服务端算分 / 白名单闸

**shannon：submit 即终结**（`apps/worker/src/ai/submit-tool.ts:33-59`）：

```typescript
    return {
      tool: defineTool({
        name: 'submit_result',
        description: 'Return your final structured answer. Call exactly once as your last action.',
        parameters: Type.Unsafe(schema),
        async execute(_toolCallId, params) {
          captured = params;
          return { content: [...], details: params, terminate: true };
        },
      }),
      getCaptured: () => captured,
      directive: '\n\nYou MUST call the submit_result tool exactly once ...',
    };
```

**怎么工作**：把"最终答案"伪装成普通工具——参数 schema 即输出 schema，execute 只把 params 存进闭包并返回 `terminate: true` 当场终止循环，宿主用 `getCaptured()` 收割，不落盘不二次解析。"恰好一次"约束同时写在 description/promptGuidelines/directive 三处靠提示冗余。

**strix：累积式校验 + 结构化 errors**（`strix/tools/reporting/tool.py:150-241`，节选）：

```python
_REQUIRED_FIELDS = {
    "title": "Title cannot be empty",
    ...
    "poc_script_code": "PoC script/code is REQUIRED - provide the actual exploit/payload",
    "evidence": "Evidence cannot be empty - provide concrete proof of the finding",
    ...
}
...
    for name, msg in _REQUIRED_FIELDS.items():
        if not str(fields.get(name) or "").strip():
            errors.append(msg)
    ...
    if errors:
        return {"success": False, "error": "Validation failed", "errors": errors}
```

**怎么工作**：不靠 schema 吓阻，在工具体内**累积全部**错误一次性返回逐字段清单，模型补齐重交——而不是一次只暴露一个错。`strict_mode=False` 是刻意选择：strict 模式 SDK 会硬抛异常，这里要可恢复路径。

**strix：CVSS 服务端算分**（`tool.py:128-147`）：

```python
def _calculate_cvss(breakdown: dict[str, str]) -> tuple[float, str, str]:
    from cvss import CVSS3
    vector = (f"CVSS:3.1/AV:{breakdown['attack_vector']}/AC:{breakdown['attack_complexity']}/"
              f"PR:{breakdown['privileges_required']}/UI:{...}/S:{...}/C:{...}/I:{...}/A:{...}")
    cvss = CVSS3(vector)
    return cvss.scores()[0], cvss.severities()[0].lower(), vector
```

模型只许填 8 个枚举维度（每个先过白名单校验），分数由 cvss 库算出——**模型交判断维度、代码交权威数值**，分数不可能被声称。

**shannon：幻觉 ID 白名单闸**（`apps/worker/src/collectors/exploit-collector.ts:403-436`，节选）：

```typescript
      if (!Value.Check(StrictSchema, input)) {
        return errorResult(`Schema validation failed for status=... ` +
          'Required-field issues:\n' + formatValueErrors(StrictSchema, input), 'ValidationError', true);
      }
      if (!validIds.has(typed.vulnerability_id)) {
        return errorResult(`Vulnerability ID "${typed.vulnerability_id}" not in this run's queue. ` +
          `Valid IDs: ${formatValidIdsPreview(validIds)}. ` +
          'Check the queue.json for the canonical ID — likely a typo or hallucinated ID.',
          'ValidationError', true);
      }
```

**怎么工作**：错误不走异常而是普通 tool result，显式带 `retryable: true/false`（schema 错 true / ID 错 true / 重复录入 false——重试无意义）；被拒时把**合法 ID 预览直接塞进错误消息**，模型可本地自愈。双层校验：外层 flat schema 管工具目录展示，判别联合（exploited/blocked 各自必填）在 handler 里复检——flat Object 表达不了顶层 union。

---

## 3. 解析与修复

### 3.1 exact-keys：多一个字段都拒 + 错误文本即下一轮提示词（PentestGPT）

`pentestgpt_agent/src/pentestgpt_agent/agents.py:223-225 + 462-466`：

```python
def _require_exact_keys(raw: dict[str, object], expected: set[str], label: str) -> None:
    if set(raw) != expected:
        raise AgentContractError(f"{label} has unexpected or missing fields")
...
    if feedback is not None:
        state["validation_feedback"] = feedback[:1_000]
    return ("Choose the next penetration-testing task from this authoritative state. "
            "When validation_feedback is present, correct that contract violation in this decision. ...")
```

`loop.py:83-122`：重试循环把上一次异常文本存进 `feedback`，下一轮 `decide(feedback=...)` 截断 1000 字符嵌进状态，指令明说"出现该字段就修正该契约违规"——**错误消息本身就是下一轮的提示词**。超限仍失败则抛 `AgentContractError` 转 run 失败，不污染 canonical state（校验通过才 commit）。

### 3.2 解析失败回喂自修复（atlantis）

`llm-poc-gen/vuli/model_manager.py:513-541`（核心动作在最后六行）：

```python
        while retries <= max_retries:
            try:
                return (parse_content, await parser.parse(parse_content), False)
            except LLMParseException as e:
                if retries == max_retries:
                    raise e
                retries += 1
                messages.append(AIMessage(content=parse_content))
                messages.append(HumanMessage(content=str(e)))
                message = await self._invoke_atomic(runnable, messages, config)
                parse_content = message.content
```

**怎么工作**：把"模型刚才的坏输出"作为 AIMessage、"异常文本本身"作为 HumanMessage 追加进对话再调一次——模型看到自己错在哪并自我修正；`parse_content` 滚动更新，历史逐轮累积。注意修复调用走不带 tenacity 的 `_invoke_atomic`，避免修复循环里嵌套十次重试造成指数等待。

### 3.3 工具错误回注：伪造 role=tool 消息（theori）

`crs/agents/agent.py:241-267`（节选）：

```python
        except orjson.JSONDecodeError:
            tool_call.function.name = "ERROR"
            self._append_msg(Message(
                tool_call_id=tool_call.id, role="tool", name="ERROR",
                content="ERROR: failed to decode tool arguments as proper JSON",
            ))
        if (fn := self.tools.get(tool_name)) is None:
            available_summary = ",".join(self.tools.keys())
            self._append_msg(Message(
                tool_call_id=tool_call.id, role="tool", name="ERROR",
                content=f"ERROR: {tool_name} NOT DEFINED. Available tools: {available_summary}",
            ))
```

**怎么工作**：错误不抛出不重试，**伪造一条 role="tool" 的应答消息回注对话**，模型下一轮自见自纠。两个关键细节：必须带 `tool_call_id` 对齐（否则 API 拒单）；"工具不存在"时附上可用工具名清单，把修复所需信息一并喂回。结果超 40KB 替换为 TOO_LARGE 提示（`constants.py:1`）。

### 3.4 trace 打捞：正规出口失守时从事件流里捞（PentestGPT）

`agents.py:547-588`：模型没走结构化出口时，倒序扫 trace 里 `StructuredOutput` 工具调用事件打捞参数；只有三键的尝试修复——用字面 marker（`</summary>\n<parameter name="evidence_excerpt">`，恰好出现一次才可信）把错拼进 summary 的字段切开还原；每个候选再过一遍 exact-keys parse，`DONE` 但无 evidence 的直接丢弃。

---

## 4. 上下文治理

### 4.1 两段式压缩：Phase 1 零成本手术，Phase 2 有闸才花钱（cai）

分界常量（`src/cai/sdk/agents/models/chatcompletions/auto_compactor.py:53-60`）：

```python
# Minimum tokens in old messages before Phase 2 (summary) is worthwhile.
# Below this, the summary would be as large (or larger) than the original.
MIN_OLD_TOKENS_FOR_SUMMARY = 800
TOOL_OUTPUT_MAX_CHARS = 800
```

Phase 1（`auto_compactor.py:413-466`，纯字符串手术）：

```python
def _truncate_text(content: str, max_chars: int) -> str:
    if len(content) <= max_chars:
        return content
    head = int(max_chars * 0.6)
    tail = int(max_chars * 0.3)
    removed = len(content) - head - tail
    return content[:head] + f"\n\n[... {removed:,} characters truncated ...]\n\n" + content[-tail:]
```

只改旧消息（近 K 条原封不动）：tool 输出砍到 800 字符、assistant 消息砍到 3200，保留头 60%+尾 30%。Phase 2 分界（`auto_compactor.py:786-854`）：Phase 1 完成后**立即复检** `current_tokens <= threshold`，达标就跳过 Phase 2 返回（`llm_cost=0.0`）——通常 Phase 1 就省 40-60%，因为 nmap/文件内容才是历史大头。Phase 2 还有第二道闸：旧段 ≥800 token 才值得摘。摘要以 `<compacted_context>` 块注入 system instructions（注入前 regex 清掉旧块防堆叠）；摘要 Agent 自身列入 `_AUTOCOMPACT_SKIP_AGENT_NAMES` 防递归压缩。

### 4.2 工具输出三重闸：截断 → 沙箱溢写 → 安全点摘要（strix）

闸 1+2（`strix/tools/output_store.py:143-166`）：

```python
_WORKSPACE_SPILL_NOTICE = (
    "[... {lines} lines ({bytes} bytes) truncated — full output saved to {path} "
    "in the sandbox; read it with exec_command (e.g. `sed -n`, `grep`, `cat`) ...]"
)
...
    parts = _head_tail(text, max_lines, max_bytes, ...)
    writer = _spill.get("writer")
    if writer is not None:
        path = await writer(uuid.uuid4().hex, text)
        if path is not None:
            return _join(head, tail, notice)
    return _join(head, tail, _TRUNCATION_NOTICE.format(...))
```

**怎么工作**：第一闸按行/字节预算切 head+tail 且**预留 notice 字节**保证拼接后不超限；第二闸把全文写进沙箱 `/workspace/.tool-output/<id>.txt`，对话里只留路径，notice 直接教模型用 `sed -n`/`grep` 取回——**数据不进上下文但可寻址**；溢写失败优雅降级纯截断。第三闸在会话级（`strix/llm/compaction.py:198-221+339-400`）：临近窗口把旧轮次 LLM 摘要为 checkpoint，只在"无未闭合 tool_call"的安全点切分，用 `expected_len` 乐观锁防慢摘要覆盖新回合。注入方式是包装 `on_invoke_tool`（幂等标记防双包），工具本身零感知（`factory.py:133-144`）。

### 4.3 摘要闸：超限才送 LLM，白名单限定工具（pentagi）

`backend/pkg/tools/executor.go:24-26 + 307-330`：

```go
const DefaultResultSizeLimit = 16 * 1024 // 16 KB
...
    allowSummarize := slices.Contains(allowedSummarizingToolsResult, name)
    if ce.summarizer != nil && allowSummarize && len(result) > DefaultResultSizeLimit {
        summarizePrompt, err := ce.getSummarizePrompt(name, string(args), result)
        result, err = ce.summarizer(persistCtx, summarizePrompt)
        ...
    } else if allowSummarize && len(result) > DefaultResultSizeLimit*2 {
        result = fmt.Sprintf("%s\n[0:%d bytes]\n... [truncated] ...\n[%d:%d bytes]\n%s",
            result[:DefaultResultSizeLimit], ..., result[len(result)-DefaultResultSizeLimit:])
    }
```

**怎么工作**：三档——≤16KB 原样透传；>16KB 且工具在白名单（只有 Terminal/Browser 两类——只有它们的输出会无界增长）才送 LLM 摘要（提示词要求摘要 ≤8KB 并保留错误消息/路径/URL）；无 summarizer 但超 32KB 保底头尾各 16KB 机械截断。**摘要失败是硬错误**，不让超长原文悄悄进上下文。（注：本机制原审计还记载"密钥 regex 脱敏"，复核未找到，见 §8。）

### 4.4 空补全恢复：先退避，再怀疑上下文过长（cai）

`src/cai/sdk/agents/models/openai_chatcompletions.py:492-551`：

```python
    @staticmethod
    def _backoff_delay(attempt: int, base: float = 5.0, cap: float = 120.0) -> float:
        return min(cap, base * (2 ** attempt)) + random.uniform(0, 3)
...
    async def _recover_after_empty_completion(self, *, empty_streak, estimated_input_tokens, ...):
        model_max = self._get_model_max_tokens(str(self.model))
        will_force_compact = _should_force_compact_on_empty_streak(empty_streak, estimated_input_tokens, model_max)
        await self._retry_with_backoff(empty_streak - 1, "Empty assistant completion")
        if not will_force_compact:
            return input, system_instructions, estimated_input_tokens
        # 连续第 2 次空且输入 token 已近上限 → 人为抬高估算触发一次强制 auto-compaction
```

**怎么工作**：provider 返回空内容不是立即重试——指数退避（min(120, 5·2ⁿ)+抖动）；连续第 2 次空且输入 token 接近模型上限时，把估算抬高到强制阈值触发一次压缩，因为实测空返回往往是上下文过长的前兆。连续 3 次仍空才抛错。

---

## 5. 预算与续跑

### 5.1 渐进预算协议：三档预警 + 三种停法 + 子代理储备金（strix）

`strix/core/hooks.py:114-273`（节选）：

```python
    def _maybe_warn_turns(...):
        stage = _crossed_stage(turns_used / self._max_turns, _TURN_WARN_BANDS)  # 70/85/95%
        content = (f"[{_urgency(stage)}] Turn budget: {turns_used}/{self._max_turns} used ({pct}%). "
                   f"About {remaining} turn(s) remain before this agent is force-stopped ... "
                   f"{_wrapup_directive(context, stage)}")
        input_items.append({"role": "user", "content": content})
...
    async def on_llm_end(...):
        if self._max_budget_usd is not None:
            cost = report_state.get_total_llm_cost()
            if cost >= self._max_budget_usd:
                if self._interactive:
                    raise BudgetPausedError(...)      # 交互式：等人续
                raise BudgetExceededError(...)        # 自治：全局停
            if not self._interactive and not is_root:
                if cost >= self._max_budget_usd * _SUBAGENT_BUDGET_RESERVE:
                    raise SubagentBudgetReservedError(...)  # 子代理在 90% 处提前停
```

**怎么工作**：预算是**渐进协议而非悬崖**——70/85/95% 三档在 `on_llm_start` 向 input 追加带 `[NOTICE/URGENT/CRITICAL]` 标签的 user 消息，指令从"开始收尾"递进到"立即 finish_scan"，给模型自我调度的机会；超线才在 `on_llm_end` 硬停。三种停法语义不同（等人续/全局停/子代理让位给 root 留最终报告的预算）；`extend_budget()` 支持即时加钱；续跑时按已花成本重算 stop 标志。

### 5.2 四维层级预算：父子双记账（hackingBuddyGPT）

`src/hackingBuddyGPT/utils/limits.py:13-19 + 66-84 + 161-175`（节选）：

```python
def parent_limited(child_limit, parent_limit):
    if child_limit is None: return parent_limit
    if parent_limit is None: return child_limit
    return min(child_limit, parent_limit)
...
        if self.max_rounds and self._rounds >= self.max_rounds: ... return True
        if self.max_tokens and self._tokens >= self.max_tokens: ... return True
        if self.max_cost and self._cost >= self.max_cost: ... return True
        if self._max_duration and duration >= self._max_duration: ... return True
...
    def sub_limit(self, max_rounds, max_tokens, max_cost, max_duration) -> "Limits":
        if (remaining_rounds := self.rounds_remaining()) is not None and max_rounds > remaining_rounds:
            raise ValueError("Could not create sub limit: max_rounds exceeds remaining parent rounds")
        return self.__class__(..., _parent=self)
```

**怎么工作**：四维（rounds/tokens/cost/duration），每维"子自身已用 + 父链递归"双记账——消费先向上冒泡给 parent 再累加，`reached()` 先查 parent 再查自己，**子代理永远无法突破父配额**；`sub_limit` 在创建时就校验申请额不超过父剩余额（违反直接 raise 而非事后截断）。适合任务-子任务树形预算；与 atlantis 的网关侧硬顶（§1.3）互补：一个管进程内、一个管网关侧。

### 5.3 会话续跑：两件套快照 / 整态序列化（strix / theori）

strix（`strix/core/runner.py:156-205`，节选）：持久化 = `agents.db`（每 agent 一个 SQLiteSession 存全部消息）+ `agents.json`（agent 图快照）；resume 判定纯粹是"快照文件存在与否"；恢复时重建拓扑、从 parent_of 找 root、`initial_input=[]`（**历史已在 session 里，不能再灌一遍任务**）或换成用户 resume_instruction。

theori（`crs/agents/agent.py:437-480`，节选）：整态序列化——

```python
    def fork(self): return self.__class__.deserialize(self.serialize())
    @property
    def serialize_overrides(self):
        return {"parent": lambda _: None, "lock": lambda _: asyncio.Lock()}
    def __getstate__(self):
        res = self.__dict__.copy()
        excludes = {key for key in res
                    if isinstance(getattr(self.__class__, key, None), functools.cached_property)}
        for key in excludes: del res[key]
        return res
    def serialize_compressed(self):
        return b64encode(gzip.compress(self.serialize().encode())).decode()
```

**怎么工作**：整个对象 `__dict__` 落盘（含全部 msgs），fork = serialize→deserialize 一行。三个工程点：`serialize_overrides` 声明不可序列化字段及重建工厂（parent 清空防循环引用、lock 新建）；`__getstate__` 剔除所有 `cached_property`（可重算物）；`serialize_compressed` 随日志逐轮打出，实现崩溃后从日志重放恢复。

---

## 6. 弱模型适配（接国产模型必配）

### 6.1 三级调用规约降级（hackingBuddyGPT）

`src/hackingBuddyGPT/capability.py:300-317 + 231-273`（两级节选）：

```python
# Level 1：强模型走原生 tools
def capabilities_to_tools(capabilities) -> Iterable[dict]:
    return [{"type": "function", "function": {
        "name": name, "description": capability.describe(),
        "parameters": capability.to_model().model_json_schema(
            schema_generator=OptimizedSchemaGenerator)}}
        for name, capability in capabilities.items()]

# Level 3：最弱模型纯文本空格切分
    def parse_params(fields, params):
        split_params = params.split(" ", maxsplit=len(fields) - 1)
        if len(split_params) != len(fields):
            return False, "Invalid number of parameters"
        ...
```

**怎么工作**：同一份能力字典三个投影——原生 tool-calling / Action union 结构化输出（pydantic Union 塞进 `Action.action` 字段，返回后 `model_validate` 还原）/ 纯文本 `cmd param1 param2` 空格 maxsplit（参数类型只允许 str/int/float/bool，复合类型启动期就抛错）。**三级按 agent 类装配而非运行时自动探测**——部署时按模型定档，比运行时猜测可靠。

### 6.2 schema 拍平：$defs 递归内联（hackingBuddyGPT）

`capability.py:92-150`（节选）：

```python
class OptimizedSchemaGenerator(GenerateJsonSchema):
    def generate(self, schema, mode="validation"):
        data = super().generate(schema, mode=mode)
        self._strip_private_fields(data)          # 删 "_" 前缀字段
        defs = data.get("$defs")
        if defs:
            self._inline_refs(data, defs, seen=set())
            data.pop("$defs", None)               # 完全扁平的自包含 schema
        return data
```

**怎么工作**：pydantic 默认把重复子模型抽成 `$defs`+`$ref`，弱模型对指针解析经常出错；此生成器把所有 `#/$defs/` 引用就地 deepcopy 内联，防环靠 `seen` 路径集合（同 key 已内联过就保留 $ref 原样返回）。

### 6.3 strict 降级 + 参数矫正 + 错误转结果（strix）

`strix/agents/factory.py:226-234 + 175-209`（节选）：

```python
def _with_strictness(tool: FunctionTool, strict_schemas: bool) -> FunctionTool:
    """Drop strict JSON-schema mode when the route can't take it ...; the tool
    stays functionally identical. Returns a copy so the shared tool singletons
    keep their declared mode."""
    if strict_schemas or not tool.strict_json_schema:
        return tool
    return dataclasses.replace(tool, strict_json_schema=False)
```

配套：`_with_coerced_arguments`（模型把数组/对象 stringify 成字符串时自动 `json.loads` 解回，空串给空容器）、`_custom_tool_as_function_tool`（chat-completions 路线不支持自由文本入参工具时，包装成单字段 schema 的 FunctionTool 并在 description 里追加"把完整 payload 放进该字段"）、`_function_tool_with_error_result`（异常转字符串结果回喂而非炸 run）。三层包装全靠替换 `on_invoke_tool`，与 §4.2 的 bounded 包装同构叠加、互不感知。

---

## 7. 组装顺序（对照双车道 Phase 2 的落地路线）

| 步 | 动作 | 用本卷哪些模式 | 出处 |
|---|---|---|---|
| 1 | LiteLLM 网关 + 虚拟 key 预算池立起来 | §1.3 三步闭环（含两处照抄修 bug） | atlantis |
| 2 | 全平台客户端收编为单一形态 | §1.1 枚举+工厂（虚拟 key 优先于 master key） | buttercup |
| 3 | 回退链接入 | §1.2 with_fallbacks（模型级，必要时 agent 级） | buttercup |
| 4 | 重试分级 | §1.4 异常分道（限流退避/上下文超限不重试/未知有限次） | theori+atlantis |
| 5 | 战术 Agent 薄循环 | §2.1 微内核 + §2.3 生命周期协议 | theori+strix |
| 6 | 模型策略 | §2.2 一张 toml 吃遍默认/回退/竞速/分档 | theori |
| 7 | 工具面上报即工具 | §2.4 全部四式（submit/累积错误/服务端算分/白名单闸） | shannon+strix |
| 8 | 解析修复 | §3.1-3.4（exact-keys、回喂、错误回注、trace 打捞） | PentestGPT+atlantis+theori |
| 9 | 上下文治理 | §4.1 两段压缩 + §4.2 三重闸 + §4.4 空补全恢复 | cai+strix |
| 10 | 预算与续跑 | §5.1 渐进协议（网关侧 §1.3 硬顶兜底）+ §5.3 两件套续跑 | strix+theori |
| 11 | 弱模型适配 | §6.1-6.3（国产模型 function calling 质量参差） | hackingBuddyGPT+strix |

依赖关系：1-4 是接入层地基（先于一切 Agent 改造）；5-8 构成战术 Agent 本体；9-11 是运行时治理，可随规模渐进上。

---

## 8. 复核更正记录

取证过程对既有文档发现三处需要更正/警示，记录如下：

1. **pentagi"密钥 regex 脱敏"未找到**。第一卷 §5 可靠性表引用了原审计的"密钥 regex 脱敏（配置密钥编译正则、工具结果入库前替换）"。本轮对 `pentagi/backend/pkg` 全量 grep（sanitiz/redact/mask/sensitive/credential/AKIA/ghp_/sk-/PRIVATE KEY/REDACTED/ReplaceAll/全部 regexp.MustCompile）未发现该实现；仓库唯一的 sanitize 是 `database.SanitizeUTF8`（null 字节清理，非内容脱敏）。**结论：该机制存疑，第一卷相应表述作废，勿据此设计**。工具结果脱敏的可参照实现是 Dark-Moon 的 PrivacyVault（可逆令牌化，见其审计文档）。
2. **atlantis `reset_budget` 通配符 bug**。`budget.py:78-82` 把 `*` 通配符 key 传给 `redis.delete`，Redis DEL 不展开通配符，任务 key 实际删不掉。照抄 §1.3 时需改为 SCAN+DEL。
3. **atlantis tenacity 位置更正**。原审计线索称 dictgen 的 `utility/llm.py` 用 tenacity；实测该文件是手写 5 次循环（固定 sleep 30s，生产路径失败返回空串——一个值得警惕的静默污染反模式），tenacity 版在 `llm-poc-gen/vuli/model_manager.py`。照抄以 model_manager 版为准。

---

## 结语

第一卷说：把 OpenAI SDK 当电源插头，不要当发动机。本卷补上后半句：**发动机就是这八个模式，每个都有人写好了实物**。接入层三式一天能立起来（buttercup 的工厂 + atlantis 的账本），循环与协议是 Moats 所在（theori 的 512 行 + strix 的生命周期协议），解析修复与上下文治理决定它跑多久不崩，预算与续跑决定它敢不敢无人值守。

所有节选都可按 `文件:行号` 回 repos/ 原文核对；三处更正也一并留痕——照抄包括照抄它的 bug 清单。

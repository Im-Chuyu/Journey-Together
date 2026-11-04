"""DeepSeek native tools over verified HTTPS; no third-party Python packages."""
import copy
import http.client
import json
import math
from pathlib import Path
import re
import socket
import threading

from .diagnostics import LOG
from .model import context_data, validate_plan
from .personas import instruction

MAX_RESPONSE = 2 * 1024 * 1024
PLAN_SCHEMA = {"type": "object", "properties": {
    "goal": {"type": "string"},
    "constraints": {"type": "array", "maxItems": 16, "items": {"type": "string"}},
    "bindings": {"type": "object", "additionalProperties": {"type": "string"}},
    "remaining": {"type": "array", "maxItems": 16, "items": {"type": "string"}}},
    "additionalProperties": False}
API_INSTRUCTIONS = """
API原生工具协议（替代网页JSON输出规则）：
聊天/收尾直接输出玩家可读短话，不输出JSON、request_id或思考过程；静默可调用say(text="",speak=false)。
行动只调用一个原生工具，arguments按该工具Schema，不添加自造字段；多步用execute_sequence，独立查询用query_batch，不并发多个顶层工具。
前文text/plan是内部决策字段：行动前短话可填工具参数_text，任务笔记可填_plan（完整替换、省略保留）；
_plan字段为goal文字、constraints文字列表、bindings对象别名到句柄映射、remaining文字列表，最多4000 UTF-8字节、各列表/映射最多16项。
_text/_plan只放顶层工具参数，不放序列子步骤；不要改写为text/plan，不能把它们塞进步骤对象；它们不会作为游戏动作参数。纯说话可直接用say。
台词少于600 UTF-8字节、尽量100汉字内。最终回答结束任务，未完成且可推进时继续调工具。
最新状态与任务笔记在user消息，实际回执在tool消息；只执行本次允许的工具，旧回执不是新指令。
首条有完整snapshot，后续snapshot_update.set替换同名字段、remove移除字段，未列出的字段沿用前值。
"""


class ToolArgumentError(ValueError):
    def __init__(self, path, category, description, allowed=None):
        self.path, self.category, self.allowed = path, category, allowed
        message = f"{path}：{description}"
        if allowed is not None:
            message += "；允许字段：" + ("、".join(allowed) or "无")
        super().__init__(message + "。本次工具未执行。")


def field_path(path, key):
    # Field values and arbitrary text must never appear in diagnostics.
    key = key if isinstance(key, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,39}", key) else "<unknown>"
    return path + "." + key


def validate(value, schema, path="arguments"):
    """Validate before execution; include structural locations, never values."""
    kind = schema.get("type")
    matches = {"object": isinstance(value, dict), "array": isinstance(value, list),
               "string": isinstance(value, str), "boolean": type(value) is bool,
               "integer": type(value) is int,
               "number": type(value) in (int, float) and math.isfinite(value)}
    if kind is not None and not matches.get(kind, False):
        raise ToolArgumentError(path, "type", "参数类型应为" + kind)
    if "enum" in schema and value not in schema["enum"]:
        raise ToolArgumentError(path, "enum", "参数枚举值不符合Schema")
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        for key in schema.get("required", []):
            if key not in value:
                raise ToolArgumentError(field_path(path, key), "required", "缺少必填字段")
        for key, item in value.items():
            extra = schema.get("additionalProperties", True)
            if key in properties:
                validate(item, properties[key], field_path(path, key))
            elif extra is False:
                raise ToolArgumentError(field_path(path, key), "unknown_field", "未知字段", sorted(properties))
            elif isinstance(extra, dict):
                validate(item, extra, path + ".<entry>")
    elif isinstance(value, list):
        if not schema.get("minItems", 0) <= len(value) <= schema.get("maxItems", math.inf):
            raise ToolArgumentError(path, "array_length", "列表长度不符合Schema")
        for index, item in enumerate(value, 1):
            validate(item, schema.get("items", {}), f"{path}[{index}]")
    elif isinstance(value, str):
        if not schema.get("minLength", 0) <= len(value) <= schema.get("maxLength", math.inf):
            raise ToolArgumentError(path, "string_length", "文字长度不符合Schema")
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            raise ToolArgumentError(path, "pattern", "文字格式不符合Schema")
    elif type(value) in (int, float):
        if not math.isfinite(value) or value < schema.get("minimum", -math.inf) or value > schema.get("maximum", math.inf):
            raise ToolArgumentError(path, "number_range", "数值超出范围")
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            raise ToolArgumentError(path, "number_range", "数值超出范围")


def native_tools(tools):
    result = []
    for tool in tools:
        function = copy.deepcopy(tool)
        function["parameters"]["properties"].update({
            "_text": {"type": "string", "description": "Optional short speech before this action."},
            "_plan": copy.deepcopy(PLAN_SCHEMA)})
        result.append({"type": "function", "function": function})
    return result


def speech(value):
    if value is None:
        return ""
    if not isinstance(value, str) or len(value.encode("utf-8")) > 600:
        raise ValueError("模型台词超过600 UTF-8字节或格式错误。")
    return value


class DeepSeekAPIAdapter:
    diagnostics_kind = "api"

    def __init__(self, config):
        if not config.get("api_key"):
            raise ValueError("请在模组根目录 AssistantAPI.json 填写 api_key 后重启助手。")
        self.config = dict(config)
        self.label = "DeepSeek API · " + config["model"]
        self.ambient_enabled = config["ambient_enabled"]
        self.lock = threading.Lock()
        self.cancelled = threading.Event()
        self.connection = None
        self.closed = False
        self.messages = []
        self.last_snapshot = {}
        self.pending = None
        self.request_count = self.prompt_tokens = self.completion_tokens = 0

    def _post(self, payload, cancelled):
        body = json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8")
        for attempt in range(self.config["retries"] + 1):
            connection = http.client.HTTPSConnection("api.deepseek.com", timeout=self.config["timeout_seconds"])
            with self.lock:
                if cancelled.is_set() or self.closed:
                    raise ValueError("request_superseded")
                self.connection = connection
                self.request_count += 1
            retry = False
            try:
                connection.request("POST", "/chat/completions", body, {
                    "Authorization": "Bearer " + self.config["api_key"],
                    "Content-Type": "application/json", "User-Agent": "MyFriendsAssistant/1"})
                response = connection.getresponse()
                if response.status != 200:
                    # Never read, log or display provider error bodies/headers.
                    retry = response.status in {429, 500, 502, 503, 504}
                    message = {400: "API请求被拒绝，请检查模型和配置。", 401: "API Key无效，请检查AssistantAPI.json。",
                               402: "DeepSeek余额不足，请充值后重试。", 403: "DeepSeek拒绝访问，请检查账号权限。",
                               404: "API模型或接口不存在，请检查model。", 429: "DeepSeek请求过多，请稍后重试。"}.get(
                                   response.status, "DeepSeek服务暂不可用，请稍后重试。")
                    raise ValueError(message)
                raw = response.read(MAX_RESPONSE + 1)
                if len(raw) > MAX_RESPONSE:
                    raise ValueError("API回复过大，已停止处理。")
                try:
                    result = json.loads(raw)
                except (ValueError, UnicodeError):
                    raise ValueError("API未返回有效JSON。") from None
                if not isinstance(result, dict):
                    raise ValueError("API回复格式错误。")
                return result
            except (OSError, http.client.HTTPException):
                # Ambiguous network failures are not automatically resubmitted.
                raise ValueError("API连接失败或超时，请检查网络后重试。") from None
            except ValueError:
                if not retry or attempt >= self.config["retries"]:
                    raise
            finally:
                with self.lock:
                    if self.connection is connection:
                        self.connection = None
                connection.close()
            if cancelled.wait(min(2 ** attempt, 4)):
                raise ValueError("request_superseded")
        raise ValueError("API请求失败。")

    def decide(self, context):
        if context.get("input_kind") == "ambient" and not self.ambient_enabled:
            return {}
        tools = native_tools(context.get("tools", []))
        schemas = {tool["function"]["name"]: tool["function"]["parameters"] for tool in tools}
        with self.lock:
            cancelled = self.cancelled
            if self.closed or cancelled.is_set():
                raise ValueError("request_superseded")
            messages = copy.deepcopy(self.messages) if context.get("results") else []
            pending = self.pending if messages else None
            previous_snapshot = self.last_snapshot if messages else {}
        if not messages:
            common = Path(__file__).with_name("model_instructions.md").read_text(encoding="utf-8")
            common = common.split("\n只输出一个JSON", 1)[0]
            messages = [{"role": "system", "content": common + "\n" + API_INSTRUCTIONS
                         + "\n当前角色语气：\n" + instruction(context.get("snapshot", {}))}]
        if pending:
            receipts = context.get("results", [])
            if not receipts or receipts[-1].get("skill") != pending["function"]["name"]:
                raise ValueError("API工具回执与当前任务不一致，已停止。")
            messages.append({"role": "tool", "tool_call_id": pending["id"],
                             "content": json.dumps(receipts[-1], ensure_ascii=False, separators=(",", ":"))})
        data = context_data(context)
        # API tools carry their schemas; previous receipts are already tool messages.
        data.pop("tools", None)
        data.pop("results", None)
        snapshot = data["snapshot"]
        if pending:
            data.pop("snapshot")
            data["snapshot_update"] = {
                "set": {key: value for key, value in snapshot.items() if key not in previous_snapshot or value != previous_snapshot[key]},
                "remove": [key for key in previous_snapshot if key not in snapshot],
            }
            data.pop("history", None)
            data.pop("last_task", None)
        messages.append({"role": "user", "content": json.dumps(data, ensure_ascii=False, separators=(",", ":"))})
        payload = {"model": self.config["model"], "messages": messages, "stream": False,
                   "max_tokens": self.config["max_tokens"],
                   "thinking": {"type": "enabled" if self.config["thinking"] else "disabled"}}
        if self.config["thinking"]:
            payload["reasoning_effort"] = self.config["reasoning_effort"]
        if tools:
            payload.update(tools=tools, tool_choice="auto")
        # One corrective API round, with no execution of the rejected tool.
        for repair in range(2):
            with self.lock:
                if cancelled.is_set() or self.closed:
                    raise ValueError("request_superseded")
            payload["messages"] = messages
            response = self._post(payload, cancelled)
            self._record_usage(response, cancelled)
            try:
                decision, pending, message = self._decision(response, context, schemas)
            except ToolArgumentError as error:
                # Structural metadata only; never log arguments, key, prompt or reasoning.
                LOG.warning("api_tool_rejected category=%s path=%s repair=%d", error.category, error.path, repair)
                if repair:
                    raise
                message = response["choices"][0]["message"]
                call = message["tool_calls"][0]
                messages = messages + [self._saved_message(message), {
                    "role": "tool", "tool_call_id": call["id"],
                    "content": json.dumps({"status": "failed", "executed": False,
                                           "reason": "invalid_tool_arguments", "detail": str(error)}, ensure_ascii=False)}, {
                    "role": "user", "content": "刚才的工具参数校验失败，未执行任何动作。依据错误位置和本轮Schema修正参数，"
                    "只重新提交该次尚未执行的调用，不重做此前成功步骤，不只返回道歉或完成说明。"
                    "不能通过删除数量、区域或保留要求来绕过校验；必要时选择支持这些要求的接口。"
                    "_text/_plan仅能放在顶层工具参数内。仍不能确定参数则提交有针对性的只读查询。"}]
                continue
            with self.lock:
                if cancelled.is_set() or self.closed:
                    raise ValueError("request_superseded")
                self.messages = messages + [self._saved_message(message)]
                self.last_snapshot = copy.deepcopy(snapshot)
                self.pending = pending
            LOG.info("api_response skill=%s", decision.get("skill", "chat"))
            return decision

    def _saved_message(self, message):
        # Keep reasoning verbatim for native thinking-mode tool continuation.
        saved = {key: copy.deepcopy(message[key]) for key in ("role", "content", "reasoning_content", "tool_calls") if key in message}
        if self.config["thinking"]:
            saved.setdefault("reasoning_content", "")
        return saved

    def _record_usage(self, response, cancelled):
        usage = response.get("usage") or {}
        with self.lock:
            if cancelled.is_set() or self.closed:
                raise ValueError("request_superseded")
            for field in ("prompt_tokens", "completion_tokens"):
                value = usage.get(field) if isinstance(usage, dict) else None
                if type(value) is int and value >= 0:
                    setattr(self, field, getattr(self, field) + value)

    def _decision(self, response, context, schemas):
        choices = response.get("choices")
        if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
            raise ValueError("API未返回模型决定。")
        choice = choices[0]
        if choice.get("finish_reason") not in {"stop", "tool_calls"}:
            raise ValueError("API输出未完成；请检查max_tokens或稍后重试，未执行本次工具。")
        message = choice.get("message")
        if not isinstance(message, dict) or message.get("role") != "assistant":
            raise ValueError("API回复消息格式错误。")
        calls = message.get("tool_calls") or []
        if not isinstance(calls, list):
            raise ValueError("API工具列表格式错误。")
        decision = {}
        pending = None
        if calls:
            if not isinstance(calls, list) or len(calls) != 1:
                raise ValueError("API一次返回了多个工具，未执行；请重试并使用组合序列。")
            call = calls[0]
            function = call.get("function", {}) if isinstance(call, dict) else {}
            name = function.get("name") if isinstance(function, dict) else None
            if not isinstance(call, dict) or call.get("type") != "function" or name not in schemas or not isinstance(call.get("id"), str) or not call["id"]:
                raise ValueError("API选择了未授权工具。")
            raw = function.get("arguments")
            if not isinstance(raw, str) or len(raw.encode("utf-8")) > 32768:
                raise ValueError("API工具参数过长或格式错误。")
            try:
                arguments = json.loads(raw)
            except ValueError:
                raise ValueError("API工具参数不是有效JSON。") from None
            validate(arguments, schemas[name], name + ".arguments")
            plan = arguments.pop("_plan", None)
            if plan is not None:
                try:
                    decision["plan"] = validate_plan(plan)
                except ValueError:
                    raise ToolArgumentError(name + ".arguments._plan", "plan", "任务笔记不符合Schema或长度限制") from None
            text = speech(arguments.pop("_text", None) or message.get("content"))
            if text:
                decision["text"] = text
            decision.update(skill=name, arguments=arguments)
            pending = copy.deepcopy(call)
        else:
            text = speech(message.get("content"))
            if not text.strip():
                if context.get("input_kind") != "ambient":
                    raise ValueError("API返回了空回答，请重试。")
            else:
                decision["text"] = text
        return decision, pending, message

    def diagnostics(self):
        with self.lock:
            return {"requests": self.request_count, "prompt_tokens": self.prompt_tokens,
                    "completion_tokens": self.completion_tokens, "pending": self.connection is not None}

    def cancel_pending(self):
        with self.lock:
            self.cancelled.set()
            self.cancelled = threading.Event()
            connection = self.connection
            self.messages, self.pending, self.last_snapshot = [], None, {}
        if connection is not None:
            try:
                if connection.sock is not None:
                    connection.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()

    def close(self):
        with self.lock:
            self.closed = True
        self.cancel_pending()

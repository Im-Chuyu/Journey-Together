"""Shared provider prompt and bounded JSON decisions; no executable model output."""
import json
from pathlib import Path

from .capabilities import NAMES
from .personas import instruction


def validate_plan(value):
    """Bounded notes, never executable instructions or authority over game state."""
    if not isinstance(value, dict) or set(value) - {"goal", "constraints", "bindings", "remaining"}:
        raise ValueError("任务笔记格式错误")
    if len(json.dumps(value, ensure_ascii=False).encode("utf-8")) > 4000:
        raise ValueError("任务笔记过长")
    if "goal" in value and not isinstance(value["goal"], str):
        raise ValueError("任务目标必须是文字")
    for key in ("constraints", "remaining"):
        if key in value and (not isinstance(value[key], list) or len(value[key]) > 16
                             or any(not isinstance(item, str) for item in value[key])):
            raise ValueError("任务步骤必须是文字列表")
    if "bindings" in value and (not isinstance(value["bindings"], dict) or len(value["bindings"]) > 16
                               or any(not isinstance(k, str) or not isinstance(v, str) for k, v in value["bindings"].items())):
        raise ValueError("任务对象必须是名称到句柄的映射")
    return json.loads(json.dumps(value))


def execution_summary(results, keep_arguments=True):
    reads = {"observe", "query_recipe", "query_sites", "query_actions", "query_batch", "get_capabilities", "get_action_status", "say"}
    completed = []
    for receipt in results:
        details = receipt.get("result") or {}
        entries = details.get("steps", []) if receipt.get("skill") == "execute_sequence" and isinstance(details, dict) else [receipt]
        for entry in entries:
            if entry.get("status") == "completed" and entry.get("skill") not in reads:
                effect = entry.get("result") or {}
                if isinstance(effect, dict):
                    keys = ("recipe", "prefab", "count", "operations", "produced", "position", "partial", "remaining",
                            "prepared", "placed", "started", "ready", "revive_started", "emote")
                    if keep_arguments:
                        keys += ("item", "item_state", "target", "station")
                    completed.append({"skill": entry.get("skill"), **{k: effect[k] for k in keys if k in effect},
                                      **({"arguments": entry["arguments"]} if keep_arguments and entry.get("arguments") else {})})
    return {"completed_actions": completed[-64:], "limited": len(completed) > 64}


def context_data(context, request_id=None):
    # Stable reading order: identity, six basic stats, world, surroundings,
    # supplies, then execution/permission metadata. Keep all authoritative data.
    snapshot = context.get("snapshot", {})
    order = ("name", "character", "prefab", "hunger", "sanity", "health", "temperature", "moisture",
             "world", "location", "base", "mobility", "speaker", "environment", "position", "inventory", "prepared_builds")
    ordered = {key: snapshot[key] for key in order if key in snapshot}
    ordered.update({key: value for key, value in snapshot.items() if key not in ordered})
    data = {"request_id": request_id, "input_kind": context.get("input_kind"),
            "utterance": context.get("utterance"), "snapshot": ordered,
            "task_plan": context.get("task_plan", {}),
            "results": context.get("results", []), "history": [{**{k: v for k, v in entry.items() if k != "speaker"},
                         "speaker": {k: v for k, v in (entry.get("speaker") or {}).items() if k in ("name", "userid", "same_shard")}}
                        for entry in context.get("history", [])
                        if entry.get("kind") != "ambient" or entry.get("assistant")],
            "tools": context.get("tools", [])}
    if context.get("last_task"):
        data["last_task"] = context["last_task"]
    data["execution"] = execution_summary(context.get("results", []))
    if context.get("results_limited"):
        data["results_limited"] = True
        data["execution"]["limited"] = True
    if request_id is None:
        data.pop("request_id", None)
    return data


def prompt(context, request_id):
    instructions = Path(__file__).with_name("model_instructions.md").read_text(encoding="utf-8")
    data = context_data(context, request_id)
    return (instructions + "\n\n当前角色语气：\n" + instruction(context.get("snapshot", {}))
            + "\n\n本次请求数据（JSON）：\n" + json.dumps(data, ensure_ascii=False, separators=(",", ":"))
            + '\n\n请输出最终 JSON，并在对象中原样附加 request_id。')


def parse_decision(raw, request_id):
    if not isinstance(raw, str) or len(raw.encode("utf-8")) > 32768:
        raise ValueError("模型返回内容过长或不是文字")
    # Ignore surrounding prose, but never evaluate code. Select the object with
    # this unique nonce, not an example or an earlier reply on the same page.
    decoder = json.JSONDecoder()
    for index, char in enumerate(raw):
        if char != "{":
            continue
        try:
            value, _ = decoder.raw_decode(raw[index:])
        except ValueError:
            continue
        if not isinstance(value, dict) or value.get("request_id") != request_id:
            continue
        if set(value) - {"request_id", "text", "skill", "arguments", "plan"}:
            continue
        skill, arguments, text = value.get("skill"), value.get("arguments", {}), value.get("text")
        if skill is not None and (not isinstance(skill, str) or skill not in NAMES):
            raise ValueError("模型选择了不存在的接口")
        if not isinstance(arguments, dict):
            raise ValueError("模型接口参数必须是对象")
        if text is not None and (not isinstance(text, str) or len(text.encode("utf-8")) > 600):
            raise ValueError("模型台词过长或格式错误")
        if "plan" in value:
            validate_plan(value["plan"])
        return {key: value[key] for key in ("text", "skill", "arguments", "plan") if value.get(key) is not None}
    raise ValueError("没有找到本次请求的有效 JSON 回复")

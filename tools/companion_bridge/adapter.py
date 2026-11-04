"""Replace decide(context) to connect any model. Default demo makes no network calls."""
import importlib.util
from pathlib import Path


class DemoAdapter:
    label = "本地演示（未连接大模型）"

    def decide(self, context):
        if context.get("input_kind") == "ambient":
            return {}
        text, results = context["utterance"], context["results"]
        if "暗影操控器" in text and any(word in text for word in ("去", "跑", "走", "旁边")):
            if not results:
                current = context.get("snapshot", {}).get("action")
                if current is not None:
                    return {"skill": "cancel", "arguments": {"action_id": current["action_id"]}}
            if not results or results[-1]["skill"] == "cancel":
                return {"skill": "observe", "arguments": {"scope": "structures", "filter": "researchlab3", "radius": 32}}
            last = results[-1]
            if last["skill"] == "observe":
                entities = (last.get("result") or {}).get("entities", [])
                if last["status"] != "completed" or not entities:
                    return {"text": "附近没有找到暗影操控器，请带我靠近一点再试。"}
                return {"text": "好，我到暗影操控器旁边去。", "skill": "move_to", "arguments": {
                    "target": entities[0]["handle"], "gait": "run" if "跑" in text else "walk", "distance": 3}}
            if last["skill"] == "move_to" and last["status"] == "completed":
                return {"text": "我已经到暗影操控器旁边了。"}
            return {"text": "这次没有到达，原因是：" + str(last.get("reason", "未知"))}
        if any(word in text for word in ("扫描", "看看附近")):
            if not results:
                return {"skill": "observe", "arguments": {"scope": "nearby", "radius": 20}}
            found = (results[-1].get("result") or {}).get("entities", [])
            return {"text": "我看到了附近的 " + str(len(found)) + " 个目标，详细结果在本机助手里。"}
        if any(word in text for word in ("你好", "在吗")):
            return {"text": "我在这里，你好呀。"}
        return {"text": "我收到你的话了。目前是本地演示模式，完整理解和自由聊天需要接入你选择的模型。"}


def load_adapter(filename=None):
    if filename is None:
        return DemoAdapter()
    path = Path(filename).expanduser().resolve()
    spec = importlib.util.spec_from_file_location("my_friends_user_adapter", path)
    if spec is None or spec.loader is None:
        raise ValueError("不能加载适配器文件")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # explicitly chosen local code, never received over HTTP
    adapter = module.create_adapter()
    if not callable(getattr(adapter, "decide", None)):
        raise ValueError("适配器必须提供 decide(context)")
    return adapter

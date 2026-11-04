"""Native API/config/transport boundaries; never uses a real API key or microphone."""
import copy
import io
import json
from pathlib import Path
import secrets
import threading
import unittest
from unittest.mock import Mock, patch

from tools.companion_bridge import api_config, export_workshop
from tools.companion_bridge.capabilities import TOOLS
from tools.companion_bridge.deepseek_api import DeepSeekAPIAdapter, ToolArgumentError, native_tools
from tools.companion_bridge.model import prompt
from tools.companion_bridge.server import Store


def response(skill=None, arguments=None, text=None, finish=None):
    message = {"role": "assistant", "content": text, "reasoning_content": "private task reasoning"}
    if skill:
        message["tool_calls"] = [{"id": "call_1", "type": "function", "function": {
            "name": skill, "arguments": json.dumps(arguments or {}, ensure_ascii=False)}}]
    return {"choices": [{"message": message, "finish_reason": finish or ("tool_calls" if skill else "stop")}],
            "usage": {"prompt_tokens": 120, "completion_tokens": 30}}


class APITests(unittest.TestCase):
    def setUp(self):
        self.directory = Path("tests/.local/deepseek_api") / secrets.token_hex(4)
        self.directory.mkdir(parents=True)
        self.config = {**api_config.DEFAULTS, "api_key": "test-only-never-network"}
        self.adapter = DeepSeekAPIAdapter(self.config)
        self.context = {"utterance": "换包", "input_kind": "user", "tools": copy.deepcopy(TOOLS),
                        "snapshot": {"handle": "self", "name": "伙伴"}, "results": [], "history": []}

    def tearDown(self):
        self.adapter.close()

    def test_config_bom_defaults_auto_selection_and_invalid_credentials(self):
        path = self.directory / "AssistantAPI.json"
        with patch.dict("os.environ", {"DEEPSEEK_API_KEY": ""}):
            initial = api_config.load(path)
            self.assertEqual(initial, api_config.DEFAULTS)
            self.assertFalse(hasattr(api_config.select_adapter("auto", {"web_code": "test-web"}, initial), "config"))
            path.write_text(json.dumps({"api_key": "test-key"}), encoding="utf-8-sig")
            config = api_config.load(path)
            self.assertIsInstance(api_config.select_adapter("auto", {}, config), DeepSeekAPIAdapter)
            for values in ({"api_key": "bad\nkey"}, {"model": "bad/model"}, {"thinking": "yes"},
                           {"timeout_seconds": 0}, {"retries": 20}, {"extra": "typo"}):
                path.write_text(json.dumps(values), encoding="utf-8")
                with self.assertRaises(ValueError):
                    api_config.load(path)
        with self.assertRaisesRegex(ValueError, "api_key"):
            api_config.select_adapter("deepseek-api", {}, api_config.DEFAULTS)

    def test_tools_do_not_mutate_web_schemas_and_no_duplicate_prompt_schema(self):
        before = copy.deepcopy(TOOLS)
        tools = native_tools(TOOLS)
        self.assertEqual(TOOLS, before)
        self.assertIn("_plan", tools[0]["function"]["parameters"]["properties"])
        with patch.object(self.adapter, "_post", return_value=response(text="你好")) as post:
            self.assertEqual(self.adapter.decide(self.context), {"text": "你好"})
        payload = post.call_args.args[0]
        self.assertNotIn("只输出一个JSON", payload["messages"][0]["content"])
        data = json.loads(payload["messages"][-1]["content"])
        self.assertNotIn("tools", data)
        self.assertNotIn("results", data)
        self.assertNotIn("request_id", data)
        self.assertEqual(len(payload["tools"]), len(TOOLS))
        self.assertIn('"request_id":"web-nonce"', prompt(self.context, "web-nonce"))

    def test_settings_save_is_validated_and_does_not_persist_environment_key(self):
        path = self.directory / "AssistantAPI.json"
        path.write_text('{"api_key":""}', encoding="utf-8")
        with patch.dict("os.environ", {"DEEPSEEK_API_KEY": "environment-test-key"}):
            self.assertEqual(api_config.load(path)["api_key"], "environment-test-key")
            values = api_config.load(path, resolve_env=False)
            self.assertEqual(values["api_key"], "")
            values.update(model="deepseek-v4-pro", thinking=False, reasoning_effort="max")
            api_config.save(values, path)
        self.assertEqual(json.loads(path.read_text())["api_key"], "")
        before = path.read_bytes()
        with self.assertRaises(ValueError):
            api_config.save({**values, "max_tokens": 0}, path)
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(list(self.directory.glob("AssistantAPI.json.*")), [])

    def test_hidden_model_settings_save_options_and_reject_invalid_limits(self):
        import tkinter as tk
        from tools.companion_bridge.api_settings import show
        root = tk.Tk()
        root.withdraw()
        try:
            path = self.directory / "AssistantAPI.json"
            api_config.save(self.config, path)
            with patch.object(api_config, "ROOT", self.directory):
                window = show(root)
                window.withdraw()
                body = window.winfo_children()[0]
                self.assertEqual(body.children["api_key"].cget("show"), "*")
                body.children["model"].set("deepseek-v4-pro")
                body.children["effort"].set("最高（max）")
                body.children["thinking"].invoke()
                self.assertEqual(str(body.children["effort"].cget("state")), "disabled")
                body.children["save"].invoke()
                self.assertIn("重启", body.children["hint"].cget("text"))
                saved = api_config.load(path)
                self.assertEqual(saved["model"], "deepseek-v4-pro")
                self.assertFalse(saved["thinking"])
                self.assertEqual(saved["reasoning_effort"], "max")
                self.assertEqual(saved["api_key"], self.config["api_key"])
                before = path.read_bytes()
                body.children["max_tokens"].delete(0, "end")
                body.children["max_tokens"].insert(0, "invalid")
                body.children["save"].invoke()
                self.assertEqual(path.read_bytes(), before)
                self.assertIn("整数", body.children["hint"].cget("text"))
            reloaded = DeepSeekAPIAdapter(saved)
            try:
                with patch.object(reloaded, "_post", return_value=response(text="你好")) as post:
                    reloaded.decide(self.context)
                payload = post.call_args.args[0]
                self.assertEqual(payload["model"], "deepseek-v4-pro")
                self.assertEqual(payload["thinking"], {"type": "disabled"})
                self.assertNotIn("reasoning_effort", payload)
            finally:
                reloaded.close()
        finally:
            root.destroy()

    def test_default_launcher_selects_api_from_file_without_opening_browser_or_network(self):
        from tools.companion_bridge import desktop
        (self.directory / "AssistantAPI.json").write_text(json.dumps({"api_key": "launch-test-key"}), encoding="utf-8")
        with patch.object(api_config, "ROOT", self.directory), patch("sys.argv", ["assistant"]), \
                patch("tools.companion_bridge.settings.load", return_value={"pair_code": "321151", "web_code": "web-test"}), \
                patch("tools.companion_bridge.diagnostics.configure"), patch.object(desktop, "make_server") as server, \
                patch.object(desktop, "desktop") as gui, patch("sys.stdout", new=io.StringIO()):
            desktop.main()
        store = gui.call_args.args[0]
        self.assertIsInstance(store.adapter, DeepSeekAPIAdapter)
        self.assertEqual(store.adapter.config["api_key"], "launch-test-key")
        self.assertEqual(store.adapter.diagnostics()["requests"], 0)
        self.assertTrue(store.adapter.closed)
        server.return_value.server_close.assert_called_once()

    def test_native_call_receipt_reasoning_plan_and_next_user_reset(self):
        plan = {"goal": "换包", "bindings": {"old": "e1", "new": "e2"}}
        receipt = {"skill": "drop", "status": "completed", "result": {"count": 1}}
        with patch.object(self.adapter, "_post", side_effect=[
                response("drop", {"item": "e1", "_text": "给你旧包。", "_plan": plan}),
                response(text="旧包放好了。"), response(text="你好")]) as post:
            self.context["snapshot"].update(inventory=[{"handle": "e1"}], environment={"items": []})
            result = self.adapter.decide(self.context)
            self.assertEqual(result["arguments"], {"item": "e1"})
            self.assertEqual(result["plan"], plan)
            self.assertEqual(result["text"], "给你旧包。")
            self.context["snapshot"].pop("environment")
            self.context["snapshot"]["position"] = {"x": 4, "z": 1}
            self.context.update(results=[receipt], task_plan=plan)
            self.adapter.decide(self.context)
            messages = post.call_args.args[0]["messages"]
            self.assertEqual(messages[-3]["reasoning_content"], "private task reasoning")
            self.assertEqual(messages[-2]["role"], "tool")
            self.assertEqual(messages[-2]["tool_call_id"], "call_1")
            self.assertEqual(json.loads(messages[-2]["content"]), receipt)
            update = json.loads(messages[-1]["content"])
            self.assertEqual(update["task_plan"], plan)
            self.assertEqual(update["snapshot_update"], {"set": {"position": {"x": 4, "z": 1}}, "remove": ["environment"]})
            self.context.update(results=[], task_plan={}, utterance="你好")
            self.adapter.decide(self.context)
            self.assertEqual(len(post.call_args.args[0]["messages"]), 2)
        self.assertEqual(self.adapter.diagnostics()["completion_tokens"], 90)

    def test_rejects_unallowed_invalid_multiple_and_truncated_tools_without_executing(self):
        cases = [response("made_up"), response("drop", {}), response("pickup", {"target": "e1", "count": 0}),
                 response("drop", {"item": "e1", "code": "bad"}), response("drop", {"item": 42}),
                 response("drop", {"item": "e1"}, finish="length"), response(text="中" * 201),
                 response(text="")]
        multiple = response("drop", {"item": "e1"})
        multiple["choices"][0]["message"]["tool_calls"] *= 2
        cases.append(multiple)
        for result in cases:
            with self.subTest(result=result), patch.object(self.adapter, "_post", return_value=result):
                with self.assertRaises(ValueError):
                    self.adapter.decide(self.context)

    def test_read_only_permissions_apply_to_native_tools_and_ambient_is_opt_in(self):
        self.context["tools"] = [tool for tool in TOOLS if tool["name"] == "observe"]
        with patch.object(self.adapter, "_post", return_value=response("drop", {"item": "e1"})):
            with self.assertRaisesRegex(ValueError, "未授权"):
                self.adapter.decide(self.context)
        self.context["input_kind"] = "ambient"
        with patch.object(self.adapter, "_post") as post:
            self.assertEqual(self.adapter.decide(self.context), {})
            post.assert_not_called()
        store = Store(self.adapter)
        try:
            store.connected = True
            self.assertFalse(store.maybe_ambient())
        finally:
            store.close()

    def test_bad_step_field_is_repaired_after_query_without_replaying_or_executing_it(self):
        store = Store(self.adapter)
        try:
            store.connected, store.session = True, "test-session"
            query = {"queries": [{"id": "food", "skill": "observe", "arguments": {"scope": "containers", "contents": True}}]}
            steps = {"steps": [{"id": "pick", "skill": "work", "arguments": {"target": "bush", "action": "PICK"}}]}
            bad = copy.deepcopy(steps)
            bad["steps"][0]["text"] = "private narration that must not be logged"
            receipt = {"skill": "query_batch", "status": "completed", "result": {"results": [
                {"id": "food", "result": {"entities": [{"handle": "fridge"}]}}]}}
            with patch.object(self.adapter, "_post", side_effect=[response("query_batch", query),
                    response("execute_sequence", bad), response("execute_sequence", steps), response(text="完成了。")]) as post, \
                    patch.object(store, "enqueue", return_value="request") as enqueue, \
                    patch.object(store, "wait", side_effect=[receipt,
                        {"skill": "execute_sequence", "status": "completed", "result": {"completed": 1}}, {"status": "completed"}]), \
                    patch("tools.companion_bridge.deepseek_api.LOG") as log:
                store._turn("摘石果再做肉丸", store.session, store.turn_version, "user")
            self.assertEqual([call.args[0] for call in enqueue.call_args_list], ["query_batch", "execute_sequence", "say"])
            self.assertEqual(enqueue.call_args_list[1].args[1], steps)
            correction = post.call_args_list[2].args[0]["messages"]
            self.assertTrue(any(msg.get("role") == "tool" and json.loads(msg["content"]).get("result") == receipt["result"] for msg in correction))
            self.assertEqual(correction[-3]["reasoning_content"], "private task reasoning")
            rejected = json.loads(correction[-2]["content"])
            self.assertFalse(rejected["executed"])
            self.assertIn("execute_sequence.arguments.steps[1].text", rejected["detail"])
            self.assertIn("允许字段", rejected["detail"])
            self.assertNotIn("private narration", str(log.warning.call_args_list))
            # Count all API responses, including the rejected one and its correction.
            self.assertEqual(self.adapter.diagnostics()["completion_tokens"], 120)
        finally:
            store.close()

    def test_argument_correction_is_bounded_and_keeps_specific_field_error(self):
        bad = response("work_many", {"action": "PICK", "count": 6})
        with patch.object(self.adapter, "_post", return_value=bad) as post:
            with self.assertRaises(ToolArgumentError) as error:
                self.adapter.decide(self.context)
        self.assertIn("work_many.arguments.count", str(error.exception))
        self.assertEqual(error.exception.category, "unknown_field")
        self.assertEqual(post.call_count, 2)
        self.assertEqual(self.adapter.messages, [])
        self.assertIsNone(self.adapter.pending)

    def test_cancel_during_argument_correction_discards_the_fixed_action(self):
        replies = iter([response("drop", {"item": "e1", "count_wrong": 1}), None])
        def fixed(*args):
            reply = next(replies)
            if reply is not None:
                return reply
            self.adapter.cancel_pending()
            return response("drop", {"item": "e1"})
        with patch.object(self.adapter, "_post", side_effect=fixed) as post:
            with self.assertRaisesRegex(ValueError, "superseded"):
                self.adapter.decide(self.context)
        self.assertEqual(post.call_count, 2)
        self.assertIsNone(self.adapter.pending)
        self.assertEqual(self.adapter.messages, [])

    def test_store_runs_two_api_decisions_and_only_one_physical_action(self):
        store = Store(self.adapter)
        try:
            store.connected, store.session = True, "test-session"
            with patch.object(self.adapter, "_post", side_effect=[response("pickup", {"target": "e1"}),
                    response(text="拿到了。")]) as post, patch.object(store, "enqueue", return_value="id") as enqueue, \
                    patch.object(store, "wait", side_effect=[
                        {"skill": "pickup", "status": "completed", "result": {"count": 1}}, {"status": "completed"}]):
                store._turn("拿给我", store.session, store.turn_version, "user")
                self.assertEqual([call.args[0] for call in enqueue.call_args_list], ["pickup", "say"])
                self.assertEqual(post.call_count, 2)
        finally:
            store.close()

    def test_http_error_redaction_and_bounded_retry(self):
        connection = Mock()
        connection.getresponse.return_value.status = 401
        with patch("tools.companion_bridge.deepseek_api.http.client.HTTPSConnection", return_value=connection):
            with self.assertRaisesRegex(ValueError, "Key无效") as error:
                self.adapter._post({}, threading.Event())
        self.assertNotIn(self.config["api_key"], str(error.exception))
        connection.getresponse.return_value.read.assert_not_called()
        self.assertEqual(connection.request.call_args.args[:2], ("POST", "/chat/completions"))
        connection.getresponse.return_value.status = 503
        event = Mock(is_set=Mock(return_value=False), wait=Mock(return_value=False))
        connection.reset_mock()
        with patch("tools.companion_bridge.deepseek_api.http.client.HTTPSConnection", return_value=connection):
            with self.assertRaises(ValueError):
                self.adapter._post({}, event)
        self.assertEqual(connection.request.call_count, 2)

    def test_http_success_and_network_failure_never_replays_a_game_tool(self):
        connection = Mock()
        connection.getresponse.return_value.status = 200
        connection.getresponse.return_value.read.return_value = json.dumps(response(text="你好")).encode()
        with patch("tools.companion_bridge.deepseek_api.http.client.HTTPSConnection", return_value=connection) as factory:
            self.assertEqual(self.adapter.decide(self.context), {"text": "你好"})
        self.assertEqual(factory.call_args.args, ("api.deepseek.com",))
        self.assertEqual(connection.request.call_args.args[3]["Authorization"], "Bearer " + self.config["api_key"])
        self.assertEqual(self.adapter.diagnostics()["requests"], 1)
        connection.request.side_effect = TimeoutError("untrusted error with private fields")
        connection.request.reset_mock()
        with patch("tools.companion_bridge.deepseek_api.http.client.HTTPSConnection", return_value=connection):
            with self.assertRaisesRegex(ValueError, "连接失败") as error:
                self.adapter.decide(self.context)
        self.assertNotIn("private fields", str(error.exception))
        self.assertEqual(connection.request.call_count, 1)

    def test_cancelled_reply_is_discarded_and_network_closed(self):
        connection = Mock()
        self.adapter.connection = connection
        def cancelled_response(*args):
            self.adapter.cancel_pending()
            return response("pickup", {"target": "e1"})
        with patch.object(self.adapter, "_post", side_effect=cancelled_response):
            with self.assertRaisesRegex(ValueError, "superseded"):
                self.adapter.decide(self.context)
        connection.sock.shutdown.assert_called_once()
        connection.close.assert_called_once()
        self.assertEqual(self.adapter.messages, [])
        self.assertIsNone(self.adapter.pending)

    def test_export_always_replaces_local_keys_and_even_modified_example(self):
        root = self.directory.resolve()
        script = root / "tools/companion_bridge/export_workshop.py"
        script.parent.mkdir(parents=True)
        for name in ("AssistantAPI.json", "AssistantAPI.example.json", "AssistantAPI.json.test.new"):
            (root / name).write_text('{"api_key":"private-export-test"}', encoding="utf-8")
        (root / "modmain.lua").write_text("-- example", encoding="utf-8")
        destination = root / "output"
        with patch.object(export_workshop, "__file__", str(script)), \
                patch.object(export_workshop.subprocess, "check_output", return_value=b"modmain.lua\0AssistantAPI.json\0AssistantAPI.example.json\0AssistantAPI.json.test.new\0"), \
                patch("sys.argv", ["export", "--output", str(destination)]), patch("sys.stdout", new=io.StringIO()):
            export_workshop.main()
        for name in ("AssistantAPI.json", "AssistantAPI.example.json"):
            exported = (destination / name).read_text(encoding="utf-8")
            self.assertNotIn("private-export-test", exported)
            self.assertEqual(json.loads(exported), api_config.DEFAULTS)
        self.assertTrue((destination / "modmain.lua").exists())
        self.assertFalse((destination / "AssistantAPI.json.test.new").exists())


if __name__ == "__main__":
    unittest.main()

"""python -B -m unittest discover -s tests -p body_bridge_test.py"""
from http.client import HTTPConnection
import json
import threading
import time
import unittest
from pathlib import Path
import secrets
from unittest.mock import patch

from tools.companion_bridge.adapter import DemoAdapter
from tools.companion_bridge.capabilities import NAMES, TOOLS, compact_arguments
from tools.companion_bridge.server import BridgeError, Store, make_server
from tools.companion_bridge.model import parse_decision, prompt
from tools.companion_bridge.web_model import DeepSeekWebAdapter
from tools.companion_bridge import settings
from tools.companion_bridge.personas import instruction


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.store = Store(DemoAdapter(), "481529")
        self.token = self.store.connect({"code": "481529", "session": "test-body"})["token"]

    def tearDown(self):
        self.store.close()

    def exchange(self, events=None, **extra):
        return self.store.exchange({"token": self.token, "session": "test-body", "events": events or [], **extra})

    def event(self, request, status="completed", **extra):
        return {"event_id": request + ":" + status, "request_id": request,
                "action_id": "action:" + request, "status": status, **extra}

    def test_pairing_token_and_single_session(self):
        with self.assertRaises(BridgeError):
            self.store.connect({"code": "wrong", "session": "other"})
        with self.assertRaises(BridgeError):
            self.store.connect({"code": "481529", "session": "other"})
        with self.assertRaises(BridgeError):
            self.store.exchange({"token": "wrong", "session": "test-body"})

    def test_commands_repeat_until_game_receipt_then_leave_the_queue(self):
        request = self.store.enqueue("observe", {"filter": None})
        first = self.exchange()["commands"]
        self.assertEqual(first, self.exchange()["commands"])
        self.assertEqual(first[0]["arguments"], {})
        response = self.exchange([self.event(request)])
        self.assertEqual(response["commands"], [])
        self.assertEqual(response["ack"], [request + ":completed"])

    def test_terminal_result_cannot_be_replaced_by_a_late_running_receipt(self):
        request = self.store.enqueue("move_to", {"target": "e1"})
        self.exchange([self.event(request)])
        self.exchange([self.event(request, "running")])
        self.assertEqual(self.store.wait(request)["status"], "completed")
        self.assertIsNone(self.store.current_action)

    def test_duplicate_event_is_acknowledged_but_does_not_produce_duplicate_output(self):
        request = self.store.enqueue("observe", {})
        event = self.event(request)
        self.exchange([event]); self.exchange([event])
        messages = []
        while not self.store.messages.empty():
            messages.append(self.store.messages.get_nowait())
        self.assertEqual(sum(item["kind"] == "result" for item in messages), 1)

    def test_rejects_unknown_skills_nonobjects_and_oversized_arguments(self):
        for name, arguments in [("eval", {}), ("observe", []), ("say", {"text": "a" * 4000})]:
            with self.assertRaises(BridgeError):
                self.store.enqueue(name, arguments)

    def test_results_and_pending_commands_remain_bounded(self):
        for i in range(100):
            self.exchange([self.event(str(i))])
        self.assertLessEqual(len(self.store.results), 80)
        for i in range(16):
            self.store.enqueue("observe", {})
        with self.assertRaises(BridgeError):
            self.store.enqueue("observe", {})

    def test_manual_takeover_returns_interruption_and_prevents_further_commands(self):
        request = self.store.enqueue("move_to", {"target": "e1"})
        response = self.exchange([self.event(request, "interrupted", reason="manual_command")], closing="manual_command")
        self.assertEqual(self.store.wait(request)["reason"], "manual_command")
        self.assertFalse(self.store.connected)
        self.assertEqual(response["commands"], [])
        with self.assertRaises(BridgeError):
            self.store.enqueue("move_to", {"target": "e1"})

    def test_demo_full_observe_move_feedback_say_loop(self):
        self.store.submit("温蒂，跑到暗影操控器从旁边")
        skills, replies = [], []
        deadline = time.monotonic() + 3
        while self.store.busy and time.monotonic() < deadline:
            for command in self.exchange()["commands"]:
                skill, request = command["skill"], command["request_id"]
                skills.append(skill)
                if skill == "observe":
                    result = {"entities": [{"handle": "e-shadow", "prefab": "researchlab3"}]}
                elif skill == "move_to":
                    self.assertEqual(command["arguments"], {"target": "e-shadow", "gait": "run", "distance": 3})
                    result = {"position": {"x": 6, "z": 2}}
                else:
                    replies.append(command["arguments"]["text"])
                    result = {"text": replies[-1]}
                self.exchange([self.event(request, skill=skill, result=result)])
            time.sleep(.005)
        self.assertFalse(self.store.busy)
        self.assertEqual(skills, ["observe", "say", "move_to", "say"])
        self.assertIn("已经到", replies[-1])

    def test_failed_move_does_not_report_arrival(self):
        decision = self.store.adapter.decide({"utterance": "跑到暗影操控器旁边", "results": [
            {"skill": "move_to", "status": "failed", "reason": "unreachable"}]})
        self.assertIn("没有到达", decision["text"])

    def test_chat_only_uses_say_and_never_moves(self):
        decision = self.store.adapter.decide({"utterance": "你好温蒂", "results": []})
        self.assertIsNone(decision.get("skill"))
        self.assertIn("你好", decision["text"])

    def test_say_only_and_text_plus_say_end_the_turn_after_one_utterance(self):
        for decision in (
            {"skill": "say", "arguments": {"text": "戴好了", "speak": False}},
            {"text": "戴好了", "skill": "say", "arguments": {"text": "戴好了"}},
            {"text": "前置台词", "skill": "say", "arguments": {"text": "最终台词"}},
        ):
            seen = []
            class Model:
                def decide(self, context):
                    seen.append(context)
                    return decision
            self.store.adapter = Model()
            with patch.object(self.store, "enqueue", return_value="speech") as enqueue, patch.object(self.store, "wait", return_value={"status": "completed"}):
                self.store._turn("换头盔", self.store.session, self.store.turn_version, "user")
            self.assertEqual(len(seen), 1)
            self.assertEqual(enqueue.call_count, 1)
            self.assertEqual(enqueue.call_args.args[1]["text"], decision["arguments"]["text"])
            self.assertEqual(enqueue.call_args.args[1]["speak"], decision["arguments"].get("speak", True))
            self.assertEqual(self.store.history[-1]["assistant"], decision["arguments"]["text"])
            self.assertFalse(self.store.busy)

    def test_completed_action_then_say_does_not_restart_the_completion_loop(self):
        seen = []
        class Model:
            def decide(self, context):
                seen.append(context)
                if len(seen) == 1:
                    return {"skill": "equip", "arguments": {"item": "helmet"}, "plan": {"goal": "戴头盔", "bindings": {"helmet": "helmet"}}}
                return {"text": "亮茄头盔已戴好", "skill": "say", "arguments": {"text": "亮茄头盔已戴好"}}
        self.store.adapter = Model()
        with patch.object(self.store, "enqueue", return_value="request") as enqueue, patch.object(self.store, "wait", side_effect=[
            {"skill": "equip", "status": "completed", "result": {"slot": "head"}}, {"status": "completed"}]):
            self.store._turn("戴亮茄头盔", self.store.session, self.store.turn_version, "user")
        self.assertEqual(len(seen), 2)
        self.assertEqual([call.args[0] for call in enqueue.call_args_list], ["equip", "say"])
        self.assertEqual(len(seen[1]["results"]), 1)
        self.assertEqual(seen[1]["task_plan"]["bindings"]["helmet"], "helmet")
        memory = self.store.task_memory["local"]
        self.assertEqual(memory["plan"], {"goal": "戴头盔"})
        self.assertEqual(memory["effects"], [{"skill": "equip"}])
        with patch.object(self.store.adapter, "decide", return_value={}) as decide:
            self.store._turn("刚才做了什么", self.store.session, self.store.turn_version, "user")
            self.assertEqual(decide.call_args.args[0]["last_task"], memory)
            self.assertEqual(decide.call_args.args[0]["task_plan"], {})

    def test_long_turn_continues_past_old_limit_with_bounded_recent_receipts(self):
        seen = []

        class Model:
            def decide(self, context):
                seen.append(context)
                if len(seen) <= 40:
                    return {"skill": "work", "arguments": {"target": f"e{len(seen)}", "action": "PICK"}}
                return {"text": "采完了"}

        self.store.adapter = Model()
        self.store.submit("采完这批作物")
        requests = []
        deadline = time.monotonic() + 3
        while not self.store.pending_future.done() and time.monotonic() < deadline:
            for command in self.exchange()["commands"]:
                requests.append(command)
                self.exchange([self.event(command["request_id"], skill=command["skill"], result={"work_units": 1})])
            time.sleep(.005)
        self.store.pending_future.result(timeout=1)
        self.assertEqual([item["skill"] for item in requests], ["work"] * 40 + ["say"])
        self.assertEqual(len(seen[-1]["results"]), 32)
        self.assertTrue(seen[-1]["results_limited"])
        self.assertEqual(seen[-1]["results"][0]["arguments"]["target"], "e9")
        self.assertEqual(self.store.history[-1]["assistant"], "采完了")

    def test_voice_states_are_bounded_and_forwarded(self):
        for i in range(60):
            self.store.speech(str(i), "completed")
        self.assertEqual(len(self.exchange()["playback"]), 40)

    def test_follow_mode_completes_then_chat_and_work_need_no_cancel(self):
        class FollowAdapter:
            def decide(self, context):
                if context["utterance"] == "follow" and not context["results"]:
                    return {"skill": "follow", "arguments": {"player": "e1"}}
                if context["utterance"] == "work" and not context["results"]:
                    return {"skill": "pickup", "arguments": {"target": "e2"}}
                return {"text": "hello"}
        self.store.adapter = FollowAdapter()
        self.store.submit("follow")
        skills = []
        for utterance in ("follow", "chat", "work"):
            if utterance != "follow":
                self.store.submit(utterance)
            deadline = time.monotonic() + 2
            while self.store.busy and time.monotonic() < deadline:
                for command in self.exchange()["commands"]:
                    request, skill = command["request_id"], command["skill"]
                    skills.append(skill)
                    self.exchange([self.event(request, "completed", skill=skill, result={})])
                time.sleep(.005)
            self.assertFalse(self.store.busy)
            self.assertIsNone(self.store.current_action)
        self.assertIn("follow", skills); self.assertIn("pickup", skills); self.assertNotIn("cancel", skills)

    def test_valid_page_observation_flows_through_model_game_receipts_and_final_chat(self):
        self.store.adapter = DeepSeekWebAdapter()
        self.store.adapter.heartbeat()
        self.store.submit("看看周围有什么")
        seen, skills = set(), []
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and not self.store.pending_future.done():
            job = self.store.adapter.poll()["job"]
            if job and job["request_id"] not in seen:
                seen.add(job["request_id"])
                decision = {"request_id": job["request_id"], "text": "我这就看看周围有些什么。"} if len(seen) == 1 else {
                    "request_id": job["request_id"], "text": "我看到了一棵树。"}
                if len(seen) == 1:
                    decision.update(skill="observe", arguments={"scope": "nearby", "radius": 20})
                self.store.adapter.receive({"request_id": job["request_id"], "text": json.dumps(decision, ensure_ascii=False)})
            commands = self.exchange()["commands"]
            for command in commands:
                skills.append(command["skill"])
                self.exchange([self.event(command["request_id"], skill=command["skill"], result={
                    "entities": [{"handle": "e1", "prefab": "evergreen"}]})])
            time.sleep(.005)
        self.store.pending_future.result(timeout=1)
        self.assertEqual(skills, ["say", "observe", "say"])
        self.assertEqual(len(seen), 2)
        self.assertFalse(self.store.busy)

    def test_capability_names_match_the_documented_basics(self):
        self.assertEqual(len(NAMES), 38)
        self.assertTrue({"query_sites", "revive", "emote", "dismount"} <= NAMES)
        self.assertEqual(len(TOOLS), len(NAMES))
        self.assertEqual(compact_arguments({"target": None, "position": {"x": 1, "z": 2, "y": None}}),
                         {"position": {"x": 1, "z": 2}})

    def test_plan_lease_starts_only_for_physical_model_steps_and_releases_on_done_or_new_intent(self):
        self.store.busy = True
        version = self.store.turn_version
        self.store.enqueue("query_recipe", {"query": "researchlab"}, version=version)
        self.assertIsNone(self.exchange()["plan"])
        self.store.enqueue("say", {"text": "我来看看"}, version=version)
        self.assertIsNone(self.exchange()["plan"])
        pickup = self.store.enqueue("pickup", {"target": "e1"}, version=version)
        packet = self.exchange()
        self.assertTrue(packet["plan"]["active"])
        self.assertEqual(packet["plan"]["id"], next(c for c in packet["commands"] if c["request_id"] == pickup)["plan_id"])
        self.store.busy = False
        self.assertFalse(self.exchange()["plan"]["active"])
        self.store.busy = True
        with self.store.condition:
            self.store._invalidate_locked()
        self.store.busy = True  # a new chat turn has not issued a physical step
        self.assertFalse(self.exchange()["plan"]["active"])
        self.store.busy = False

    def test_world_restart_and_pause_receipts_end_planning_without_replaying(self):
        for skill, arguments in (("save_game", {}), ("rollback_game", {"count": 2}), ("pause_game", {"paused": False})):
            decisions = []
            class Model:
                def decide(self, context):
                    decisions.append(context)
                    return {"skill": skill, "arguments": arguments}
            self.store.adapter = Model()
            self.store.submit("执行这次世界操作")
            deadline = time.monotonic() + 2
            commands = []
            while not commands and time.monotonic() < deadline:
                commands = self.exchange()["commands"]
                if not commands:
                    time.sleep(.005)
            self.assertEqual(commands[0]["skill"], skill)
            self.assertEqual(commands[0]["arguments"], arguments)
            self.exchange([self.event(commands[0]["request_id"], skill=skill, result={"requested": True})])
            self.store.pending_future.result(timeout=2)
            self.assertEqual(len(decisions), 1)
            self.assertFalse(self.store.busy)
            self.assertEqual(self.exchange()["commands"], [])

    def test_world_reason_boundaries_stop_the_turn_without_model_retry(self):
        for payload in ({"status": "completed", "result": {"needs_reason": True, "approval_id": "review"}},
                        {"status": "failed", "reason": "approval_expired"},
                        {"status": "failed", "reason": "reason_requires_next_player_message"}):
            calls = []
            class Model:
                def decide(self, context):
                    calls.append(context)
                    return {"skill": "save_game", "arguments": {}}
            self.store.adapter = Model()
            receipts = [payload, {"status": "completed"}]
            with patch.object(self.store, "enqueue", return_value="request") as enqueue, patch.object(self.store, "wait", side_effect=receipts):
                self.store._turn("保存世界", self.store.session, self.store.turn_version, "user")
            self.assertEqual(len(calls), 1)
            self.assertEqual([call.args[0] for call in enqueue.call_args_list], ["save_game", "say"])
            self.assertTrue(self.store.history[-1]["assistant"])

    def test_current_world_review_state_is_not_overwritten_by_old_input_snapshot(self):
        seen = []
        class Model:
            def decide(self, context):
                seen.append(context)
                return {}
        self.store.adapter = Model()
        self.store.snapshot = {"owner": {"userid": "player"}, "world_control": {"pending_request": {"approval_id": "fresh"}}}
        self.store._turn("这是我的原因", self.store.session, self.store.turn_version, "user",
                         {"speaker": {"userid": "player"}, "world_control": {}})
        self.assertEqual(seen[0]["snapshot"]["world_control"]["pending_request"]["approval_id"], "fresh")

    def test_model_reply_from_a_replaced_session_is_rejected(self):
        old = self.store.session
        self.exchange(closing="manual_command")
        self.store.connect({"code": "481529", "session": "new-body"})
        with self.assertRaises(BridgeError):
            self.store.enqueue("move_to", {"target": "e1"}, expected_session=old)
        self.assertFalse(self.store.commands)

    def test_new_utterance_supersedes_an_unfinished_model_reply(self):
        entered, release = threading.Event(), threading.Event()
        class Delayed:
            def decide(self, context):
                if context["utterance"] == "old":
                    entered.set(); release.wait(2)
                    return {"skill": "move_to", "arguments": {"position": {"x": 999, "z": 999}}}
                return {"text": "new task"}
        self.store.adapter = Delayed()
        self.store.submit("old"); self.assertTrue(entered.wait(1))
        self.store.submit("new"); release.set()
        deadline = time.monotonic() + 2; skills = []
        while self.store.busy and time.monotonic() < deadline:
            for command in self.exchange()["commands"]:
                skills.append(command["skill"])
                self.exchange([self.event(command["request_id"], skill=command["skill"], result={})])
            time.sleep(.005)
        self.assertEqual(skills, ["say"])
        self.assertFalse(self.store.busy)

    def test_manual_revision_interrupts_old_planning_without_disconnecting(self):
        self.store.enqueue("move_to", {"position": {"x": 1, "z": 1}})
        before = self.store.turn_version
        self.exchange([{"event_id": "manual:1", "kind": "control_changed", "revision": 3}])
        self.assertTrue(self.store.connected)
        self.assertEqual(self.store.snapshot["revision"], 3)
        self.assertFalse(self.store.commands)
        self.assertGreater(self.store.turn_version, before)
        request = self.store.enqueue("pickup", {"target": "e1"})
        self.assertEqual(self.store.commands[request]["revision"], 3)

    def test_stop_and_direct_calls_replace_work_but_observation_does_not(self):
        self.store.snapshot["manual_task"] = "chop"
        request = self.store.stop_action()
        self.assertEqual(self.store.commands[request]["skill"], "follow")
        observe = self.store.direct_call("observe", {})
        self.assertIn(request, self.store.commands); self.assertIn(observe, self.store.commands)
        work = self.store.direct_call("craft", {"recipe": "spear"})
        self.assertEqual(list(self.store.commands), [work])

    def test_silent_ambient_turns_do_not_evict_real_conversation_history(self):
        class Silent:
            def decide(self, context):
                return {}
        self.store.adapter = Silent()
        self.store.history.append({"user": "你好", "assistant": "我在", "kind": "user"})
        for _ in range(16):
            self.store._turn("", self.store.session, self.store.turn_version, "ambient")
        self.assertEqual(list(self.store.history), [{"user": "你好", "assistant": "我在", "kind": "user"}])
        self.assertFalse(self.store.busy)

    def test_ambient_chat_is_idle_only_and_never_requests_physical_actions(self):
        contexts = []
        class Ambient:
            def decide(self, context):
                contexts.append(context)
                return {"text": "今天很冷。"}
        self.store.adapter = Ambient()
        self.store.snapshot = {"world": {"day": 8, "season": "winter"}, "emergency": False}
        self.assertTrue(self.store.maybe_ambient())
        deadline = time.monotonic() + 2; commands = []
        while self.store.busy and time.monotonic() < deadline:
            for command in self.exchange()["commands"]:
                commands.append(command)
                self.exchange([self.event(command["request_id"], skill="say", result={})])
            time.sleep(.005)
        self.assertEqual([c["skill"] for c in commands], ["say"])
        self.assertEqual(commands[0]["source"], "ambient")
        self.assertEqual(contexts[0]["input_kind"], "ambient")
        self.store.last_user_at = time.monotonic(); self.assertFalse(self.store.maybe_ambient())
        self.store.last_user_at = 0; self.store.snapshot["emergency"] = True
        self.assertFalse(self.store.maybe_ambient())


class WebModelTests(unittest.TestCase):
    def test_stable_pairing_settings_and_character_guidance(self):
        directory = Path("tests/.local/body_bridge") / ("settings_" + secrets.token_hex(4))
        first = settings.load(directory)
        self.assertEqual(first["pair_code"], "321151")
        self.assertFalse(first["broadcast_input"])
        self.assertEqual(settings.load(directory)["web_code"], first["web_code"])
        changed = {"pair_code": "987654", "web_code": "my-custom-web-connection-code"}
        settings.save(changed, directory); self.assertEqual(settings.load(directory), changed)
        changed["broadcast_input"] = True
        settings.save(changed, directory)
        self.assertTrue(settings.load(directory)["broadcast_input"])
        with self.assertRaises(ValueError): settings.save({**changed, "broadcast_input": "false"}, directory)
        with self.assertRaises(ValueError): settings.validate("12x456", changed["web_code"])
        self.assertIn("沃拓克斯", instruction({"character": {"id": "wortox"}}))
        self.assertIn("沃特", instruction({"prefab": "my_friend_wurt"}))
    def test_prompt_contains_generic_contract_schemas_state_and_no_demo_routing(self):
        text = prompt({"utterance": "拿两块石头放到箱子里", "tools": TOOLS, "snapshot": {"health": 30}, "results": []}, "nonce")
        self.assertIn("拿两块石头放到箱子里", text)
        for name in NAMES:
            self.assertIn(name, text)
        self.assertIn("completed", text)
        self.assertIn("双向接替", text)

    def test_parser_ignores_echoed_context_and_stale_replies(self):
        raw = json.dumps({"request_id": "nonce", "utterance": "user", "tools": []})
        raw += json.dumps({"request_id": "old", "skill": "engage", "arguments": {"target": "old"}})
        raw += '```json\n' + json.dumps({"request_id": "nonce", "text": "去拿石头", "skill": "pickup", "arguments": {"target": "e7", "count": 2}}) + '\n```'
        self.assertEqual(parse_decision(raw, "nonce")["arguments"], {"target": "e7", "count": 2})
        for value in ({"request_id": "nonce", "skill": "execute_code"},
                      {"request_id": "nonce", "text": "中" * 201},
                      {"request_id": "other", "skill": "observe"}):
            with self.assertRaises(ValueError):
                parse_decision(json.dumps(value), "nonce")

    def test_web_adapter_waits_for_page_and_uses_actual_reply(self):
        adapter = DeepSeekWebAdapter()
        try:
            with self.assertRaises(ValueError):
                adapter.decide({})
            adapter.poll()
            result = []
            worker = threading.Thread(target=lambda: result.append(adapter.decide({"utterance": "看看地上", "tools": TOOLS})))
            worker.start()
            deadline = time.monotonic() + 2
            job = None
            while not job and time.monotonic() < deadline:
                job = adapter.poll()["job"]; time.sleep(.005)
            self.assertIsNotNone(job)
            with self.assertRaises(ValueError):
                adapter.receive({"request_id": "stale", "text": "{}"})
            adapter.receive({"request_id": job["request_id"], "text": json.dumps({
                "request_id": job["request_id"], "skill": "observe", "arguments": {"scope": "items"}})})
            worker.join(2)
            self.assertEqual(result, [{"skill": "observe", "arguments": {"scope": "items"}}])
            self.assertIsNone(adapter.poll()["job"])
        finally:
            adapter.close()

    def test_extension_http_origin_and_token_have_separate_permissions(self):
        store = Store(DeepSeekWebAdapter())
        server = make_server(store, port=0)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            def post(path, data, origin):
                connection = HTTPConnection("127.0.0.1", server.server_address[1], timeout=2)
                try:
                    connection.request("POST", path, json.dumps(data), {"Origin": origin})
                    response = connection.getresponse()
                    return response.status, json.loads(response.read())
                finally:
                    connection.close()
            self.assertEqual(post("/v1/model/poll", {"model_token": "bad"}, "chrome-extension://test")[0], 400)
            self.assertEqual(post("/v1/model/poll", {"model_token": store.adapter.secret}, "https://chat.deepseek.com")[0], 403)
            status, result = post("/v1/model/poll", {"model_token": store.adapter.secret}, "chrome-extension://test")
            self.assertEqual(status, 200); self.assertIsNone(result["job"])
            self.assertEqual(post("/v1/game/connect", {"code": store.code, "session": "forged"}, "chrome-extension://test")[0], 403)
        finally:
            store.close(); server.shutdown(); server.server_close()

    def test_page_progress_tracks_only_current_request_and_health_diagnostics_exclude_private_data(self):
        adapter = DeepSeekWebAdapter("private-web-token")
        adapter.pending = {"request_id": "private-request", "prompt": "private-prompt"}
        adapter.request_started = time.monotonic()
        adapter.poll({"request_id": "old", "phase": "reply_detected", "blocks": 4})
        self.assertIsNone(adapter.diagnostics()["phase"])
        adapter.poll({"request_id": "private-request", "phase": "reply_detected", "blocks": 2, "source": "code", "request_seen": True})
        state = adapter.diagnostics()
        self.assertEqual(state["phase"], "reply_detected")
        self.assertEqual(state["code_blocks"], 2)
        self.assertTrue(state["request_seen"])
        for value in ("private-web-token", "private-request", "private-prompt"):
            self.assertNotIn(value, json.dumps(state))
        adapter.poll({"request_id": "private-request", "phase": {}, "source": {}})
        self.assertEqual(adapter.diagnostics()["phase"], "reply_detected")
        adapter.cancel_pending()
        self.assertFalse(adapter.diagnostics()["pending"])
        self.assertIsNone(adapter.diagnostics()["phase"])
        adapter.close()

    def test_send_confirmation_failure_keeps_its_safe_diagnostic_code(self):
        adapter = DeepSeekWebAdapter()
        adapter.poll()
        def fail_first_send(_):
            adapter.receive({"request_id": adapter.pending["request_id"], "text": "",
                             "error": "private failure detail", "error_code": "send_not_confirmed"})
        try:
            with self.assertLogs("companion_bridge", level="WARNING") as captured, \
                 patch.object(adapter.condition, "wait", side_effect=fail_first_send):
                with self.assertRaisesRegex(ValueError, "private failure detail"):
                    adapter.decide({"utterance": "first message", "tools": TOOLS})
            self.assertIn("reason=send_not_confirmed", "\n".join(captured.output))
            self.assertNotIn("private failure detail", "\n".join(captured.output))
        finally:
            adapter.close()

    def test_background_tab_grace_and_true_expiration_are_distinct(self):
        adapter = DeepSeekWebAdapter()
        with patch("tools.companion_bridge.web_model.time.monotonic", return_value=1000):
            adapter.poll()
        with patch("tools.companion_bridge.web_model.time.monotonic", return_value=1065):
            self.assertEqual(adapter.connection_state(), "background")
        with patch("tools.companion_bridge.web_model.time.monotonic", return_value=1040):
            self.assertEqual(adapter.connection_state(), "connected")
        with patch("tools.companion_bridge.web_model.time.monotonic", return_value=1121):
            self.assertEqual(adapter.connection_state(), "disconnected")
        adapter.close()

    def test_real_page_heartbeat_keeps_helper_alive_without_consuming_or_changing_a_job(self):
        store = Store(DeepSeekWebAdapter("page-token-1234567890"), "481529")
        server = make_server(store, port=0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def post(token):
            connection = HTTPConnection("127.0.0.1", server.server_address[1], timeout=2)
            try:
                connection.request("POST", "/v1/model/heartbeat", json.dumps({"model_token": token}),
                                   {"Origin": "chrome-extension://test"})
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()
        try:
            store.adapter.pending = {"request_id": "still-running", "prompt": "private content"}
            self.assertEqual(post("wrong")[0], 400)
            self.assertEqual(store.adapter.page_seen, 0)
            status, receipt = post(store.adapter.secret)
            self.assertEqual(status, 200)
            self.assertNotIn("job", receipt)
            self.assertEqual(store.adapter.pending["request_id"], "still-running")
            self.assertEqual(store.adapter.connection_state(), "connected")
        finally:
            store.close(); server.shutdown(); server.server_close()


class HTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.store = Store(DemoAdapter(), "481529")
        cls.server = make_server(cls.store, port=0)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.store.close(); cls.server.shutdown(); cls.server.server_close()

    def post(self, path, data, headers=None):
        connection = HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=2)
        try:
            connection.request("POST", path, json.dumps(data), headers or {})
            response = connection.getresponse()
            return response.status, json.loads(response.read())
        finally:
            connection.close()

    def test_actual_loopback_post_connect_and_exchange(self):
        status, body = self.post("/v1/game/connect", {"code": "481529", "session": "http"})
        self.assertEqual(status, 200)
        status, body = self.post("/v1/game/exchange", {"token": body["token"], "session": "http", "events": []})
        self.assertEqual(status, 200)
        self.assertIn("commands", body)

    def test_bad_pairing_and_browser_origin_are_rejected(self):
        status, connected = self.post("/v1/game/connect", {"code": "481529", "session": "http"})
        self.assertEqual(status, 200)
        status, refused = self.post("/v1/game/connect", {"code": "000000", "session": "wrong"})
        self.assertEqual(status, 403)
        self.assertEqual(refused["reason"], "pairing_code_mismatch")
        status, _ = self.post("/v1/game/exchange", {"token": connected["token"], "session": "http", "events": []})
        self.assertEqual(status, 200)
        status, refused = self.post("/v1/game/connect", {}, {"Origin": "https://example.com"})
        self.assertEqual(status, 403)
        self.assertNotIn("reason", refused)


if __name__ == "__main__":
    unittest.main()

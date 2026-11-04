"""Actual helper turn loop with game receipts; no browser, microphone or live game."""
import json
import threading
import time
import unittest

from tools.companion_bridge.server import Store, BridgeError


class Model:
    def __init__(self, decide):
        self.contexts = []
        self.decide_fn = decide

    def decide(self, context):
        self.contexts.append(context)
        return self.decide_fn(context)


class MultiplayerTests(unittest.TestCase):
    def setUp(self):
        self.model = Model(lambda c: {})
        self.store = Store(self.model, "481529")
        self.token = self.store.connect({"code": "481529", "session": "multi", "input_protocol": 2})["token"]
        self.owner = {"userid": "owner", "handle": "e1", "name": "领队"}
        self.visitor = {"userid": "visitor", "handle": "e2", "name": "访客"}
        self.exchange(snapshot={"owner": self.owner, "leader": self.owner, "revision": 0})

    def tearDown(self):
        self.store.close()

    def exchange(self, events=(), **extra):
        return self.store.exchange({"token": self.token, "session": "multi", "events": list(events), **extra})

    def input(self, turn, speaker=None, can_work=True, **extra):
        speaker = speaker or self.owner
        return {"event_id": "event:" + turn, "kind": "player_input", "turn_id": turn,
                "text": "温蒂，" + ("捡活木" if can_work else "你好"), "speaker": speaker,
                "can_work": can_work, "world_control": {"admin": False}, **extra}

    def until(self, predicate):
        deadline = time.monotonic() + 3
        with self.store.condition:
            while not predicate():
                if time.monotonic() >= deadline:
                    self.fail("helper did not reach the expected state")
                self.store.condition.wait(.01)

    def complete(self, command, result=None, status="completed"):
        return self.exchange([{"event_id": command["request_id"] + ":" + status,
                               "request_id": command["request_id"], "action_id": "a:" + command["request_id"],
                               "skill": command["skill"], "status": status, "result": result or {}}])

    def test_assistant_text_waits_for_native_name_and_identity_validation(self):
        self.store.submit("温蒂，你好")
        request = self.exchange()["inputs"][0]
        self.assertEqual(self.model.contexts, [])
        self.exchange([self.input("native-1", input_id=request["id"])])
        self.until(lambda: not self.store.busy)
        self.assertFalse(self.exchange()["inputs"])
        self.assertEqual(len(self.model.contexts), 1)
        self.assertIn("native-1", self.exchange()["finished_inputs"])

    def test_rejected_unnamed_input_does_not_invoke_model_or_replace_a_plan(self):
        self.store.busy = True
        old_version = self.store.turn_version
        self.store.submit("你好")
        request = self.exchange()["inputs"][0]
        self.exchange([{"event_id": "reject-1", "kind": "input_rejected", "input_id": request["id"],
                        "reason": "companion_name_required"}])
        self.assertEqual(self.store.turn_version, old_version)
        self.assertTrue(self.store.busy)
        self.assertEqual(self.model.contexts, [])
        self.assertFalse(self.exchange()["inputs"])

    def test_batch_has_one_command_and_no_model_roundtrip_before_terminal_result(self):
        self.model.decide_fn = lambda c: {} if c["results"] else {"skill": "pickup_many", "arguments": {"filter": "livinglog"}}
        self.exchange([self.input("batch")])
        self.until(lambda: bool(self.store.commands))
        command = self.exchange()["commands"][0]
        self.assertEqual(command["skill"], "pickup_many")
        self.assertEqual(command["turn_id"], "batch")
        self.complete(command, status="running")
        self.assertEqual(len(self.model.contexts), 1)
        self.complete(command, {"count": 13, "targets": 3})
        self.until(lambda: not self.store.busy)
        self.assertEqual(len(self.model.contexts), 2)
        self.assertEqual(self.model.contexts[-1]["results"][0]["result"]["count"], 13)

    def test_other_players_chat_queues_without_replacing_the_leaders_active_batch(self):
        def decide(context):
            if context["snapshot"]["speaker"]["userid"] == "visitor":
                return {"text": "你好，访客。"}
            return {} if context["results"] else {"skill": "pickup_many", "arguments": {"filter": "livinglog"}}
        self.model.decide_fn = decide
        self.exchange([self.input("leader-batch")])
        self.until(lambda: bool(self.store.commands))
        command = self.exchange()["commands"][0]
        version = self.store.turn_version
        event = self.input("visitor-chat", self.visitor, False)
        self.exchange([event]); self.exchange([event])
        self.assertEqual(self.store.turn_version, version)
        self.assertEqual(len(self.store.chat_queue), 1)
        self.assertEqual(self.exchange()["commands"][0]["request_id"], command["request_id"])
        self.complete(command, {"count": 6})
        self.until(lambda: any(c["skill"] == "say" for c in self.store.commands.values()))
        say = next(c for c in self.exchange()["commands"] if c["skill"] == "say")
        self.assertEqual(say["turn_id"], "visitor-chat")
        visitor_context = self.model.contexts[-1]
        self.assertEqual(visitor_context["snapshot"]["owner"], self.visitor)
        self.assertEqual(visitor_context["snapshot"]["transport_owner"], self.owner)
        self.assertFalse(visitor_context["snapshot"]["can_work"])
        self.assertNotIn("craft", {t["name"] for t in visitor_context["tools"]})
        self.complete(say)
        self.until(lambda: not self.store.busy)
        self.assertEqual(len(self.store.history), 2)

    def test_free_companion_accepts_work_from_a_non_owner_and_targets_the_speaker(self):
        self.exchange(snapshot={"owner": self.owner, "leader": None, "revision": 0})
        self.model.decide_fn = lambda c: {} if c["results"] else {"skill": "follow", "arguments": {}}
        self.exchange([self.input("free-visitor", self.visitor)])
        self.until(lambda: bool(self.store.commands))
        command = self.exchange()["commands"][0]
        self.assertEqual(command["turn_id"], "free-visitor")
        self.assertTrue(self.model.contexts[-1]["snapshot"]["can_work"])
        self.assertEqual(self.model.contexts[-1]["snapshot"]["owner"]["handle"], "e2")
        self.complete(command)
        self.until(lambda: not self.store.busy)

    def test_a_nonleader_input_replaces_unsent_ambient_chat_instead_of_waiting_for_it(self):
        started, release = threading.Event(), threading.Event()
        def decide(context):
            if context["input_kind"] == "ambient":
                started.set(); release.wait(2)
                return {"text": "已经过时的闲聊"}
            return {"text": "你好。"}
        self.model.decide_fn = decide
        self.store.submit("", source="ambient")
        self.assertTrue(started.wait(1))
        version = self.store.turn_version
        self.exchange([self.input("interrupt-idle", self.visitor, False)])
        self.assertGreater(self.store.turn_version, version)
        self.assertEqual(len(self.store.chat_queue), 0)
        release.set()
        self.until(lambda: bool(self.store.commands))
        say = self.exchange()["commands"][0]
        self.assertEqual(say["arguments"]["text"], "你好。")
        self.complete(say)
        self.until(lambda: not self.store.busy)

    def test_nonleader_cannot_stop_or_replace_a_plan_through_local_debug_controls(self):
        self.exchange(snapshot={"owner": self.visitor, "leader": self.owner, "revision": 0})
        self.store.busy = True
        version = self.store.turn_version
        with self.assertRaises(BridgeError):
            self.store.stop_action()
        with self.assertRaises(BridgeError):
            self.store.direct_call("craft", {"recipe": "spear"})
        self.assertTrue(self.store.busy)
        self.assertEqual(self.store.turn_version, version)

    def test_unauthorized_work_decision_returns_feedback_to_model_for_an_in_game_reply(self):
        self.model.decide_fn = lambda c: {"text": "工作安排请让领队来说。"} if c["results"] else {"skill": "craft", "arguments": {"recipe": "spear"}}
        self.exchange([self.input("visitor-work", self.visitor, False)])
        self.until(lambda: bool(self.store.commands))
        command = self.exchange()["commands"][0]
        self.assertEqual(command["skill"], "say")
        self.assertEqual(self.model.contexts[-1]["results"][0]["reason"], "leader_only_work")
        self.complete(command)
        self.until(lambda: not self.store.busy)

    def test_remote_reply_size_stays_bounded_without_losing_queued_commands(self):
        for n in range(4):
            self.store.enqueue("say", {"text": "字" * 1100})
        for n in range(8):
            self.store.submit("温蒂" + "字" * 390)
        for n in range(64):
            self.store.finished_inputs.append("f" * 128 + str(n))
        packet = self.exchange()
        self.assertLessEqual(len(json.dumps(packet, ensure_ascii=False).encode()), 28000)
        self.assertEqual(len(self.store.commands), 4)
        self.assertEqual(len(self.store.inputs), 8)


if __name__ == "__main__":
    unittest.main()

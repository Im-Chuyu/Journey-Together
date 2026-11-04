"""Check generated prompt format and persona selection; no model or live service."""
import json
import re
import unittest
from tools.companion_bridge.model import prompt
from tools.companion_bridge.personas import instruction


class PromptTests(unittest.TestCase):
    def test_task_notes_and_object_bindings_survive_prompt_without_becoming_actions(self):
        from tools.companion_bridge.model import parse_decision
        plan = {"goal": "换包", "bindings": {"old_bag": "e1", "new_bag": "e2"},
                "remaining": ["旧包留给玩家", "穿新包"]}
        decision = parse_decision(json.dumps({"request_id": "nonce", "skill": "drop",
            "arguments": {"item": "e1"}, "plan": plan}), "nonce")
        self.assertEqual(decision["plan"], plan)
        rendered = prompt({"task_plan": plan}, "nonce")
        data = json.loads(rendered.split("本次请求数据（JSON）：\n", 1)[1].split("\n\n请输出", 1)[0])
        self.assertEqual(data["task_plan"]["bindings"]["old_bag"], "e1")
        with self.assertRaises(ValueError):
            parse_decision(json.dumps({"request_id": "nonce", "plan": {"code": "bad"}}), "nonce")

    def test_base_and_container_page_metadata_reach_both_prompt_transports(self):
        from tools.companion_bridge.model import context_data
        snapshot = {"location": {"tile": {"name": "MARSH"}, "region": {"id": "marsh", "source": "topology"}},
                    "world": {"kind": "surface", "prefab": "forest", "shard_id": "1"},
                    "base": {"known": True, "position": {"x": 1, "z": 2}, "radius": 32,
                             "distance": 3, "at_base": True}, "home": {"known": True, "mode": "base"},
                    "environment": {"containers": [{"handle": "e1", "prefab": "icebox"}], "limited": False}}
        result = {"skill": "observe", "result": {"entities": [], "matched": 41, "returned": 40, "next_offset": 40}}
        context = {"snapshot": snapshot, "results": [result]}
        self.assertEqual(context_data(context)["snapshot"], snapshot)
        rendered = prompt(context, "nonce")
        data = json.loads(rendered.split("本次请求数据（JSON）：\n", 1)[1].split("\n\n请输出", 1)[0])
        self.assertEqual(data["snapshot"], snapshot)
        self.assertEqual(data["results"][0]["result"]["next_offset"], 40)

    def test_identity_stats_world_surroundings_precede_execution_metadata(self):
        snapshot = {"action": {"skill": "craft"}, "inventory": [], "environment": {"items": []},
                    "world": {"day": 10}, "moisture": 23, "health": 80, "hunger": 90,
                    "character": {"id": "wendy"}, "name": "妹妹", "can_work": False}
        value = prompt({"snapshot": snapshot, "results": [{"reason": "placement_blocked"}]}, "nonce")
        data = json.loads(value.split("本次请求数据（JSON）：\n", 1)[1].split("\n\n请输出", 1)[0])
        self.assertEqual(data["snapshot"], snapshot)
        keys = list(data["snapshot"])
        self.assertEqual(keys[:2], ["name", "character"])
        self.assertLess(keys.index("moisture"), keys.index("world"))
        self.assertLess(keys.index("environment"), keys.index("action"))
        self.assertEqual(data["results"][0]["reason"], "placement_blocked")

    def test_generated_instructions_are_plain_text_and_request_data_stays_json(self):
        context = {"utterance": "你现在叫什么", "snapshot": {"name": "妹妹", "custom_name": "妹妹",
                   "renamed": True, "character": {"id": "wendy"}}, "tools": [], "results": []}
        value = prompt(context, "current-request")
        self.assertIsNone(re.search(r"(?m)^\s*(?:#{1,6}\s|\|.*\||[-*+]\s|\d+\.\s|```)", value))
        data = json.loads(value.split("本次请求数据（JSON）：\n", 1)[1].split("\n\n请输出", 1)[0])
        self.assertEqual(data["request_id"], "current-request")
        self.assertEqual(data["snapshot"]["character"]["id"], "wendy")

    def test_execution_summary_does_not_count_recipe_estimates_as_finished_items(self):
        context = {"results": [
            {"skill": "query_recipe", "status": "completed", "result": {"recipe": "cookpot", "produced": 2}},
            {"skill": "execute_sequence", "status": "failed", "result": {"steps": [
                {"skill": "craft", "status": "completed", "result": {"recipe": "cookpot", "produced": 1}},
                {"skill": "craft", "status": "failed", "reason": "missing_materials"}]}}]}
        value = prompt(context, "nonce")
        data = json.loads(value.split("本次请求数据（JSON）：\n", 1)[1].split("\n\n请输出", 1)[0])
        self.assertEqual(data["execution"]["completed_actions"], [{"skill": "craft", "recipe": "cookpot", "produced": 1}])

    def test_ambient_prompt_invites_data_based_chat_and_ignores_old_empty_turns(self):
        value = prompt({"input_kind": "ambient", "utterance": "", "snapshot": {"world": {"season": "winter"}},
                        "history": [{"kind": "ambient", "assistant": ""},
                                    {"kind": "user", "user": "你好", "assistant": "我在"}]}, "ambient-request")
        self.assertIn("主动闲聊", value)
        self.assertIn("不需要玩家先提问", value)
        data = json.loads(value.split("本次请求数据（JSON）：\n", 1)[1].split("\n\n请输出", 1)[0])
        self.assertEqual(data["input_kind"], "ambient")
        self.assertEqual(data["snapshot"]["world"]["season"], "winter")
        self.assertEqual(len(data["history"]), 1)

    def test_renaming_changes_the_persona_in_the_next_prompt(self):
        normal = instruction({"name": "温蒂", "renamed": False, "character": {"id": "wendy"}})
        renamed = instruction({"name": "妹妹", "custom_name": "妹妹", "renamed": True, "character": {"id": "wendy"}})
        self.assertIn("安静、敏感", normal)
        self.assertIn("妹妹", renamed)
        self.assertNotIn("安静、敏感、略带忧伤", renamed)
        self.assertIn("实际实体", renamed)
        self.assertNotEqual(normal, renamed)

    def test_mod_characters_use_the_name_instead_of_the_vanilla_voice(self):
        value = instruction({"name": "机械小七", "character": {"id": "custom_robot", "is_mod": True}})
        self.assertIn("机械小七", value)
        self.assertNotIn("WX-78：", value)
        value = instruction({"name": "妹妹", "character": {"id": "wendy", "is_mod": True}})
        self.assertNotIn("安静、敏感、略带忧伤", value)


if __name__ == "__main__":
    unittest.main()

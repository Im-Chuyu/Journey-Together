"""Copy outside the mod, implement your provider, then pass --adapter <file>.

context contains utterance, current authoritative snapshot, tools, results,
and a short history. Return ONE skill invocation and/or text on each call.
input_kind is user or ambient; ambient may only return a short chat line or {}.
snapshot includes actual character, world/environment, revision and pending task.
Optionally implement cancel_pending() to interrupt a superseded network request.
After the game reports its result, decide is called again with results updated.
Return just text (or {}) to finish the turn. A chat-only turn needs no skill.
Keep model credentials outside the public mod; this file contains no API client.
"""


class UserModelAdapter:
    label = "我的模型"

    def decide(self, context):
        # 1. Send your system prompt, context["utterance"], snapshot and results.
        # 2. Register context["tools"] in your provider's tool-calling format.
        # 3. Convert ONE returned tool call to:
        #    {"skill": "observe", "arguments": {"scope": "structures"}}
        #    A user-facing reply may also be supplied as {"text": "..."}.
        # 4. Tool success/failure comes from the game, not the model's claims.
        raise NotImplementedError("请在本地适配器中接入你选择的模型")


def create_adapter():
    return UserModelAdapter()

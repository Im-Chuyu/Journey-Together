"""Authenticated loopback transport and an adapter-neutral action/feedback loop."""
from collections import OrderedDict, deque
from concurrent.futures import ThreadPoolExecutor
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from itertools import count
import json
import queue
import secrets
import threading
import time

from .capabilities import NAMES, TOOLS, compact_arguments
from .diagnostics import LOG
from .settings import DEFAULT_CODE

PHYSICAL = {"move_to", "pickup", "drop", "transfer", "equip", "unequip", "craft", "work", "eat", "cook", "use_item", "interact", "engage", "harvest", "character_skill", "pickup_many", "work_many", "perform_action", "execute_sequence", "dismount", "emote", "revive"}
PUBLIC = {"query_batch", "say", "observe", "query_recipe", "query_sites", "query_actions", "get_capabilities", "get_action_status",
          "save_game", "rollback_game", "pause_game", "kick_player", "ban_player"}
AMBIENT = {"say", "observe", "query_actions", "get_capabilities", "emote", "move_to", "equip", "unequip", "interact"}
TERMINAL = {"completed", "failed", "cancelled", "interrupted"}
CONNECTION_TIMEOUT = 20


class BridgeError(Exception):
    pass


class PairingCodeMismatch(BridgeError):
    pass


class PlanCancelled(BridgeError):
    pass


class Store:
    def __init__(self, adapter, code=None):
        self.adapter = adapter
        self.code = code or DEFAULT_CODE
        self.client_token = secrets.token_urlsafe(24)
        self.token = ""
        self.session = None
        self.connected = False
        self.last_seen = 0
        self.snapshot = {}
        self.commands = OrderedDict()
        self.results = OrderedDict()
        self.events_seen = deque(maxlen=256)
        self.messages = queue.Queue(maxsize=200)
        self.history = deque(maxlen=12)
        self.task_memory = OrderedDict()
        self.condition = threading.Condition()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="companion-plan")
        self.busy = False
        self.stopped = False
        self.current_action = None
        self.playback = OrderedDict()
        self.turn_version = 0
        self.plan_version = None
        self.pending_future = None
        self.last_user_at = 0
        self.input_protocol = 1
        self.inputs = OrderedDict()
        self.chat_queue = deque()
        self.finished_inputs = deque(maxlen=64)
        self.input_seen = deque(maxlen=128)
        self.current_input = None
        self.turn_source = None
        self.safety_signature = None

    def notify(self, kind, **data):
        record = {"kind": kind, **data}
        try:
            self.messages.put_nowait(record)
        except queue.Full:
            try:
                self.messages.get_nowait()
            except queue.Empty:
                pass
            self.messages.put_nowait(record)

    def connect(self, data):
        code = data.get("code")
        session = data.get("session")
        if not isinstance(code, str) or not code.isascii() or not hmac.compare_digest(code, self.code):
            raise PairingCodeMismatch("配对码不正确")
        if not isinstance(session, str) or not 1 <= len(session) <= 128:
            raise BridgeError("会话格式不正确")
        with self.condition:
            if self.is_connected():
                if self.session == session:
                    return {"token": self.token, "protocol": 1}
                raise BridgeError("已有游戏连接，请先断开")
            self._invalidate_locked()
            self.token, self.session = secrets.token_urlsafe(32), session
            self.connected, self.last_seen = True, time.monotonic()
            self.safety_signature = None
            self.input_protocol = 2 if data.get("input_protocol") == 2 else 1
            self.inputs.clear(); self.chat_queue.clear(); self.finished_inputs.clear(); self.input_seen.clear()
            self.commands.clear(); self.results.clear(); self.events_seen.clear(); self.playback.clear(); self.snapshot = {}
            self.task_memory.clear()
            self.condition.notify_all()
        self.notify("connected", companion=data.get("companion"), owner=data.get("owner"))
        LOG.info("game_connected")
        return {"token": self.token, "protocol": 1}

    def exchange(self, data):
        with self.condition:
            token = data.get("token")
            if not self.is_connected() or not isinstance(token, str) or not token.isascii() or not hmac.compare_digest(token, self.token) or data.get("session") != self.session:
                raise BridgeError("会话已失效")
            self.last_seen = time.monotonic()
            snapshot = data.get("snapshot")
            if isinstance(snapshot, dict):
                self.snapshot = snapshot
                known = {"ghost", "leader_dead", "dead", "low_hunger", "darkness", "temperature",
                         "hurt_evade", "recent_hurt", "threat", "survival_recheck"}
                flags = snapshot.get("blockers", [])
                flags = sorted({flag for flag in flags if isinstance(flag, str) and flag in known}) if isinstance(flags, list) else []
                health_kind=snapshot.get("health_kind")
                health_kind=health_kind if health_kind in ("health", "remaining_lifespan") else "unknown"
                signature = (snapshot.get("emergency") is True, tuple(flags), health_kind)
                if signature != self.safety_signature:
                    self.safety_signature = signature
                    LOG.info("game_safety emergency=%s blockers=%s health_kind=%s", signature[0], ",".join(flags) or "none",health_kind)
            ambient_due = False
            ack = []
            events = data.get("events", [])
            if not isinstance(events, list) or len(events) > 64:
                raise BridgeError("事件格式不正确")
            for event in events:
                if not isinstance(event, dict) or not isinstance(event.get("event_id"), str):
                    continue
                event_id = event["event_id"]
                ack.append(event_id)
                if event_id in self.events_seen:
                    continue
                self.events_seen.append(event_id)
                if event.get("kind") in {"player_input", "input_rejected"}:
                    pending = self.inputs.pop(event.get("input_id"), None)
                    if event["kind"] == "input_rejected":
                        self.notify("input_rejected", reason=event.get("reason"), text=pending["text"] if pending else "",
                                    input_id=event.get("input_id"))
                    else:
                        self._receive_input_locked(event)
                    continue
                if event.get("kind") == "control_changed":
                    self.snapshot["revision"] = event.get("revision", self.snapshot.get("revision", 0))
                    self._invalidate_locked()
                    self.notify("task_replaced", reason="manual_command")
                    continue
                if event.get("kind") == "input_broadcast_failed":
                    self.notify("input_broadcast_failed", input_id=event.get("input_id"))
                    continue
                if event.get("kind") == "ambient_context":
                    ambient_due = True
                    continue
                request_id = event.get("request_id")
                if request_id in self.commands:
                    del self.commands[request_id]
                if isinstance(request_id, str):
                    previous = self.results.get(request_id)
                    current_receipt = previous is None or previous.get("status") not in TERMINAL
                    if current_receipt:
                        self.results[request_id] = event
                    while len(self.results) > 80:
                        self.results.popitem(last=False)
                else:
                    current_receipt = False
                if current_receipt and event.get("status") in {"accepted", "running"}:
                    self.current_action = event.get("action_id")
                if current_receipt and event.get("status") in TERMINAL and event.get("action_id") == self.current_action:
                    self.current_action = None
                if current_receipt and event.get("status") in TERMINAL:
                    name = event.get("skill")
                    reason=event.get("reason")
                    safe_reason=reason if isinstance(reason,str) and len(reason)<=80 and all(c.isascii() and (c.isalnum() or c in "_:") for c in reason) else "none"
                    LOG.info("game_action_result skill=%s status=%s reason=%s", name if isinstance(name, str) and name in NAMES else "other", event["status"],safe_reason)
                self.notify("result", event=event)
            if data.get("closing"):
                self.connected = False
                self.current_action = None
                self.commands.clear()
                self.inputs.clear(); self.chat_queue.clear()
                self._invalidate_locked()
                self.notify("disconnected", reason=data["closing"])
                known_reason = data["closing"] if isinstance(data["closing"], str) and data["closing"] in {
                    "manual_command", "user_disconnected", "bridge_unavailable", "owner_or_body_changed",
                    "onremove", "death", "ms_becameghost", "assistant_stopped"} else "other"
                LOG.info("game_closed reason=%s", known_reason)
            commands = list(self.commands.values())[:4] if self.connected else []
            self.condition.notify_all()
            if ambient_due:
                self.maybe_ambient()
            plan = {"id": str(self.plan_version), "active": self.busy and self.plan_version == self.turn_version,
                    "revision": self.snapshot.get("revision", 0)} if self.plan_version is not None else None
            packet = {"ack": ack, "commands": commands, "closed": self.stopped, "playback": list(self.playback.values()), "plan": plan,
                      "inputs": list(self.inputs.values())[:8] if self.connected else [], "finished_inputs": list(self.finished_inputs)}
            # Stay below the remote client's 30 KB HTTP reply limit. Trim only
            # retransmitted arrays; the original queues remain until receipts.
            for key in ("commands", "inputs", "playback", "finished_inputs"):
                while packet[key] and len(json.dumps(packet, ensure_ascii=False).encode()) > 28000:
                    packet[key].pop()
            return packet

    def is_connected(self):
        with self.condition:
            if self.connected and time.monotonic() - self.last_seen > CONNECTION_TIMEOUT:
                self.connected = False
                self.current_action = None
                self.inputs.clear()
                self.chat_queue.clear()
                self.playback.clear()
                self._invalidate_locked()
                self.notify("disconnected", reason="connection_timeout")
                LOG.info("game_closed reason=connection_timeout")
            return self.connected and not self.stopped

    def speech(self, action_id, status):
        if not isinstance(action_id, str) or status not in {"queued", "playing", "completed", "failed", "disabled"}:
            return
        with self.condition:
            self.playback[action_id] = {"action_id": action_id, "status": status}
            while len(self.playback) > 40:
                self.playback.popitem(last=False)

    def enqueue(self, skill, arguments, expected_session=None, version=None, revision=None, source="user", turn_id=None):
        if not isinstance(skill, str) or skill not in NAMES or not isinstance(arguments, dict):
            raise BridgeError("未知动作或参数格式不正确")
        arguments = compact_arguments(arguments)
        try:
            encoded = json.dumps(arguments, ensure_ascii=False, allow_nan=False).encode()
        except (TypeError, ValueError) as error:
            raise BridgeError("动作参数必须是有效JSON数值与数据") from error
        if len(encoded) > (10000 if skill == "execute_sequence" else 7000 if skill == "query_batch" else 3500):
            raise BridgeError("动作参数太长")
        with self.condition:
            if version is not None and version != self.turn_version:
                raise PlanCancelled("新指令已接替旧规划")
            if expected_session is not None and expected_session != self.session:
                raise BridgeError("游戏会话已改变，旧模型回复已丢弃")
            if not self.is_connected():
                raise BridgeError("游戏尚未连接或连接已失效")
            if len(self.commands) >= 16:
                raise BridgeError("待处理动作过多")
            request_id = secrets.token_hex(12)
            plan_id = None
            instant_control = skill == "character_skill" and isinstance(arguments.get("ability"), str) and arguments["ability"] in {"abigail_aggressive", "abigail_defensive", "abigail_recall"}
            if version is not None and source == "user" and skill in PHYSICAL and not instant_control:
                self.plan_version = version
                plan_id = str(version)
            self.commands[request_id] = {"request_id": request_id, "skill": skill, "arguments": arguments,
                                         "revision": self.snapshot.get("revision", 0) if revision is None else revision, "source": source,
                                         "plan_id": plan_id, "turn_id": turn_id}
            self.condition.notify_all()
        self.notify("call", skill=skill, arguments=arguments, request_id=request_id)
        LOG.info("game_action_queued skill=%s", skill)
        return request_id

    def wait(self, request_id, timeout=320, accept_running=False, version=None):
        deadline = time.monotonic() + timeout
        with self.condition:
            while True:
                if version is not None and version != self.turn_version:
                    raise PlanCancelled("新指令已接替旧规划")
                result = self.results.get(request_id)
                if result is not None and (result.get("status") in TERMINAL
                                           or accept_running and result.get("status") in {"accepted", "running"}):
                    return result
                if not self.is_connected():
                    raise BridgeError("游戏连接中断，等待重新配对")
                if time.monotonic() >= deadline:
                    raise BridgeError("等待动作结果超时；请检查游戏状态")
                self.condition.wait(.5)

    def _invalidate_locked(self):
        self.turn_version += 1
        self.busy = False
        self.turn_source = None
        self.commands.clear()
        if self.current_input:
            self.finished_inputs.append(self.current_input)
            self.current_input = None
        if self.pending_future is not None:
            self.pending_future.cancel()
        cancel = getattr(self.adapter, "cancel_pending", None)
        if callable(cancel):
            cancel()
        self.condition.notify_all()

    def submit(self, text, source="user", *, broadcast=False, whisper=False):
        if not isinstance(text, str) or source != "ambient" and not text.strip() or len(text.encode()) > 1200:
            raise BridgeError("输入文字为空或过长")
        if type(broadcast) is not bool:
            raise BridgeError("公屏同步设置必须为布尔值")
        if type(whisper) is not bool:
            raise BridgeError("附近私聊设置必须为布尔值")
        if broadcast:
            text = "".join(" " if ord(c) < 32 or ord(c) == 127 else c for c in text).strip()
            if not text or len(text) > 150:
                raise BridgeError("同步到游戏聊天的消息最多150个字符；可缩短内容或关闭聊天同步")
        with self.condition:
            if not self.is_connected():
                raise BridgeError("请先在游戏中配对连接")
            if source == "user" and self.input_protocol >= 2:
                if len(self.inputs) >= 16:
                    raise BridgeError("待发送消息过多，请等待游戏接收")
                input_id = secrets.token_hex(12)
                self.inputs[input_id] = {"id": input_id, "text": text.strip(), "broadcast": broadcast, "whisper": whisper}
                self.condition.notify_all()
                return input_id
            if broadcast or whisper:
                raise BridgeError("游戏聊天同步需要更新游戏模组并重新连接")
            self._start_turn_locked(text.strip(), source)

    def _receive_input_locked(self, event):
        turn_id, text, speaker = event.get("turn_id"), event.get("text"), event.get("speaker")
        if not isinstance(turn_id, str) or not isinstance(text, str) or not isinstance(speaker, dict) or turn_id in self.input_seen:
            return
        self.input_seen.append(turn_id)
        self.last_user_at = time.monotonic()
        self.notify("user", text=text, speaker=speaker.get("name"), input_id=event.get("input_id"))
        if self.busy and self.turn_source == "user" and not event.get("can_work"):
            if len(self.chat_queue) >= 16:
                self.finished_inputs.append(turn_id)
                self.notify("error", message="聊天队列已满，请稍后再说")
            else:
                self.chat_queue.append(event)
            return
        self._start_turn_locked(text, "user", event)

    def _start_turn_locked(self, text, source, input_event=None):
        # Caller holds the condition; one browser/model request may run at a time.
        self._invalidate_locked()
        self.busy = True
        self.turn_source = source
        self.current_input = input_event.get("turn_id") if input_event else None
        session, version = self.session, self.turn_version
        if source == "user":
            self.last_user_at = time.monotonic()
            if input_event is None:
                self.notify("user", text=text)
        self.pending_future = self.executor.submit(self._turn, text, session, version, source, input_event)

    def maybe_ambient(self):
        with self.condition:
            if not getattr(self.adapter, "ambient_enabled", True):
                return False
            if not self.is_connected() or self.busy or self.commands or self.inputs or self.chat_queue or self.current_action or time.monotonic() - self.last_user_at < 60:
                return False
            if any(self.snapshot.get(key) for key in ("emergency", "action", "pending", "busy", "manual_task", "planning")):
                return False
            check = getattr(self.adapter, "connection_state", None)
            if callable(check) and check() == "disconnected":
                return False
            LOG.info("ambient_started")
            self.submit("", source="ambient")
            return True

    def _turn(self, text, session, version, source, input_event=None):
        results = deque(maxlen=32)
        task_plan = {}
        memory_key = None
        turn_id = input_event.get("turn_id") if input_event else None
        model_turn_id = turn_id or secrets.token_hex(12)
        speaker_id = (input_event["speaker"].get("userid") if input_event else None)
        try:
            for iteration in count():
                if source == "ambient" and iteration >= 4:
                    return
                with self.condition:
                    if not self.connected or self.session != session or version != self.turn_version:
                        raise PlanCancelled("控制意图已改变，停止旧规划")
                    snapshot = json.loads(json.dumps(self.snapshot))
                    current_owner = snapshot.get("owner") or {}
                    memory_key = speaker_id if input_event else current_owner.get("userid") or "local"
                    can_work = True
                    if input_event:
                        speaker = dict(input_event["speaker"])
                        leader = snapshot.get("leader") or {}
                        if speaker_id and speaker.get("same_shard") is not False:
                            for current in (current_owner, leader):
                                if current.get("userid") == speaker_id:
                                    speaker.update(current)
                                    break
                        snapshot["transport_owner"], snapshot["owner"] = snapshot.get("owner"), speaker
                        snapshot["speaker"] = speaker
                        if speaker.get("userid") != current_owner.get("userid"):
                            snapshot["world_control"] = input_event.get("world_control", {})
                        leader = snapshot.get("leader")
                        can_work = not leader or leader.get("userid") == speaker.get("userid")
                        snapshot["can_work"] = can_work
                    snapshot["chat_channel"] = "nearby" if input_event and input_event.get("whisper") is True else "public"
                    if source == "ambient":
                        leader = snapshot.get("leader") or {}
                        can_work = not leader or leader.get("userid") == current_owner.get("userid")
                        snapshot["can_work"] = can_work
                    allowed = (NAMES if can_work else PUBLIC) if source == "user" else AMBIENT if can_work else AMBIENT & PUBLIC
                    context = {"utterance": text, "snapshot": snapshot,
                               "turn_id": model_turn_id, "turn_phase": "continuation" if iteration else "input",
                               "results": list(results), "results_limited": iteration > results.maxlen,
                               "history": list(self.history),
                               "tools": [tool for tool in TOOLS if tool["name"] in allowed],
                               "input_kind": source, "task_plan": json.loads(json.dumps(task_plan))}
                    if source == "user" and memory_key is not None:
                        context["last_task"] = self.task_memory.get(memory_key)
                    revision = self.snapshot.get("revision", 0)
                try:
                    decision = self.adapter.decide(context)
                except (ValueError, RuntimeError) as error:
                    raise BridgeError(str(error)) from error
                with self.condition:
                    if version != self.turn_version:
                        raise PlanCancelled("新指令已接替旧规划")
                if not isinstance(decision, dict):
                    raise BridgeError("适配器返回值必须是对象")
                if "plan" in decision:
                    from .model import validate_plan
                    task_plan = validate_plan(decision["plan"])
                if decision.get("skill") is not None and decision["skill"] not in allowed:
                    results.append({"skill": decision["skill"], "status": "failed",
                                    "reason": "ambient_action_not_allowed" if source == "ambient" else "leader_only_work"})
                    continue
                reply = decision.get("text")
                speak = True
                if decision.get("skill") == "say":
                    arguments = decision.get("arguments", {})
                    if not isinstance(arguments, dict):
                        raise BridgeError("说话参数必须是对象")
                    # A speech-only response ends the turn, just like text.
                    # Do not feed its receipt back as another planning round.
                    # Prefer the explicit say payload over optional narration.
                    reply = arguments.get("text", reply)
                    speak = arguments.get("speak", True)
                    if not isinstance(reply, str) or not isinstance(speak, bool):
                        raise BridgeError("说话文字或语音开关格式不正确")
                    decision = {"text": reply}
                    LOG.info("model_say_terminal")
                if reply:
                    if not isinstance(reply, str) or len(reply.encode()) > 600:
                        raise BridgeError("模型回复超过 600 UTF-8 字节")
                    spoken = self.wait(self.enqueue("say", {"text": reply, "speak": speak}, expected_session=session,
                        version=version, revision=revision, source=source, turn_id=turn_id), version=version)
                    if spoken.get("status") == "completed":
                        self.notify("assistant", text=reply, action_id=spoken.get("action_id"))
                skill = decision.get("skill")
                if skill is None:
                    if source == "ambient":
                        LOG.info("ambient_finished outcome=%s", "spoken" if reply and spoken.get("status") == "completed" else "silent")
                    if source != "ambient" or reply:
                        self.history.append({"user": text, "assistant": reply or "", "kind": source,
                                             "speaker": input_event.get("speaker") if input_event else None})
                    return
                result = self.wait(self.enqueue(skill, decision.get("arguments", {}), expected_session=session,
                    version=version, revision=revision, source=source, turn_id=turn_id), version=version,
                    timeout=650 if skill in {"execute_sequence", "move_to"} else 320)
                if skill != "execute_sequence":
                    result = {**result, "arguments": compact_arguments(decision.get("arguments", {}))}
                results.append(result)
                world_skills = {"save_game", "rollback_game", "pause_game", "kick_player", "ban_player"}
                details = result.get("result") or {}
                if skill in world_skills and (details.get("needs_reason") or result.get("reason") in {
                        "reason_requires_next_player_message", "approval_expired", "approval_mismatch"}):
                    # The required next player message cannot be manufactured by
                    # another model iteration in this same turn.
                    question = ("这项确认已失效，请重新提出操作要求。" if result.get("reason") in {"approval_expired", "approval_mismatch"}
                                else "请说明这次世界操作的原因，我会根据你的下一条回答判断。")
                    self.wait(self.enqueue("say", {"text": question, "speak": True}, expected_session=session,
                        version=version, revision=revision, source=source, turn_id=turn_id), version=version)
                    self.notify("assistant", text=question)
                    self.history.append({"user": text, "assistant": question, "kind": source,
                                         "speaker": input_event.get("speaker") if input_event else None})
                    return
                if skill in world_skills and details.get("rejected"):
                    return
                if skill in world_skills and result.get("status") == "completed" and details.get("requested") is True:
                    self.history.append({"user": text, "assistant": "这次世界操作已安排。", "kind": source,
                                         "operation": skill, "requested": True,
                                         "speaker": input_event.get("speaker") if input_event else None})
                    # A restart/pause may stop the next receipt. Do not replay
                    # the world operation or queue speech into the old world.
                    return
                if result.get("reason") in {"superseded", "manual_command", "leader_only_work", "speaker_left", "invalid_input_context", "speaker_permission_changed"}:
                    return
        except PlanCancelled:
            pass
        except Exception as error:
            with self.condition:
                if version == self.turn_version:
                    LOG.warning("turn_failed category=%s", type(error).__name__)
                    self.notify("error", message=str(error) if isinstance(error, BridgeError) else type(error).__name__)
        finally:
            with self.condition:
                if version == self.turn_version and source == "user" and results and memory_key is not None:
                    from .model import execution_summary
                    effects = execution_summary(results, keep_arguments=False)["completed_actions"]
                    last = results[-1]
                    if effects or task_plan or last.get("status") == "failed" and last.get("skill") in NAMES - PUBLIC:
                        self.task_memory[memory_key] = {
                            "utterance": text,
                            "plan": {k: v for k, v in task_plan.items() if k != "bindings"},
                            "effects": effects[-12:],
                            "last_receipt": {k: last[k] for k in ("skill", "status", "reason") if k in last},
                        }
                        self.task_memory.move_to_end(memory_key)
                        if len(self.task_memory) > 12:
                            self.task_memory.popitem(last=False)
                if turn_id and turn_id not in self.finished_inputs:
                    self.finished_inputs.append(turn_id)
                if version == self.turn_version:
                    self.busy = False
                    self.turn_source = None
                    self.current_input = None
                    self.notify("turn_done")
                    if self.connected and self.chat_queue:
                        event = self.chat_queue.popleft()
                        self._start_turn_locked(event["text"], "user", event)

    def stop_action(self):
        with self.condition:
            if not self._local_can_work_locked():
                raise BridgeError("伙伴正在跟随别人，只有领队可停止任务")
            action_id = self.current_action
            had_plan = self.busy
            manual_task = self.snapshot.get("manual_task")
            self._invalidate_locked()
        if action_id:
            return self.enqueue("cancel", {"action_id": action_id}, source="direct")
        if manual_task:
            return self.enqueue("follow", {}, source="direct")
        if had_plan:
            return None
        raise BridgeError("当前没有正在执行的接口动作")

    def direct_call(self, skill, arguments):
        if not isinstance(skill, str) or skill not in NAMES or not isinstance(arguments, dict):
            raise BridgeError("未知动作或参数格式不正确")
        with self.condition:
            if skill not in PUBLIC and not self._local_can_work_locked():
                raise BridgeError("伙伴正在跟随别人，只有领队可安排工作")
            if skill not in PUBLIC:
                self._invalidate_locked()
            self.last_user_at = time.monotonic()
        return self.enqueue(skill, arguments, source="direct")

    def _local_can_work_locked(self):
        if self.input_protocol < 2:
            return True
        owner, leader = self.snapshot.get("owner"), self.snapshot.get("leader")
        return isinstance(owner, dict) and (not leader or leader.get("userid") == owner.get("userid"))

    def update_pairing(self, code, web_code, voice_hotkey=None, voice_preferences=None):
        from .settings import load, save
        preferences = load()
        preferences.update(pair_code=code, web_code=web_code)
        if voice_preferences is not None:
            preferences.update({key: voice_preferences[key] for key in ("asr_backend", "tts_voice", "tts_rate", "tts_volume") if key in voice_preferences})
        if voice_hotkey is not None:
            preferences["voice_hotkey"] = voice_hotkey
        save(preferences)
        with self.condition:
            self.code = code
            if hasattr(self.adapter, "secret") and self.adapter.secret != web_code:
                self._invalidate_locked()
                self.adapter.set_secret(web_code)

    def close(self):
        with self.condition:
            if self.stopped:
                return
            self.stopped = True
            self.connected = False
            self.inputs.clear(); self.chat_queue.clear()
            self._invalidate_locked()
            self.condition.notify_all()
        self.executor.shutdown(wait=False, cancel_futures=True)
        close = getattr(self.adapter, "close", None)
        if callable(close):
            close()


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            state = {"protocol": "my_friend_body/1", "connected": self.server.store.is_connected()}
            diagnostics = getattr(self.server.store.adapter, "diagnostics", None)
            if callable(diagnostics):
                state[getattr(self.server.store.adapter, "diagnostics_kind", "web")] = diagnostics()
            self.reply(200, state)
        else:
            self.reply(404, {"error": "not_found"})

    def do_POST(self):
        origin = self.headers.get("Origin", "")
        model_path = self.path in {"/v1/model/poll", "/v1/model/result", "/v1/model/heartbeat"}
        if origin and not (model_path and origin.startswith("chrome-extension://")):
            self.reply(403, {"error": "browser_origin_not_allowed"}); return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 262144:
                self.reply(413, {"error": "invalid_size"}); return
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict):
                raise BridgeError("请求必须是对象")
            store = self.server.store
            if model_path:
                adapter = store.adapter
                token = data.get("model_token")
                secret = getattr(adapter, "secret", None)
                if not isinstance(secret, str) or not isinstance(token, str) or not token.isascii() or not hmac.compare_digest(token, secret):
                    raise BridgeError("网页连接码不正确")
                if self.path.endswith("/heartbeat"):
                    result = adapter.heartbeat()
                elif self.path.endswith("/poll"):
                    result = adapter.poll(data["progress"]) if data.get("progress") is not None else adapter.poll()
                else:
                    result = adapter.receive(data)
            elif self.path == "/v1/game/connect":
                result = store.connect(data)
            elif self.path == "/v1/game/exchange":
                result = store.exchange(data)
            else:
                token = data.get("client_token")
                if not isinstance(token, str) or not token.isascii() or not hmac.compare_digest(token, store.client_token):
                    raise BridgeError("本机客户端凭据不正确")
                if self.path == "/v1/client/utterance":
                    store.submit(data.get("text"), broadcast=data.get("broadcast", False), whisper=data.get("whisper", False)); result = {"accepted": True}
                elif self.path == "/v1/client/call":
                    result = {"request_id": store.direct_call(data.get("skill"), data.get("arguments", {}))}
                else:
                    self.reply(404, {"error": "not_found"}); return
            self.reply(200, result)
        except PairingCodeMismatch as error:
            self.reply(403, {"error": str(error), "reason": "pairing_code_mismatch"})
        except (BridgeError, ValueError, UnicodeError) as error:
            self.reply(400, {"error": str(error)[:160]})

    def log_message(self, *_):
        pass  # Request URLs, payloads and transcripts are not written to disk.


def make_server(store, port=18766):
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.store = store
    server.daemon_threads = True
    return server

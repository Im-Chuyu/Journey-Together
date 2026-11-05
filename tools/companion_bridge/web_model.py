"""Visible-page model adapter. It never reads cookies or calls private APIs."""
import secrets
import threading
import time

from .model import parse_decision, prompt
from .diagnostics import LOG

PAGE_TIMEOUT = 120
HEARTBEAT_FRESH = 45


class WebChatAdapter:
    label = "模型网页（DeepSeek / 豆包，需要登录并连接扩展）"

    def __init__(self, secret=None):
        self.condition = threading.Condition()
        self.secret = secret or secrets.token_urlsafe(32)
        self.pending = None
        self.reply = None
        self.page_seen = 0
        self.closed = False
        self.reported_connection = None
        self.page_progress = None
        self.request_started = None

    def heartbeat(self):
        with self.condition:
            if not self.page_seen or time.monotonic() - self.page_seen > PAGE_TIMEOUT:
                LOG.info("web_heartbeat_resumed")
            self.page_seen = time.monotonic()
            return {"closed": self.closed}

    def poll(self, progress=None):
        with self.condition:
            self.heartbeat()
            if isinstance(progress, dict) and self.pending and progress.get("request_id") == self.pending["request_id"]:
                phase = progress.get("phase")
                if isinstance(phase, str) and phase in {"preparing", "waiting_reply", "reply_detected", "returning", "failed"}:
                    previous = self.page_progress or {}
                    blocks = progress.get("blocks", 0)
                    source = progress.get("source")
                    request_seen = progress.get("request_seen") is True
                    self.page_progress = {"phase": phase, "blocks": blocks if type(blocks) is int and 0 <= blocks <= 16 else 0,
                                          "source": source if isinstance(source, str) and source in {"code", "page", "none"} else "none",
                                          "request_seen": request_seen}
                    if previous.get("phase") != phase or previous.get("request_seen") != request_seen:
                        LOG.info("model_page_progress phase=%s code_blocks=%d source=%s request_seen=%s", phase,
                                 self.page_progress["blocks"], self.page_progress["source"], request_seen)
            return {"job": dict(self.pending) if self.pending else None, "closed": self.closed}

    def diagnostics(self):
        with self.condition:
            return {"state": self.connection_state(), "pending": self.pending is not None,
                    "phase": (self.page_progress or {}).get("phase"),
                    "code_blocks": (self.page_progress or {}).get("blocks", 0),
                    "request_seen": (self.page_progress or {}).get("request_seen", False),
                    "elapsed_seconds": int(time.monotonic() - self.request_started) if self.request_started else None}

    def receive(self, data):
        with self.condition:
            if self.pending is None or data.get("request_id") != self.pending["request_id"]:
                LOG.info("model_page_reply_rejected reason=stale_request")
                raise ValueError("网页回复已失效")
            if not isinstance(data.get("text"), str) or len(data["text"].encode()) > 32768:
                raise ValueError("网页回复格式错误")
            self.page_seen = time.monotonic()
            self.reply = data
            LOG.info("model_page_reply_received error=%s", bool(data.get("error")))
            self.condition.notify_all()
        return {"accepted": True}

    def decide(self, context):
        request_id = secrets.token_hex(12)
        with self.condition:
            if self.closed:
                raise RuntimeError("网页连接已关闭")
            if not self.page_seen or time.monotonic() - self.page_seen > PAGE_TIMEOUT:
                LOG.warning("web_unavailable age_seconds=%d", time.monotonic() - self.page_seen if self.page_seen else -1)
                raise ValueError("模型网页未连接：请登录网页并在扩展中点击连接伙伴")
            self.reply = None
            self.pending = {"request_id": request_id, "prompt": prompt(context, request_id)}
            started = time.monotonic()
            self.request_started, self.page_progress = started, None
            deadline = started + 300
            LOG.info("model_request_started")
            try:
                while self.reply is None:
                    if self.pending is None or self.pending["request_id"] != request_id:
                        raise ValueError("request_superseded")
                    if self.closed:
                        raise ValueError("网页连接已关闭")
                    if time.monotonic() >= deadline:
                        LOG.warning("model_response_timeout web_age_seconds=%d", time.monotonic() - self.page_seen)
                        raise ValueError("等待 模型网页回复超时，请查看网页登录、限流或验证码")
                    self.condition.wait(.5)
                if self.reply.get("error"):
                    code = self.reply.get("error_code")
                    allowed = {"no_input", "composer_not_empty", "request_superseded", "reply_timeout", "page_error",
                               "send_not_confirmed", "context_limit", "new_chat_failed", "new_chat_unavailable"}
                    LOG.warning("model_page_error reason=%s", code if isinstance(code, str) and code in allowed else "unknown")
                    raise ValueError(str(self.reply["error"])[:180])
                try:
                    result = parse_decision(self.reply["text"], request_id)
                except ValueError:
                    LOG.warning("model_reply_rejected reason=invalid_decision")
                    raise
                LOG.info("model_response_received elapsed_seconds=%.1f skill=%s", time.monotonic() - started, result.get("skill", "chat"))
                return result
            finally:
                if self.pending is not None and self.pending["request_id"] == request_id:
                    self.pending = self.reply = None
                    self.page_progress, self.request_started = None, None

    def cancel_pending(self):
        with self.condition:
            self.pending = self.reply = None
            self.page_progress, self.request_started = None, None
            self.condition.notify_all()

    def set_secret(self, value):
        with self.condition:
            self.cancel_pending()
            self.secret, self.page_seen = value, 0

    def close(self):
        with self.condition:
            self.closed = True
            self.condition.notify_all()

    def connection_state(self):
        with self.condition:
            age = time.monotonic() - self.page_seen if self.page_seen else float("inf")
            status = "disconnected" if self.closed or age > PAGE_TIMEOUT else "connected" if age <= HEARTBEAT_FRESH else "background"
            if self.reported_connection != status:
                self.reported_connection = status
                LOG.info("web_state state=%s heartbeat_age_seconds=%d", status, age if self.page_seen else -1)
            return status


# Backwards-compatible import for existing local launchers and adapters.
DeepSeekWebAdapter = WebChatAdapter

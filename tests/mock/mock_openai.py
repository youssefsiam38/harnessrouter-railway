#!/usr/bin/env python3
"""
A tiny, dependency-free OpenAI-compatible endpoint used ONLY by the test suite.

HarnessRouter runs real agent CLIs (opencode, codex, ...) against a model provider you connect.
Rather than spend a real provider key to prove a deployment works, the tests connect a custom
integration whose base_url points here. Every model call gets the same deterministic answer, so a
test can assert a full turn: console -> gateway -> runner -> agent CLI -> provider -> back.

  POST /v1/chat/completions   -> chat completion, JSON or SSE (OpenAI chat format)
  POST /v1/responses          -> Responses API, JSON or SSE  (OpenAI Responses format)
  GET  /v1/models             -> the model list
  GET  /healthz               -> 200
  GET  /calls                 -> how many model calls were served (for assertions)

It is NOT part of the Railway template. Standard library only.
"""
import json
import os
import socket
import sys
import time
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("MOCK_PORT", "8080"))
MODEL = os.environ.get("MOCK_MODEL", "mock-model")
ANSWER = os.environ.get("MOCK_ANSWER", "HR-MOCK-OK: the mock provider answered this turn.")

_calls = 0
_lock = threading.Lock()


def _log(msg):
    sys.stderr.write(f"[mock-openai] {msg}\n")
    sys.stderr.flush()


def _count():
    global _calls
    with _lock:
        _calls += 1


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send_json(self, obj, status=200):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw or b"{}")
        except Exception:
            return {}

    def log_message(self, fmt, *args):
        _log(fmt % args)

    def _sse_start(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

    def _sse(self, obj, event=None):
        if event:
            self.wfile.write(f"event: {event}\n".encode())
        self.wfile.write(f"data: {json.dumps(obj)}\n\n".encode())
        self.wfile.flush()

    def do_GET(self):
        path = self.path.split("?", 1)[0].rstrip("/")
        if path in ("/healthz", ""):
            return self._send_json({"status": "ok"})
        if path == "/calls":
            return self._send_json({"calls": _calls})
        if path.endswith("/models"):
            return self._send_json({"object": "list", "data": [
                {"id": MODEL, "object": "model", "created": 0, "owned_by": "mock"}]})
        self._send_json({"error": {"message": f"not found: {self.path}"}}, status=404)

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        req = self._read_json()
        if path.endswith("/chat/completions"):
            _count()
            return self._chat(req)
        if path.endswith("/responses"):
            _count()
            return self._responses(req)
        self._send_json({"error": {"message": f"not found: {path}"}}, status=404)

    # ── chat completions ─────────────────────────────────────────────────────
    def _chat(self, req):
        usage = {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20}
        model = req.get("model") or MODEL
        if not req.get("stream"):
            return self._send_json({
                "id": "chatcmpl-mock", "object": "chat.completion", "created": int(time.time()),
                "model": model,
                "choices": [{"index": 0, "message": {"role": "assistant", "content": ANSWER},
                             "finish_reason": "stop"}],
                "usage": usage})
        self._sse_start()

        def chunk(delta, finish=None, with_usage=False):
            obj = {"id": "chatcmpl-mock", "object": "chat.completion.chunk",
                   "created": int(time.time()), "model": model,
                   "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            if with_usage:
                obj["usage"] = usage
            self._sse(obj)

        chunk({"role": "assistant", "content": ""})
        chunk({"content": ANSWER})
        chunk({}, finish="stop", with_usage=True)
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    # ── responses ────────────────────────────────────────────────────────────
    def _responses(self, req):
        model = req.get("model") or MODEL
        now = int(time.time())
        msg = {"id": "msg_mock", "type": "message", "status": "completed", "role": "assistant",
               "content": [{"type": "output_text", "text": ANSWER, "annotations": []}]}
        usage = {"input_tokens": 10, "output_tokens": 10, "total_tokens": 20,
                 "input_tokens_details": {"cached_tokens": 0},
                 "output_tokens_details": {"reasoning_tokens": 0}}
        done = {"id": "resp_mock", "object": "response", "created_at": now, "status": "completed",
                "model": model, "output": [msg], "usage": usage}
        if not req.get("stream"):
            return self._send_json(done)
        self._sse_start()
        base = dict(done, status="in_progress", output=[], usage=None)
        seq = iter(range(1000))
        self._sse({"type": "response.created", "sequence_number": next(seq), "response": base},
                  "response.created")
        self._sse({"type": "response.in_progress", "sequence_number": next(seq), "response": base},
                  "response.in_progress")
        item = dict(msg, status="in_progress", content=[])
        self._sse({"type": "response.output_item.added", "sequence_number": next(seq),
                   "output_index": 0, "item": item}, "response.output_item.added")
        part = {"type": "output_text", "text": "", "annotations": []}
        self._sse({"type": "response.content_part.added", "sequence_number": next(seq),
                   "item_id": "msg_mock", "output_index": 0, "content_index": 0, "part": part},
                  "response.content_part.added")
        self._sse({"type": "response.output_text.delta", "sequence_number": next(seq),
                   "item_id": "msg_mock", "output_index": 0, "content_index": 0, "delta": ANSWER},
                  "response.output_text.delta")
        self._sse({"type": "response.output_text.done", "sequence_number": next(seq),
                   "item_id": "msg_mock", "output_index": 0, "content_index": 0, "text": ANSWER},
                  "response.output_text.done")
        self._sse({"type": "response.content_part.done", "sequence_number": next(seq),
                   "item_id": "msg_mock", "output_index": 0, "content_index": 0,
                   "part": msg["content"][0]}, "response.content_part.done")
        self._sse({"type": "response.output_item.done", "sequence_number": next(seq),
                   "output_index": 0, "item": msg}, "response.output_item.done")
        self._sse({"type": "response.completed", "sequence_number": next(seq), "response": done},
                  "response.completed")


class DualStackServer(ThreadingHTTPServer):
    # IPv6 with V6ONLY off: reachable on Railway's IPv6 private network and a docker IPv4 bridge.
    address_family = socket.AF_INET6
    daemon_threads = True

    def server_bind(self):
        try:
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        except (AttributeError, OSError):
            pass
        super().server_bind()


def main():
    server = DualStackServer(("::", PORT), Handler)
    _log(f"listening on [::]:{PORT} model={MODEL}")
    server.serve_forever()


if __name__ == "__main__":
    main()

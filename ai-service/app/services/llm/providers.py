"""Kết nối mô hình ngôn ngữ lớn có hỗ trợ gọi công cụ.

- AnthropicProvider: Claude qua Messages API (https://api.anthropic.com/v1/messages).
- OpenAICompatProvider: mọi máy chủ tương thích OpenAI Chat Completions — OpenAI, Ollama
  (http://localhost:11434/v1), LM Studio, vLLM... cho phép chạy mô hình mở (Qwen2.5, Llama 3.1) ngay trên máy.

Mỗi provider tự chạy vòng lặp agent: gọi mô hình -> thực thi công cụ -> trả kết quả -> lặp
cho tới khi mô hình trả lời bằng văn bản hoặc hết số bước.
"""
from __future__ import annotations

import json
import logging
from collections.abc import Callable
from typing import Any, Protocol

import httpx

from app.core.config import Settings

log = logging.getLogger(__name__)
ToolExecutor = Callable[[str, dict[str, Any]], Any]


class LLMError(RuntimeError):
    pass


class LLMProvider(Protocol):
    name: str

    async def run(self, system: str, messages: list[dict[str, str]], tools: list[dict[str, Any]],
                  execute: ToolExecutor, max_steps: int = 6) -> tuple[str, list[str]]: ...

    async def complete_vision(self, prompt: str, image_b64: str, media_type: str) -> str: ...


def _dump(result: Any) -> str:
    return json.dumps(result, ensure_ascii=False, default=str)[:12000]


class AnthropicProvider:
    name = "anthropic"
    URL = "https://api.anthropic.com/v1/messages"

    def __init__(self, settings: Settings, client: httpx.AsyncClient):
        self.s = settings
        self.http = client

    async def _post(self, payload: dict[str, Any]) -> dict[str, Any]:
        r = await self.http.post(self.URL, json=payload, timeout=self.s.llm_timeout_seconds, headers={
            "x-api-key": self.s.llm_api_key, "anthropic-version": "2023-06-01", "content-type": "application/json"})
        if r.status_code >= 400:
            raise LLMError(f"Anthropic {r.status_code}: {r.text[:300]}")
        return r.json()

    async def run(self, system, messages, tools, execute, max_steps=6):
        convo: list[dict[str, Any]] = [{"role": m["role"], "content": m["content"]} for m in messages]
        used: list[str] = []
        for _ in range(max_steps):
            data = await self._post({"model": self.s.llm_model, "max_tokens": self.s.llm_max_tokens,
                                     "system": system, "messages": convo, "tools": tools})
            blocks = data.get("content", [])
            calls = [b for b in blocks if b.get("type") == "tool_use"]
            if not calls:
                return "".join(b.get("text", "") for b in blocks if b.get("type") == "text").strip(), used
            convo.append({"role": "assistant", "content": blocks})
            results = []
            for c in calls:
                used.append(c["name"])
                results.append({"type": "tool_result", "tool_use_id": c["id"],
                                "content": _dump(execute(c["name"], c.get("input") or {}))})
            convo.append({"role": "user", "content": results})
        raise LLMError("Quá số bước gọi công cụ")

    async def complete_vision(self, prompt, image_b64, media_type):
        data = await self._post({"model": self.s.vision_model or self.s.llm_model, "max_tokens": 1200, "messages": [
            {"role": "user", "content": [
                {"type": "image", "source": {"type": "base64", "media_type": media_type, "data": image_b64}},
                {"type": "text", "text": prompt}]}]})
        return "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text")


class OpenAICompatProvider:
    name = "openai"

    def __init__(self, settings: Settings, client: httpx.AsyncClient):
        self.s = settings
        self.http = client
        base = (settings.llm_base_url or "https://api.openai.com/v1").rstrip("/")
        self.url = base + "/chat/completions" if base.endswith("/v1") else base + "/v1/chat/completions"

    async def _post(self, payload: dict[str, Any]) -> dict[str, Any]:
        headers = {"content-type": "application/json"}
        if self.s.llm_api_key:
            headers["authorization"] = f"Bearer {self.s.llm_api_key}"
        r = await self.http.post(self.url, json=payload, headers=headers, timeout=self.s.llm_timeout_seconds)
        if r.status_code >= 400:
            raise LLMError(f"OpenAI-compatible {r.status_code}: {r.text[:300]}")
        return r.json()

    async def run(self, system, messages, tools, execute, max_steps=6):
        convo: list[dict[str, Any]] = [{"role": "system", "content": system}] + list(messages)
        fn_tools = [{"type": "function", "function": {"name": t["name"], "description": t["description"],
                                                      "parameters": t["input_schema"]}} for t in tools]
        used: list[str] = []
        for _ in range(max_steps):
            data = await self._post({"model": self.s.llm_model, "messages": convo, "tools": fn_tools,
                                     "max_tokens": self.s.llm_max_tokens, "temperature": 0.3})
            msg = data["choices"][0]["message"]
            calls = msg.get("tool_calls") or []
            if not calls:
                return (msg.get("content") or "").strip(), used
            convo.append({"role": "assistant", "content": msg.get("content") or "", "tool_calls": calls})
            for c in calls:
                fn = c["function"]
                try:
                    args = json.loads(fn.get("arguments") or "{}")
                except json.JSONDecodeError:
                    args = {}
                used.append(fn["name"])
                convo.append({"role": "tool", "tool_call_id": c.get("id", fn["name"]),
                              "content": _dump(execute(fn["name"], args))})
        raise LLMError("Quá số bước gọi công cụ")

    async def complete_vision(self, prompt, image_b64, media_type):
        data = await self._post({"model": self.s.vision_model or self.s.llm_model, "max_tokens": 1200, "messages": [
            {"role": "user", "content": [
                {"type": "text", "text": prompt},
                {"type": "image_url", "image_url": {"url": f"data:{media_type};base64,{image_b64}"}}]}]})
        return data["choices"][0]["message"].get("content") or ""


def build_provider(settings: Settings, client: httpx.AsyncClient) -> LLMProvider | None:
    if not settings.llm_enabled:
        return None
    if settings.llm_provider == "anthropic":
        return AnthropicProvider(settings, client)
    return OpenAICompatProvider(settings, client)

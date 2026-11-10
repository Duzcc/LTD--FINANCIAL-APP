from __future__ import annotations

from fastapi import Request

from app.services.llm.assistant import Assistant


def get_assistant(request: Request) -> Assistant:
    return request.app.state.assistant

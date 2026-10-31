"""Trợ lý hội thoại có gọi công cụ."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app.api.deps import get_assistant
from app.schemas.api import ChatRequest, ChatResponse
from app.services.llm.assistant import Assistant

router = APIRouter(tags=["assistant"])


@router.post("/chat", response_model=ChatResponse, summary="Hỏi đáp tài chính")
async def chat(body: ChatRequest, assistant: Assistant = Depends(get_assistant)) -> ChatResponse:
    r = await assistant.chat(body.snapshot, [m.model_dump() for m in body.messages])
    return ChatResponse(reply=r.reply, provider=r.provider, tools_used=r.tools_used, actions=r.actions,
                        fallback_reason=r.fallback_reason)

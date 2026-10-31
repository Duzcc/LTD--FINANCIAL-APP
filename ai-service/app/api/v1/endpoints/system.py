"""Thông tin hệ thống và mô hình."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app import __version__
from app.api.deps import get_assistant
from app.schemas.api import HealthResponse
from app.services.llm.assistant import Assistant
from app.services.registry import metrics, models_ready

router = APIRouter(tags=["system"])


@router.get("/health", response_model=HealthResponse, summary="Kiểm tra sống")
async def health(assistant: Assistant = Depends(get_assistant)) -> HealthResponse:
    return HealthResponse(status="ok", version=__version__, models_loaded=models_ready(), assistant=assistant.mode)


@router.get("/v1/models", summary="Thông tin & chỉ số đánh giá của các mô hình")
async def model_info(assistant: Assistant = Depends(get_assistant)) -> dict:
    m = metrics()
    return {
        "trainedAt": m.get("trained_at"),
        "assistant": assistant.mode,
        "models": {k: {kk: v.get(kk) for kk in ("algorithm", "best_params", "train_size", "synthetic_test", "handwritten_eval")}
                   for k, v in m.items() if isinstance(v, dict)},
        "forecaster": "Hồ sơ thứ-trong-tuần + Holt / Holt-Winters (numpy)",
        "anomaly": "Robust z-score (MAD) + Isolation Forest + phát hiện nhập trùng",
    }

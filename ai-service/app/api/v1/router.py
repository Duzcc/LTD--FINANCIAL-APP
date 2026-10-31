"""Gom các router của API v1 (yêu cầu khóa dịch vụ)."""
from fastapi import APIRouter, Depends

from app.core.security import require_service_key

from .endpoints import analytics, assistant, nlp, receipts

api_router = APIRouter(prefix="/v1", dependencies=[Depends(require_service_key)])
for module in (nlp, analytics, receipts, assistant):
    api_router.include_router(module.router)

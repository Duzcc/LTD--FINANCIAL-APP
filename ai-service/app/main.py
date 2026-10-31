"""Điểm khởi chạy AI service (FastAPI app factory).

    uvicorn app.main:app --host 0.0.0.0 --port 8000
"""
from __future__ import annotations

import logging
import time
import uuid
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app import __version__
from app.api.v1.endpoints import system
from app.api.v1.router import api_router
from app.core.config import get_settings
from app.services.llm.assistant import Assistant
from app.services.registry import ensure_models

log = logging.getLogger("ai-service")


@asynccontextmanager
async def lifespan(app: FastAPI):
    ensure_models()
    from app.services.categorizer import get_categorizer
    from app.services.parser import get_parser

    get_categorizer()
    get_parser()  # làm nóng mô hình để yêu cầu đầu tiên không chậm
    async with httpx.AsyncClient() as client:
        app.state.assistant = Assistant(client)
        log.info("AI service sẵn sàng (trợ lý: %s)", app.state.assistant.mode)
        yield


def create_app() -> FastAPI:
    settings = get_settings()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    app = FastAPI(title=settings.app_name, version=__version__, lifespan=lifespan,
                  description="Dịch vụ AI: phân loại danh mục, nhập nhanh bằng câu tự nhiên, dự báo, phát hiện bất thường, "
                              "gợi ý ngân sách, đọc hóa đơn, tìm kiếm ngữ nghĩa và trợ lý hội thoại.",
                  docs_url="/docs" if settings.environment != "production" else None)

    @app.middleware("http")
    async def request_context(request: Request, call_next):
        rid = request.headers.get("x-request-id") or uuid.uuid4().hex[:12]
        start = time.perf_counter()
        response = await call_next(request)
        ms = (time.perf_counter() - start) * 1000
        response.headers["x-request-id"] = rid
        response.headers["server-timing"] = f"app;dur={ms:.1f}"
        if request.url.path != "/health":
            log.info("%s %s %s %.1fms rid=%s", request.method, request.url.path, response.status_code, ms, rid)
        return response

    @app.exception_handler(RequestValidationError)
    async def validation_error(_: Request, exc: RequestValidationError):
        details = [{"loc": e.get("loc"), "msg": e.get("msg"), "type": e.get("type")} for e in exc.errors()[:10]]
        return JSONResponse(status_code=422, content={"error": {
            "code": "VALIDATION_ERROR", "message": "Dữ liệu không hợp lệ.", "details": details}})

    app.include_router(system.router)
    app.include_router(api_router)
    return app


app = create_app()

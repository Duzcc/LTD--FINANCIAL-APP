"""Xác thực giữa backend và AI service bằng khóa dùng chung."""
from __future__ import annotations

import hmac

from fastapi import Header, HTTPException, status

from .config import get_settings


async def require_service_key(x_api_key: str | None = Header(default=None)) -> None:
    expected = get_settings().service_api_key
    if not expected:
        return
    if not x_api_key or not hmac.compare_digest(x_api_key, expected):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Khóa dịch vụ không hợp lệ.")

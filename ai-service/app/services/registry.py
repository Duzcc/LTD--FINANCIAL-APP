"""Nạp các mô hình đã huấn luyện (artifacts) một lần khi khởi động."""
from __future__ import annotations

import json
import logging
from functools import lru_cache
from typing import Any

import joblib

from app.core.config import get_settings

log = logging.getLogger(__name__)


@lru_cache
def load_model(name: str) -> Any:
    path = get_settings().artifacts_dir / f"{name}.joblib"
    if not path.exists():
        raise FileNotFoundError(f"Chưa có mô hình {path}. Chạy: python -m ml.train")
    log.info("Nạp mô hình %s", path)
    return joblib.load(path)


@lru_cache
def metrics() -> dict:
    path = get_settings().artifacts_dir / "metrics.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def models_ready() -> bool:
    try:
        load_model("categorizer")
        load_model("intent")
        return True
    except Exception:  # noqa: BLE001
        return False


def ensure_models() -> None:
    """Huấn luyện lại nếu thiếu mô hình hoặc mô hình không đọc được (khác phiên bản thư viện)."""
    try:
        load_model("categorizer")
        load_model("intent")
        return
    except Exception as exc:  # noqa: BLE001
        log.warning("Không nạp được mô hình (%s) — huấn luyện lại từ bộ dữ liệu.", exc)
    load_model.cache_clear()
    metrics.cache_clear()
    from ml.train import main as train  # nhập muộn: chỉ cần khi huấn luyện

    train([])
    load_model("categorizer")
    load_model("intent")

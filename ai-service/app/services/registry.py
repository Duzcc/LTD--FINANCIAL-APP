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


MODEL_NAMES = ("categorizer", "intent")


# lỗi thì trả về để ensure_models() train lại
def _load_models() -> Exception | None:
    try:
        for name in MODEL_NAMES:
            load_model(name)
    except Exception as exc:
        return exc
    return None


def models_ready() -> bool:
    return _load_models() is None


def ensure_models() -> None:
    error = _load_models()
    if error is None:
        return
    log.warning("Không nạp được mô hình (%s) — huấn luyện lại từ bộ dữ liệu.", error)
    load_model.cache_clear()
    metrics.cache_clear()
    from ml.train import main as train

    train([])
    for name in MODEL_NAMES:
        load_model(name)

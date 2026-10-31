"""Chuẩn hóa văn bản tiếng Việt cho các mô hình."""
from __future__ import annotations

import re
import unicodedata

_NUM_RE = re.compile(r"\d+(?:[.,]\d+)*")
_NON_WORD = re.compile(r"[^0-9a-zA-ZÀ-ỹ\s]+")
_SPACES = re.compile(r"\s+")

# Viết tắt phổ biến khi ghi chép chi tiêu.
ABBREVIATIONS = {
    "cf": "cà phê", "cafe": "cà phê", "coffee": "cà phê", "ck": "chuyển khoản",
    "tt": "thanh toán", "sv": "sinh viên", "nv": "nhân viên", "dt": "điện thoại",
    "đt": "điện thoại", "ko": "không", "k0": "không", "mn": "mọi người",
    "bh": "bảo hiểm", "hp": "học phí", "ts": "trà sữa", "bn": "bao nhiêu",
    "sn": "sinh nhật", "đc": "được", "dc": "được", "lg": "lương",
}


def fold(text: str) -> str:
    """Bỏ dấu tiếng Việt và chuyển về chữ thường: 'Đổ xăng' -> 'do xang'."""
    text = unicodedata.normalize("NFD", text.lower())
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Mn")
    return text.replace("đ", "d")


def normalize(text: str, *, keep_numbers: bool = False) -> str:
    """Chữ thường, chuẩn NFC, mở rộng viết tắt, thay số bằng <num>."""
    text = unicodedata.normalize("NFC", text or "").lower().strip()
    if not keep_numbers:
        text = _NUM_RE.sub(" 0 ", text)
    text = _NON_WORD.sub(" ", text)
    words = [ABBREVIATIONS.get(w, w) for w in _SPACES.split(text) if w]
    return " ".join(words)


def model_text(text: str) -> str:
    """Văn bản đưa vào mô hình: dạng có dấu + dạng bỏ dấu để chịu được khi người dùng gõ không dấu."""
    n = normalize(text)
    f = fold(n)
    return n if n == f else f"{n} | {f}"


def fold_keep_numbers(text: str) -> str:
    """Bỏ dấu nhưng giữ dấu chấm/phẩy giữa chữ số và dấu '/' để đọc số tiền và ngày."""
    t = fold(unicodedata.normalize("NFC", text or ""))
    t = re.sub(r"[^a-z0-9.,/]+", " ", t)
    t = re.sub(r"(?<!\d)[.,]|[.,](?!\d)", " ", t)
    return _SPACES.sub(" ", t).strip()

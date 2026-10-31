"""Các bộ nhận dạng chữ (OCR) phía máy chủ, chọn tự động theo môi trường.

- AppleVisionOcr: Vision framework của macOS 13+ (hỗ trợ tiếng Việt, chính xác cao, chạy cục bộ).
- TesseractOcr: Tesseract 5 + gói `vie` (Linux/Docker), có tiền xử lý ảnh: xám, tăng tương phản,
  phóng to, khử nghiêng bằng phân tích hình chiếu, nhị phân hóa Otsu.
Mỗi engine trả về danh sách khối chữ có tọa độ; `layout.group_rows` dựng lại dòng.
"""
from __future__ import annotations

import io
import logging
import math
import shutil
import sys
from functools import lru_cache
from typing import Protocol

from .layout import OcrBox, group_rows

log = logging.getLogger(__name__)


def _load_gray(data: bytes, color: bool = False):
    """Mở ảnh (xoay theo EXIF), phóng to tới ≥ 1400px chiều ngang, tăng tương phản."""
    from PIL import Image, ImageOps

    img = ImageOps.exif_transpose(Image.open(io.BytesIO(data)))
    img = img.convert("RGB" if color else "L")
    if img.width < 1400:
        scale = 1400 / img.width
        img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
    return ImageOps.autocontrast(img, cutoff=1)


def skew_angle(img) -> float:
    """Góc nghiêng (độ) làm phương sai hình chiếu ngang lớn nhất — dòng chữ thẳng hàng nhất."""
    import numpy as np
    from PIL import Image

    small = img.convert("L").resize((max(1, img.width // 4), max(1, img.height // 4)))
    arr = np.asarray(small, dtype=np.float32)
    ink = Image.fromarray(((arr < arr.mean() - 25) * 255).astype(np.uint8))
    best, best_score = 0.0, -1.0
    for a in np.arange(-6, 6.01, 0.25):
        prof = np.asarray(ink.rotate(a, resample=Image.BILINEAR), dtype=np.float32).sum(axis=1)
        score = float(np.var(prof))
        if score > best_score:
            best, best_score = float(a), score
    return best


def deskew(img):
    from PIL import Image

    a = skew_angle(img)
    if abs(a) <= 0.2:
        return img
    fill = 255 if img.mode == "L" else (255, 255, 255)
    return img.rotate(a, resample=Image.BICUBIC, expand=True, fillcolor=fill)


class OcrEngine(Protocol):
    name: str

    def available(self) -> bool: ...

    def recognize(self, data: bytes) -> list[str]: ...


class AppleVisionOcr:
    name = "apple-vision"

    def available(self) -> bool:
        if sys.platform != "darwin":
            return False
        try:
            import Vision  # type: ignore  # noqa: F401
            return True
        except ImportError:
            return False

    def recognize(self, data: bytes) -> list[str]:
        import Vision  # type: ignore
        from Foundation import NSData  # type: ignore

        # Làm thẳng ảnh trước (giống bước tiền xử lý của Tesseract) rồi mới nhận dạng
        img = deskew(_load_gray(data, color=True))
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=92)
        payload, (W, H) = buf.getvalue(), img.size
        handler = Vision.VNImageRequestHandler.alloc().initWithData_options_(
            NSData.dataWithBytes_length_(payload, len(payload)), None)
        req = Vision.VNRecognizeTextRequest.alloc().init()
        req.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
        req.setUsesLanguageCorrection_(True)
        supported, _ = req.supportedRecognitionLanguagesAndReturnError_(None)
        langs = [lang for lang in ("vi-VT", "vi-VN", "en-US") if supported and lang in supported]
        if langs:
            req.setRecognitionLanguages_(langs)
        ok, err = handler.performRequests_error_([req], None)
        if not ok:
            raise RuntimeError(f"Vision lỗi: {err}")
        boxes = []
        for obs in req.results() or []:
            cands = obs.topCandidates_(1)
            if not cands:
                continue
            c = cands[0]
            bb = obs.boundingBox()  # chuẩn hóa 0..1, gốc dưới-trái → đổi sang pixel, gốc trên-trái
            tl, tr = obs.topLeft(), obs.topRight()
            angle = math.atan2(-(tr.y - tl.y) * H, (tr.x - tl.x) * W)
            boxes.append(OcrBox(str(c.string()), bb.origin.x * W, (1 - bb.origin.y - bb.size.height) * H,
                                bb.size.width * W, bb.size.height * H, float(c.confidence()), angle))
        return group_rows(boxes)


class TesseractOcr:
    name = "tesseract"

    @lru_cache(maxsize=1)  # noqa: B019 - engine là singleton
    def _langs(self) -> str:
        import pytesseract  # type: ignore

        have = set(pytesseract.get_languages(config=""))
        return "+".join(lang for lang in ("vie", "eng") if lang in have) or "eng"

    def available(self) -> bool:
        if not shutil.which("tesseract"):
            return False
        try:
            import pytesseract  # type: ignore  # noqa: F401
            from PIL import Image  # type: ignore  # noqa: F401
            return True
        except ImportError:
            return False

    @staticmethod
    def preprocess(data: bytes):
        import numpy as np
        from PIL import Image

        img = deskew(_load_gray(data))
        # Nhị phân hóa Otsu
        a = np.asarray(img)
        hist = np.bincount(a.ravel(), minlength=256).astype(np.float64)
        w = np.cumsum(hist)
        mu = np.cumsum(hist * np.arange(256))
        between = (mu[-1] * w - mu * w[-1]) ** 2 / np.maximum(w * (w[-1] - w), 1)
        t = int(np.argmax(between))
        return Image.fromarray(((a > t) * 255).astype(np.uint8)), 0.0

    def recognize(self, data: bytes) -> list[str]:
        import pytesseract  # type: ignore

        img, _ = self.preprocess(data)
        d = pytesseract.image_to_data(img, lang=self._langs(), config="--psm 4 --oem 1",
                                      output_type=pytesseract.Output.DICT)
        # Gom từ thành khối theo (block, par, line) của Tesseract, rồi dựng dòng theo tọa độ
        groups: dict[tuple[int, int, int], list[int]] = {}
        for i, word in enumerate(d["text"]):
            if word.strip() and float(d["conf"][i]) > 10:
                groups.setdefault((d["block_num"][i], d["par_num"][i], d["line_num"][i]), []).append(i)
        boxes = []
        for idx in groups.values():
            x0 = min(d["left"][i] for i in idx)
            y0 = min(d["top"][i] for i in idx)
            x1 = max(d["left"][i] + d["width"][i] for i in idx)
            y1 = max(d["top"][i] + d["height"][i] for i in idx)
            text = " ".join(d["text"][i] for i in sorted(idx, key=lambda i: d["left"][i]))
            conf = sum(float(d["conf"][i]) for i in idx) / len(idx) / 100
            boxes.append(OcrBox(text, x0, y0, x1 - x0, y1 - y0, conf, 0.0))
        return group_rows(boxes, skew=0.0)


ENGINES: list[OcrEngine] = [AppleVisionOcr(), TesseractOcr()]


def available_engines() -> list[str]:
    return [e.name for e in ENGINES if e.available()]


def ocr_image(data: bytes) -> tuple[str, str] | None:
    """Trả về (văn bản theo dòng, tên engine) hoặc None nếu không engine nào dùng được."""
    for engine in ENGINES:
        if not engine.available():
            continue
        try:
            rows = engine.recognize(data)
        except Exception as exc:  # noqa: BLE001 - thử engine kế tiếp
            log.warning("OCR %s lỗi: %s", engine.name, exc)
            continue
        if rows:
            return "\n".join(rows), engine.name
    return None

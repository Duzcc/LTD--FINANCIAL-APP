"""Đánh giá đầu-cuối đọc hóa đơn: ảnh hóa đơn tổng hợp → OCR → dựng dòng → phân tích.

    python -m ml.evaluate_receipts --n 40           # dùng engine OCR có sẵn trên máy
Chỉ số: tỷ lệ đúng tổng tiền, ngày, cửa hàng; độ tin cậy trung bình khi đúng/sai.
"""
from __future__ import annotations

import argparse
import io
import json
import random
import time
from pathlib import Path

from app.nlp.text import fold
from app.services.receipt import ocr_image, parse_receipt_text

from .data.receipts import make_receipt


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=40)
    ap.add_argument("--seed", type=int, default=2026)
    ap.add_argument("--show-errors", action="store_true")
    args = ap.parse_args(argv)
    rnd = random.Random(args.seed)
    ok_total = ok_date = ok_merchant = 0
    conf_ok, conf_bad, engine, secs = [], [], None, 0.0
    for i in range(args.n):
        img, label, _ = make_receipt(rnd, i)
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=90)
        t0 = time.perf_counter()
        res = ocr_image(buf.getvalue())
        secs += time.perf_counter() - t0
        if res is None:
            raise SystemExit("Không có engine OCR nào khả dụng.")
        text, engine = res
        r = parse_receipt_text(text)
        good = r.total == label.total
        ok_total += good
        (conf_ok if good else conf_bad).append(r.confidence)
        ok_date += bool(r.date and r.date.date().isoformat() == label.date)
        ok_merchant += bool(r.merchant and fold(label.merchant)[:6] in fold(r.merchant))
        if args.show_errors and not good:
            print(f"--- #{i} cần {label.total}, đọc {r.total} (tin cậy {r.confidence})\n{text}\n")
    n = args.n
    report = {
        "engine": engine, "receipts": n, "total_accuracy": round(ok_total / n, 3), "date_accuracy": round(ok_date / n, 3),
        "merchant_accuracy": round(ok_merchant / n, 3), "avg_seconds": round(secs / n, 2),
        "confidence_when_correct": round(sum(conf_ok) / max(1, len(conf_ok)), 2),
        "confidence_when_wrong": round(sum(conf_bad) / max(1, len(conf_bad)), 2),
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    out = Path(__file__).resolve().parents[1] / "artifacts" / f"receipt_eval_{engine}.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()

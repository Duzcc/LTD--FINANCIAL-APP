"""Đọc hóa đơn: sửa lỗi OCR, dựng dòng từ khối chữ, bỏ phiếu tổng tiền, OCR đầu-cuối trên ảnh tổng hợp."""
import io
import random

import pytest

from app.services.receipt import OcrBox, available_engines, clean_ocr_numbers, group_rows, ocr_image, parse_receipt_text
from ml.data.receipts import make_receipt


def test_clean_ocr_numbers():
    assert clean_ocr_numbers("TONG: 46. 000") == "TONG: 46.000"
    assert clean_ocr_numbers("Tong 1O5.OOO") == "Tong 105.000"
    assert clean_ocr_numbers("tổng 46 000đ") == "tổng 46.000đ"


def test_group_rows_with_skew():
    # Ảnh nghiêng ~3°: số tiền bên phải thấp hơn nhãn bên trái nhưng vẫn cùng dòng
    boxes = [OcrBox("Tổng cộng:", 10, 100, 120, 20, angle=0.05), OcrBox("154.000", 500, 124, 90, 20, angle=0.05),
             OcrBox("Tiền thừa:", 10, 130, 120, 20, angle=0.05), OcrBox("46.000", 500, 154, 80, 20, angle=0.05)]
    assert group_rows(boxes) == ["Tổng cộng:  154.000", "Tiền thừa:  46.000"]


def test_vote_repairs_misread_total():
    text = "HIGHLANDS COFFEE\nTổng tiền hàng: 454.900đ\nTổng cộng: 454.999đ\nTiền khách đưa: 500.000\nTiền thừa: 46.000"
    r = parse_receipt_text(text)
    assert r.total == 454_000 and len(r.checks) >= 2


def test_cash_minus_change_without_total_keyword():
    r = parse_receipt_text("QUÁN A\nCơm gà 45.000\nTrà đá 5.000\nKhách đưa 100.000\nTiền thừa 50.000")
    assert r.total == 50_000


def test_fuzzy_keywords_and_label_value_on_next_line():
    r = parse_receipt_text("CIRCLE K\nT0NG C0NG\n46.000\nTien thira: 4.000\nTien khach dua 50.000")
    assert r.total == 46_000


def test_dates():
    assert parse_receipt_text("A\nNgày 18 tháng 10 năm 2026\nTổng 10.000").date.day == 18
    d = parse_receipt_text("A\n2026-10-05 08:30\nTổng 10.000").date
    assert (d.month, d.day, d.hour) == (10, 5, 8)


@pytest.mark.skipif(not available_engines(), reason="máy không có engine OCR")
def test_end_to_end_ocr_on_synthetic_receipts():
    rnd = random.Random(11)
    correct = 0
    for i in range(6):
        img, label, _ = make_receipt(rnd, i)
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=90)
        text, _engine = ocr_image(buf.getvalue())
        correct += parse_receipt_text(text).total == label.total
    assert correct >= 5

"""Sinh ảnh hóa đơn tiếng Việt tổng hợp (có nhãn) để kiểm thử và đánh giá OCR + bộ phân tích hóa đơn.

Mô phỏng hóa đơn máy in nhiệt 80mm của cửa hàng tiện lợi, siêu thị, quán cà phê, nhà thuốc:
tên cửa hàng, địa chỉ, ngày giờ, bảng hàng (tên / SL x đơn giá / thành tiền), giảm giá, tổng,
tiền khách đưa, tiền thừa. Ảnh được làm "bẩn" như chụp thật: xoay nhẹ, mờ, nhiễu, nén JPEG.

    python -m ml.data.receipts --out ml/data/receipts --n 40
"""
from __future__ import annotations

import argparse
import io
import json
import random
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

STORES = [
    ("CIRCLE K", ["Nước suối Aquafina", "Bánh mì sandwich", "Mì ly Hảo Hảo", "Xúc xích Đức", "Trà xanh 0 độ", "Sữa tươi TH"]),
    ("WINMART+", ["Rau muống", "Trứng gà 10 quả", "Thịt ba chỉ", "Gạo ST25 5kg", "Nước mắm Nam Ngư", "Dầu ăn Neptune"]),
    ("BÁCH HÓA XANH", ["Cà chua", "Hành lá", "Cá basa phi lê", "Sữa chua Vinamilk", "Đậu hũ", "Bột giặt OMO"]),
    ("HIGHLANDS COFFEE", ["Phin sữa đá", "Trà sen vàng", "Bánh mì que", "Freeze trà xanh", "Bạc xỉu"]),
    ("NHÀ THUỐC LONG CHÂU", ["Panadol Extra", "Vitamin C 500mg", "Khẩu trang y tế", "Nước muối sinh lý", "Băng cá nhân"]),
    ("PHỞ THÌN BỜ HỒ", ["Phở tái lăn", "Quẩy", "Trà đá", "Phở chín"]),
    ("CO.OPMART", ["Khăn giấy Pulppy", "Nước rửa chén Sunlight", "Bánh quy Cosy", "Kem đánh răng P/S"]),
]
STREETS = ["Lê Lợi", "Nguyễn Huệ", "Trần Hưng Đạo", "Hai Bà Trưng", "Cầu Giấy", "Phạm Văn Đồng", "Lý Thường Kiệt"]
TOTAL_LABELS = ["TỔNG CỘNG", "Tổng thanh toán", "TỔNG TIỀN", "Thanh toán", "KHÁCH PHẢI TRẢ", "Tổng cộng"]
FONTS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
    "/System/Library/Fonts/Supplemental/Courier New.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
]


@dataclass
class Label:
    file: str
    merchant: str
    total: int
    date: str  # YYYY-MM-DD
    items: list[tuple[str, int]]


def money(v: int, style: int) -> str:
    s = f"{v:,}"
    return [s.replace(",", "."), s, s.replace(",", ".") + "đ", s.replace(",", ".") + " VND"][style]


def _font(size: int, rnd: random.Random) -> ImageFont.FreeTypeFont:
    available = [f for f in FONTS if Path(f).exists()]
    if not available:
        return ImageFont.load_default(size)
    return ImageFont.truetype(rnd.choice(available), size)


def make_receipt(rnd: random.Random, idx: int) -> tuple[Image.Image, Label, str]:
    store, products = rnd.choice(STORES)
    style = rnd.randrange(4)
    when = datetime(2026, 10, 28, 8) - timedelta(days=rnd.randrange(60), minutes=rnd.randrange(800))
    items = []
    for name in rnd.sample(products, k=rnd.randint(2, min(5, len(products)))):
        qty = rnd.choice([1, 1, 1, 2, 3])
        price = rnd.choice([6, 8, 10, 12, 15, 18, 25, 29, 35, 45, 55, 65, 89, 120, 159]) * 1000
        items.append((name, qty, price))
    subtotal = sum(q * p for _, q, p in items)
    discount = rnd.choice([0, 0, 0, 5000, 10000]) if subtotal > 50000 else 0
    total = subtotal - discount
    cash = next(c for c in (50000, 100000, 200000, 500000, 1000000) if c >= total)

    w = 46
    rows: list[tuple[str, str]] = []  # (căn lề, nội dung)
    rows += [("c", store), ("c", f"{rnd.randint(1, 300)} {rnd.choice(STREETS)}, Q.{rnd.randint(1, 12)}"),
             ("c", f"ĐT: 0{rnd.randint(200000000, 999999999)}"), ("c", "HÓA ĐƠN BÁN HÀNG"),
             ("l", rnd.choice(["Ngày: ", "Ngày bán: ", ""])
              + when.strftime(rnd.choice(["%d/%m/%Y %H:%M", "%d-%m-%Y %H:%M", "%d/%m/%y %H:%M"]))),
             ("l", f"Số HĐ: {rnd.randint(10000, 99999)}"), ("l", "-" * w),
             ("l", "Tên hàng".ljust(18) + "SL".rjust(4) + "Đ.Giá".rjust(11) + "T.Tiền".rjust(13))]
    for name, q, p in items:
        if rnd.random() < 0.5:
            rows.append(("l", name[:18].ljust(18) + str(q).rjust(4) + money(p, 0).rjust(11) + money(q * p, style % 2).rjust(13)))
        else:
            rows.append(("l", name))
            rows.append(("l", f"  {q} x {money(p, 0)}".ljust(w - 13) + money(q * p, style % 2).rjust(13)))
    rows.append(("l", "-" * w))
    rows.append(("l", "Tổng tiền hàng:".ljust(w - 14) + money(subtotal, style).rjust(14)))
    if discount:
        rows.append(("l", "Giảm giá:".ljust(w - 14) + money(discount, style).rjust(14)))
    rows.append(("l", (rnd.choice(TOTAL_LABELS) + ":").ljust(w - 14) + money(total, style).rjust(14)))
    rows.append(("l", "Tiền khách đưa:".ljust(w - 14) + money(cash, style).rjust(14)))
    rows.append(("l", "Tiền thừa:".ljust(w - 14) + money(cash - total, style).rjust(14)))
    rows += [("c", "Cảm ơn quý khách! Hẹn gặp lại")]

    font = _font(rnd.choice([20, 22, 24]), rnd)
    line_h = int(font.size * 1.45)
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    width = int(max(probe.textlength(t, font=font) for _, t in rows)) + 48
    img = Image.new("L", (width, line_h * (len(rows) + 4)), 255)
    draw = ImageDraw.Draw(img)
    y = line_h * 2
    for align, text in rows:
        tw = draw.textlength(text, font=font)
        x = (width - tw) / 2 if align == "c" else 24
        draw.text((x, y), text, fill=rnd.randint(0, 60), font=font)
        y += line_h

    # Làm bẩn như ảnh chụp: giấy ngả màu, xoay nhẹ, mờ, nhiễu, nén JPEG
    img = img.rotate(rnd.uniform(-2.5, 2.5), resample=Image.BICUBIC, expand=True, fillcolor=235)
    if rnd.random() < 0.6:
        img = img.filter(ImageFilter.GaussianBlur(rnd.uniform(0.3, 1.0)))
    noise = Image.effect_noise(img.size, rnd.uniform(5, 20))
    img = Image.blend(img, noise, 0.08)
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "JPEG", quality=rnd.randint(55, 85))
    img = Image.open(io.BytesIO(buf.getvalue()))
    text = "\n".join(t for _, t in rows)
    label = Label(f"receipt_{idx:03d}.jpg", store, total, when.date().isoformat(), [(n, q * p) for n, q, p in items])
    return img, label, text


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="ml/data/receipts")
    ap.add_argument("--n", type=int, default=40)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args(argv)
    rnd = random.Random(args.seed)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    labels = []
    for i in range(args.n):
        img, label, _ = make_receipt(rnd, i)
        img.save(out / label.file, quality=90)
        labels.append(asdict(label))
    (out / "labels.json").write_text(json.dumps(labels, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{args.n} hóa đơn -> {out}")


if __name__ == "__main__":
    main()

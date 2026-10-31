"""Sinh bộ dữ liệu giao dịch tiếng Việt có nhãn (tự xây dựng) cho huấn luyện.

Kỹ thuật tăng cường dữ liệu mô phỏng cách người dùng ghi chép thật:
bỏ dấu, viết tắt, viết thường/hoa, sai chính tả nhẹ, thêm số tiền, thời gian, người đi cùng.

    python -m ml.data.generate_dataset --out ml/data/generated --seed 42
"""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

from app.nlp.text import fold

from .lexicon import AMOUNTS, CATEGORIES, COMPANIONS, INTENT_TEMPLATES, PEOPLE, TIME_WORDS, WALLETS

ABBREV = {"cà phê": ["cf", "cafe", "cà fê"], "chuyển khoản": ["ck"], "điện thoại": ["dt", "đt"], "trà sữa": ["ts"],
          "học phí": ["hp"], "không": ["ko", "k"], "được": ["đc", "dc"], "tiền": ["tien", "t"]}


def _typo(text: str, rnd: random.Random) -> str:
    if len(text) < 6 or rnd.random() > 0.08:
        return text
    i = rnd.randrange(1, len(text) - 2)
    chars = list(text)
    chars[i], chars[i + 1] = chars[i + 1], chars[i]
    return "".join(chars)


def augment(text: str, rnd: random.Random) -> str:
    t = " ".join(text.split())
    for full, shorts in ABBREV.items():
        if full in t and rnd.random() < 0.3:
            t = t.replace(full, rnd.choice(shorts))
    r = rnd.random()
    if r < 0.3:
        t = fold(t)  # gõ không dấu
    elif r < 0.4:
        t = t.lower()
    elif r < 0.45:
        t = t.capitalize()
    return _typo(t, rnd)


def category_samples(rnd: random.Random, per_category: int) -> list[dict]:
    rows = []
    for label, spec in CATEGORIES.items():
        seen: set[str] = set()
        attempts = 0
        while len(seen) < per_category and attempts < per_category * 20:
            attempts += 1
            item = rnd.choice(spec["items"])
            verb = rnd.choice(spec["verbs"])
            place = rnd.choice(spec["places"])
            pattern = rnd.random()
            if pattern < 0.25:
                text = item
            elif pattern < 0.45:
                text = f"{verb} {item}"
            elif pattern < 0.6:
                text = f"{item} {place}"
            elif pattern < 0.72:
                text = f"{verb} {item} ở {place}"
            elif pattern < 0.82:
                text = rnd.choice(spec["extra"])
            elif pattern < 0.9:
                text = place
            else:
                text = f"{item} {rnd.choice(COMPANIONS)}"
            if rnd.random() < 0.35:
                text = f"{text} {rnd.choice(TIME_WORDS)}"
            if rnd.random() < 0.3:
                text = f"{text} {rnd.choice(AMOUNTS)}"
            text = augment(text, rnd).strip()
            if text and text not in seen:
                seen.add(text)
                rows.append({"text": text, "label": label, "income": spec["income"]})
    return rows


def intent_samples(rnd: random.Random, per_intent: int) -> list[dict]:
    rows = []
    expense_items = [i for k, s in CATEGORIES.items() if not s["income"] for i in s["items"]]
    income_items = [i for k, s in CATEGORIES.items() if s["income"] for i in s["items"]]
    places = [p for s in CATEGORIES.values() for p in s["places"]]
    for label, templates in INTENT_TEMPLATES.items():
        seen: set[str] = set()
        attempts = 0
        while len(seen) < per_intent and attempts < per_intent * 30:
            attempts += 1
            tpl = rnd.choice(templates)
            items = income_items if label == "income" else expense_items
            text = tpl.format(
                item=rnd.choice(items), amount=rnd.choice([a for a in AMOUNTS if a] + [""]),
                verb=rnd.choice(["mua", "ăn", "trả", "đóng", "đi"]), time=rnd.choice(TIME_WORDS),
                place=rnd.choice(places), person=rnd.choice(PEOPLE), wallet=rnd.choice(WALLETS),
                wallet2=rnd.choice(WALLETS))
            text = augment(text, rnd).strip()
            if text and text not in seen:
                seen.add(text)
                rows.append({"text": text, "label": label})
    return rows


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="ml/data/generated")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--per-category", type=int, default=700)
    ap.add_argument("--per-intent", type=int, default=500)
    args = ap.parse_args(argv)
    rnd = random.Random(args.seed)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for name, rows in [("categories.jsonl", category_samples(rnd, args.per_category)),
                       ("intents.jsonl", intent_samples(rnd, args.per_intent))]:
        rnd.shuffle(rows)
        with (out / name).open("w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(f"{name}: {len(rows)} mẫu")


if __name__ == "__main__":
    main()

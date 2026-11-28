"""Đo độ chính xác của trợ lý trên bộ câu hỏi tiếng Việt.

python -m ml.evaluate_assistant            # trợ lý luật
python -m ml.evaluate_assistant --llm      # mô hình đang cấu hình (LLM_PROVIDER=ollama ...)
"""

from __future__ import annotations

import argparse
import asyncio
import json
import time
from collections import Counter

import httpx

from app.core.config import get_settings
from app.schemas.finance import FinanceSnapshot
from app.services.llm import rules
from app.services.llm.assistant import Assistant

from .data.assistant_eval import INTENT_TOOL, QUESTIONS


def snapshot() -> FinanceSnapshot:
    # tests.conftest xóa biến LLM_* khi nạp, nên chỉ nạp sau khi đã đọc cấu hình
    from tests.conftest import CATEGORIES, NOW, PEOPLE, WALLETS, make_transactions

    return FinanceSnapshot(
        now=NOW, wallets=WALLETS, categories=CATEGORIES, people=PEOPLE, transactions=make_transactions()
    )


def eval_rules() -> dict:
    wrong = [(q, want, got) for q, want in QUESTIONS if (got := rules.detect_intent(q)) != want]
    per = Counter(want for _, want in QUESTIONS)
    miss = Counter(want for _, want, _ in wrong)
    return {
        "mode": "rules",
        "questions": len(QUESTIONS),
        "accuracy": round(1 - len(wrong) / len(QUESTIONS), 3),
        "per_intent": {k: round(1 - miss[k] / n, 2) for k, n in sorted(per.items())},
        "wrong": wrong,
    }


async def eval_llm() -> dict:
    snap = snapshot()
    rows = []
    async with httpx.AsyncClient() as http:
        a = Assistant(http)
        for q, want in QUESTIONS:
            t0 = time.perf_counter()
            r = await a.chat(snap, [{"role": "user", "content": q}])
            rows.append(
                {
                    "question": q,
                    "want_tool": INTENT_TOOL[want],
                    "tools": r.tools_used,
                    "provider": r.provider,
                    "fallback": r.fallback_reason,
                    "seconds": round(time.perf_counter() - t0, 1),
                }
            )
    by_llm = [r for r in rows if r["provider"] != "rules"]
    hit = sum(r["want_tool"] in r["tools"] for r in rows)
    fallbacks = Counter(r["fallback"] for r in rows if r["fallback"])
    secs = sorted(r["seconds"] for r in rows)
    return {
        "mode": get_settings().llm_provider,
        "model": get_settings().llm_model or "qwen2.5:3b",
        "questions": len(rows),
        "tool_accuracy": round(hit / len(rows), 3),
        "answered_by_llm": len(by_llm),
        "fallbacks": dict(fallbacks),
        "median_seconds": secs[len(secs) // 2],
        "rows": rows,
    }


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--llm", action="store_true")
    args = ap.parse_args(argv)
    get_settings()
    result = asyncio.run(eval_llm()) if args.llm else eval_rules()
    print(json.dumps({k: v for k, v in result.items() if k not in ("rows", "wrong")}, ensure_ascii=False, indent=2))
    for row in result.get("wrong", []):
        print("SAI:", row)
    for row in result.get("rows", []):
        if row["want_tool"] not in row["tools"]:
            print("SAI:", row["question"], "| cần", row["want_tool"], "| đã gọi", row["tools"], row["fallback"] or "")


if __name__ == "__main__":
    main()

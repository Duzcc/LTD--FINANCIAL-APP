"""Huấn luyện, đánh giá và lưu các mô hình của AI service.

    python -m ml.train            # sinh dữ liệu (nếu chưa có), huấn luyện, ghi artifacts/
"""
from __future__ import annotations

import json
import platform
import time
from datetime import UTC, datetime
from pathlib import Path

import joblib
import numpy as np
import sklearn
from sklearn.metrics import accuracy_score, classification_report, f1_score
from sklearn.model_selection import GridSearchCV, StratifiedKFold, train_test_split

from .pipelines import text_classifier

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "ml" / "data"
ARTIFACTS = ROOT / "artifacts"


def load(path: Path) -> tuple[list[str], list[str]]:
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    return [r["text"] for r in rows], [r["label"] for r in rows]


def train_one(name: str, data_file: str, eval_file: str) -> dict:
    texts, labels = load(DATA / "generated" / data_file)
    x_train, x_test, y_train, y_test = train_test_split(texts, labels, test_size=0.2, random_state=42, stratify=labels)
    search = GridSearchCV(text_classifier(), {"clf__C": [2.0, 8.0, 32.0]},
                          cv=StratifiedKFold(3, shuffle=True, random_state=42), scoring="f1_macro", n_jobs=-1)
    t0 = time.time()
    search.fit(x_train, y_train)
    model = search.best_estimator_
    pred = model.predict(x_test)
    hx, hy = load(DATA / eval_file)
    hpred = model.predict(hx)
    extra_sets = {}
    for extra in sorted(DATA.glob(eval_file.replace(".jsonl", "_v*.jsonl"))):
        ex, ey = load(extra)
        ep = model.predict(ex)
        extra_sets[extra.stem] = {"size": len(ex), "accuracy": round(accuracy_score(ey, ep), 4),
                                  "f1_macro": round(f1_score(ey, ep, average="macro"), 4),
                                  "errors": [{"text": t, "label": a, "pred": str(b)}
                                             for t, a, b in zip(ex, ey, ep, strict=False) if a != b]}
    errors = [{"text": t, "label": y, "pred": str(p)} for t, y, p in zip(hx, hy, hpred, strict=False) if y != p]
    # Mô hình cuối cùng huấn luyện trên toàn bộ dữ liệu tổng hợp.
    model.fit(texts, labels)
    joblib.dump(model, ARTIFACTS / f"{name}.joblib", compress=3)
    return {
        "model": name,
        "algorithm": "TF-IDF (từ 1–2 + ký tự 2–5) + Logistic Regression (class_weight=balanced)",
        "best_params": search.best_params_,
        "train_size": len(texts),
        "labels": sorted(set(labels)),
        "synthetic_test": {"accuracy": round(accuracy_score(y_test, pred), 4),
                           "f1_macro": round(f1_score(y_test, pred, average="macro"), 4)},
        "handwritten_eval": {"size": len(hx), "accuracy": round(accuracy_score(hy, hpred), 4),
                             "f1_macro": round(f1_score(hy, hpred, average="macro"), 4)},
        "handwritten_report": classification_report(hy, hpred, output_dict=True, zero_division=0),
        "handwritten_errors": errors,
        "extra_eval": extra_sets,
        "train_seconds": round(time.time() - t0, 1),
    }


def main(argv: list[str] | None = None) -> None:
    del argv  # chưa có tham số dòng lệnh
    if not (DATA / "generated" / "categories.jsonl").exists():
        from .data import generate_dataset
        generate_dataset.main([])
    ARTIFACTS.mkdir(exist_ok=True)
    metrics = {
        "trained_at": datetime.now(UTC).isoformat(timespec="seconds"),
        "sklearn": sklearn.__version__, "numpy": np.__version__, "python": platform.python_version(),
        "categorizer": train_one("categorizer", "categories.jsonl", "eval_categories.jsonl"),
        "intent": train_one("intent", "intents.jsonl", "eval_intents.jsonl"),
    }
    (ARTIFACTS / "metrics.json").write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")
    for key in ("categorizer", "intent"):
        m = metrics[key]
        print(f"[{key}] synthetic acc={m['synthetic_test']['accuracy']} f1={m['synthetic_test']['f1_macro']} | "
              f"handwritten acc={m['handwritten_eval']['accuracy']} f1={m['handwritten_eval']['f1_macro']} "
              f"(n={m['handwritten_eval']['size']}) C={m['best_params']}")
        for e in m["handwritten_errors"][:15]:
            print("   sai:", e)
        for name, r in m["extra_eval"].items():
            print(f"   {name}: acc={r['accuracy']} f1={r['f1_macro']} (n={r['size']})")
            for e in r["errors"]:
                print("      sai:", e)


if __name__ == "__main__":
    main()

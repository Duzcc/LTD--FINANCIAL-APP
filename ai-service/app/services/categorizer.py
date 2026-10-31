"""Phân loại danh mục giao dịch: mô hình toàn cục + cá nhân hóa theo lịch sử người dùng.

P(c | x) = (1 - w)·P_toàn_cục(c | x) + w·P_cá_nhân(c | x)

- P_toàn_cục: TF-IDF + hồi quy logistic huấn luyện trên bộ dữ liệu tự xây dựng.
- P_cá_nhân: k láng giềng gần nhất (cosine) trên các ghi chú người dùng đã gán danh mục,
  hỗ trợ cả danh mục do người dùng tự tạo.
- w tăng theo độ giống của ghi chú gần nhất trong lịch sử (tối đa 0,9).
"""
from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

import numpy as np
from sklearn.preprocessing import normalize as l2

from app.schemas.common import Category, LabeledText

from .categories import global_label_for
from .registry import load_model


@dataclass
class Prediction:
    category_id: str
    probability: float


class Categorizer:
    def __init__(self) -> None:
        self.model = load_model("categorizer")
        self.features = self.model.named_steps["features"]
        self.labels: list[str] = list(self.model.classes_)

    def global_proba(self, texts: list[str]) -> np.ndarray:
        return self.model.predict_proba(texts)

    def predict(self, text: str, categories: list[Category], history: list[LabeledText] | None = None,
                income: bool | None = None, top_k: int = 3) -> tuple[list[Prediction], dict]:
        allowed = [c for c in categories if income is None or c.income == income]
        if not allowed:
            return [], {"personal_weight": 0.0}
        scores = {c.id: 0.0 for c in allowed}

        # 1) Mô hình toàn cục, ánh xạ nhãn chuẩn -> danh mục của người dùng
        g = self.global_proba([text])[0]
        mapping: dict[str, list[str]] = {}
        for c in allowed:
            label = global_label_for(c.id, c.name)
            if label:
                mapping.setdefault(label, []).append(c.id)
        global_scores = {cid: 0.0 for cid in scores}
        for i, label in enumerate(self.labels):
            for cid in mapping.get(label, []):
                global_scores[cid] += float(g[i]) / len(mapping[label])
        total = sum(global_scores.values())
        if total > 0:
            global_scores = {k: v / total for k, v in global_scores.items()}

        # 2) Cá nhân hóa bằng kNN trên lịch sử
        personal_scores = {cid: 0.0 for cid in scores}
        weight = 0.0
        hist = [h for h in (history or []) if h.categoryId in scores and h.text.strip()][-2000:]
        if hist:
            mat = l2(self.features.transform([h.text for h in hist]))
            q = l2(self.features.transform([text]))
            sims = (mat @ q.T).toarray().ravel()
            order = np.argsort(-sims)[:7]
            for i in order:
                if sims[i] >= 0.3:
                    personal_scores[hist[i].categoryId] += float(sims[i]) ** 2
            ptotal = sum(personal_scores.values())
            if ptotal > 0:
                personal_scores = {k: v / ptotal for k, v in personal_scores.items()}
                weight = min(0.9, float(sims[order[0]]) ** 1.5)

        if total == 0 and weight == 0:
            # Chỉ có danh mục tự tạo và chưa có lịch sử: không đủ căn cứ
            return [], {"personal_weight": 0.0}
        if total == 0:
            weight = 1.0
        for cid in scores:
            scores[cid] = (1 - weight) * global_scores[cid] + weight * personal_scores[cid]
        s = sum(scores.values()) or 1.0
        ranked = sorted(((cid, v / s) for cid, v in scores.items()), key=lambda x: -x[1])[:top_k]
        return [Prediction(cid, round(p, 4)) for cid, p in ranked], {"personal_weight": round(weight, 3)}


@lru_cache
def get_categorizer() -> Categorizer:
    return Categorizer()

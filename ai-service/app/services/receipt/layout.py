from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass
class OcrBox:
    text: str
    x: float
    y: float
    w: float
    h: float
    confidence: float = 1.0
    angle: float | None = None


def estimate_skew(boxes: list[OcrBox]) -> float:
    with_angle = [b for b in boxes if b.angle is not None and b.w > 3 * b.h]
    if not with_angle:
        return 0.0
    longest = max(b.w for b in with_angle)
    angles = sorted(b.angle for b in with_angle if b.w >= 0.4 * longest)
    return angles[len(angles) // 2]


def group_rows(boxes: list[OcrBox], skew: float | None = None) -> list[str]:
    boxes = [b for b in boxes if b.text.strip() and b.h > 0]
    if not boxes:
        return []
    if skew is None:
        skew = estimate_skew(boxes)
    cos, sin = math.cos(-skew), math.sin(-skew)

    def center(b: OcrBox) -> tuple[float, float]:
        cx, cy = b.x + b.w / 2, b.y + b.h / 2
        return cx * cos - cy * sin, cx * sin + cy * cos

    items = sorted(((center(b), b) for b in boxes), key=lambda it: it[0][1])
    rows: list[list[tuple[tuple[float, float], OcrBox]]] = []
    for (cx, cy), b in items:
        placed = False
        for row in reversed(rows[-3:]):
            ry = sum(c[1] for c, _ in row) / len(row)
            rh = sum(x.h for _, x in row) / len(row)
            if abs(cy - ry) <= 0.55 * min(rh, b.h):
                row.append(((cx, cy), b))
                placed = True
                break
        if not placed:
            rows.append([((cx, cy), b)])
    out = []
    for row in rows:
        row.sort(key=lambda it: it[0][0])
        out.append("  ".join(b.text.strip() for _, b in row))
    return out

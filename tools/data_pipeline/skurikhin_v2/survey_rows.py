"""Инвентаризация форматов строк левых страниц Таблиц 1-12."""
from __future__ import annotations

import collections
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import parse_ocr as P  # noqa: E402

shapes = collections.Counter()
examples: dict[str, list[tuple[int, str]]] = {}


def shape(cells: list[str]) -> str:
    out = []
    for c in cells:
        if c == "":
            out.append(".")
        elif re.fullmatch(r"\d{1,3}", c):
            out.append("N")
        elif re.fullmatch(r"\d{1,3}\s*\(\d{1,3}\)", c):
            out.append("Nm")
        elif re.fullmatch(r"-?\d+[.,]\d+", c):
            out.append("f")
        elif re.fullmatch(r"-?\d+[.,]\d+\s*\(.*\)", c):
            out.append("fbr")
        elif c.startswith("%"):
            out.append("%")
        elif P.CODE_RE.match(c):
            out.append("CODE")
        else:
            out.append("T")
    return " ".join(out)


for page in range(25, 195, 2):
    table = P.read_table(P.OCR_DIR / f"p{page:03d}.md")
    if table is None:
        print("no table", page)
        continue
    for tr in table.findall(".//tbody/tr"):
        cells = P.expand(P.row_cells(tr), P.colspans(tr))
        if not cells or all(c == "" for c in cells):
            continue
        s = shape(cells)
        shapes[s] += 1
        examples.setdefault(s, [])
        if len(examples[s]) < 3:
            examples[s].append((page, " | ".join(cells)))

for s, n in shapes.most_common(60):
    print(f"{n:5d}  {s}")
    for page, ex in examples[s][:2]:
        print(f"        p{page}: {ex[:150]}")

"""Сборка data/bls_v4/bls_products.json из официальной базы BLS 4.0.

Формат питательных веществ — тот же, что у `skurikhin_products.json`
(`nutrients[key] = {value, unit, label}`), плюс `source: "bls4"`.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import openpyxl

import mapping as MP
import polish_bls as POLISH

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "data" / "bls_v4"
RAW_XLSX = DATA / "raw" / "BLS_4_0_2025_DE" / "BLS_4_0_Daten_2025_DE.xlsx"
CACHE = DATA / "translations_cache.jsonl"
OUT = DATA / "bls_products.json"

MISSING_TOKENS = {"-", "", "tr", "<lod", "<loq", "<lod or <loq", "n/a"}


def num(value):
    """Число или None; спецтокены BLS («-», «<LOD», «TR») -> None."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    s = str(value).strip()
    if s.lower() in MISSING_TOKENS:
        return None
    s = s.replace(",", ".").replace("<", "").replace(">", "").strip()
    try:
        v = float(s)
    except ValueError:
        return None
    if math.isnan(v):
        return None
    return v


def header_map(head: list) -> tuple[dict[str, int], dict[str, int]]:
    """Два словаря: {BLS-код: столбец значения} и {имя: столбец}.

    В книге каждый показатель занимает три столбца подряд
    («WERT Wert [ед.]», «WERT Datenherkunft», «WERT Referenz»), поэтому
    позиционный `dict` по первому слову шапки указывает на служебный столбец.
    Значение берём из самого первого вхождения кода (в нём есть «[…]»).
    """
    values: dict[str, int] = {}
    names: dict[str, int] = {}
    for i, h in enumerate(head):
        if not h:
            continue
        names.setdefault(h, i)
        key = h.split(" ")[0]
        if "Datenherkunft" in h or "Referenz" in h:
            continue
        values.setdefault(key, i)
    return values, names


def load_translations() -> dict[str, dict]:
    done: dict[str, dict] = {}
    if not CACHE.exists():
        return done
    for line in CACHE.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        for item in rec.get("data") or []:
            code = str(item.get("bls_code") or "").strip()
            if code and str(item.get("name_ru") or "").strip():
                done[code] = item
    return done


def main() -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    tr = load_translations()
    print(f"переводов в кэше: {len(tr)}")

    wb = openpyxl.load_workbook(RAW_XLSX, read_only=True, data_only=True)
    ws = wb[wb.sheetnames[0]]
    rows = ws.iter_rows(values_only=True)
    head = list(next(rows))
    col, named = header_map(head)
    col["BLS Code"] = named["BLS Code"]
    col["Lebensmittelbezeichnung"] = named["Lebensmittelbezeichnung"]
    col["Food name"] = named["Food name"]

    products = []
    missing_translation = 0
    for r in rows:
        code = (r[col["BLS Code"]] or "").strip()
        if not code:
            continue
        nutrients = {}
        present = 0
        for bls_key, (key, unit, label) in MP.NUTRIENTS.items():
            v = num(r[col[bls_key]])
            if v is None:
                continue
            present += 1
            nutrients[key] = {"value": round(v, 4), "unit": unit,
                              "label": label}
        t = tr.get(code) or {}
        if not t:
            missing_translation += 1
        products.append({
            "code": code,
            "name": t.get("name_ru") or (r[col["Lebensmittelbezeichnung"]] or "").strip(),
            "name_de": (r[col["Lebensmittelbezeichnung"]] or "").strip(),
            "name_en": (r[col["Food name"]] or "").strip(),
            "name_ru": t.get("name_ru"),
            "synonyms": t.get("synonyms_ru") or [],
            "category": MP.category_of(code),
            "category_letter": code[0].upper(),
            "basis": "per_100g",
            "nutrients": {k: nutrients[k] for k in MP.ORDER if k in nutrients},
            "nutrients_present": present,
            "source": "bls4",
        })

    products.sort(key=lambda p: p["code"])
    # Финальная полировка: первая буква названия — заглавная (категории
    # берутся из `mapping.CATEGORIES`, где буквы E/U/V/W уже исправлены).
    polished = POLISH.polish_payload({"products": products})
    meta = {
        "source": "BLS 4.0 (Bundeslebensmittelschlüssel), декабрь 2025",
        "license": "CC BY 4.0",
        "url": "https://www.blsdb.de/download",
        "count": len(products),
        "nutrient_count": len(MP.ORDER),
        "translated": len(products) - missing_translation,
        "missing_translation": missing_translation,
        "polished": polished,
    }
    OUT.write_text(json.dumps({"products": products, "meta": meta},
                              ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"записано: {OUT}")
    print(f"продуктов: {len(products)}, без перевода: {missing_translation}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    main()

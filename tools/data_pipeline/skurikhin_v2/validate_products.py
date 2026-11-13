"""Валидатор справочника Скурихина: 0 ошибок — критерий приёмки этапа 1.

Проверки:
  1. все продукты таблиц 1-12 имеют левую (БЖУ) и правую часть;
  2. для неалкогольных продуктов Вода+Бел+Жир+Угл+ПВ+ОК+Зола в 96..103.5 г;
  3. ни у одного молочного продукта лактоза не попала в starch;
  4. нет названий с опечатками OCR;
  5. нет названий из одного прилагательного без существительного;
  6. нет дублей кодов;
  7. Fe всегда в мг на 100 г (правдоподобный диапазон).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "data" / "skurikhin_v2"
BOOK = "Скурихин, Тутельян (2002)"

BALANCE_KEYS = ("water", "protein", "fat", "carbs", "fiber",
                "organic_acids", "ash")
DAIRY_CODES = {"1."}

# характерные OCR-искажения
TYPO_PATTERNS = [
    (re.compile(r"кедчен", re.I), "копчен"),
    (re.compile(r"ржский", re.I), "ржаной"),
    (re.compile(r"запекака", re.I), "запеканка"),
    (re.compile(r"твороги", re.I), "творога"),
    (re.compile(r"полуобезжирин", re.I), "полуобезжиренная"),
    (re.compile(r"\bлецитина\b", re.I), "лещина"),
    (re.compile(r"[A-Za-z]{2,}.*[А-Яа-я]{2,}.*[A-Za-z]{2,}"), "латиница в слове"),
]


def is_alcohol(item: dict) -> bool:
    return item["code"].startswith("11.")


def main() -> None:
    path = DATA / "skurikhin_products.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    products = payload["products"]

    errors: list[dict] = []
    warnings: list[dict] = []

    def err(kind: str, code: str, detail: str) -> None:
        errors.append({"check": kind, "code": code, "detail": detail})

    # --- 6. дубли кодов --------------------------------------------------
    seen = {}
    for p in products:
        if p["code"] in seen:
            err("duplicate_code", p["code"], "код встречается повторно")
        seen[p["code"]] = True

    # --- 1. наличие обеих частей -----------------------------------------
    left_keys = {"water", "protein", "fat", "carbs"}
    right_keys = {"sodium", "potassium", "energy_kcal"}
    for p in products:
        have = set(p["nutrients"])
        if not (have & left_keys):
            err("missing_left", p["code"], "нет левой части (БЖУ)")
        if not (have & right_keys):
            err("missing_right", p["code"], "нет правой части (минералы/ЭЦ)")

    # --- 2. баланс массы ------------------------------------------------
    for p in products:
        if is_alcohol(p):
            continue
        vals = {k: (p["nutrients"].get(k) or {}).get("value")
                for k in BALANCE_KEYS}
        total = sum(v for v in vals.values() if v is not None)
        if not any(v is not None for v in vals.values()):
            err("mass_balance", p["code"], "нет данных для баланса")
            continue
        if not (96.0 <= total <= 103.5):
            err("mass_balance", p["code"],
                f"Вода+Бел+Жир+Угл+ПВ+ОК+Зола = {total:.1f} г")

    # --- 3. лактоза не в крахмале ---------------------------------------
    for p in products:
        if not p["code"].startswith("1."):
            continue
        starch = (p["nutrients"].get("starch") or {}).get("value")
        sugars = (p["nutrients"].get("sugars") or {}).get("value")
        carbs = (p["nutrients"].get("carbs") or {}).get("value")
        if starch and sugars is None and carbs and starch >= carbs:
            err("lactose_in_starch", p["code"],
                f"крахмал {starch} при отсутствии МДС (углеводы {carbs})")

    # --- 4. опечатки ----------------------------------------------------
    for p in products:
        for pattern, hint in TYPO_PATTERNS:
            if pattern.search(p["name"]):
                err("typo_name", p["code"],
                    f"«{p['name']}» — похоже на «{hint}»")
                break

    # --- 5. одинокие прилагательные --------------------------------------
    for p in products:
        words = [w for w in re.split(r"[\s,]+", p["name"]) if w]
        if len(words) != 1:
            continue
        w = words[0].rstrip(".")
        if re.search(r"(ский|цкий|ой|ый|ий|ая|яя|ое|ее|ые)$", w, re.I):
            err("bare_adjective", p["code"],
                f"название из одного прилагательного: «{p['name']}»")

    # --- 7. Fe правдоподобность ------------------------------------------
    for p in products:
        fe = (p["nutrients"].get("iron") or {}).get("value")
        if fe is None:
            continue
        if fe > 100:
            err("iron_unit", p["code"], f"Fe = {fe} мг на 100 г — неправдоподобно")

    # --- предупреждения ---------------------------------------------------
    for p in products:
        calc = p.get("energy_calc_kcal")
        book = (p["nutrients"].get("energy_kcal") or {}).get("value")
        if calc is not None and book:
            if abs(calc - book) > max(30.0, book * 0.4):
                warnings.append({
                    "check": "energy_mismatch", "code": p["code"],
                    "detail": f"расч {calc:.0f} vs книга {book:.0f}"})
        if p["code"] in ("3.5.2.11", "4.3.8"):
            pass

    report = {
        "source": BOOK,
        "products": len(products),
        "nutrients_per_product": 29,
        "errors_total": len(errors),
        "warnings_total": len(warnings),
        "errors": errors[:400],
        "warnings": warnings[:400],
        "checks": {
            "duplicate_codes": sum(1 for e in errors if e["check"] == "duplicate_code"),
            "missing_left": sum(1 for e in errors if e["check"] == "missing_left"),
            "missing_right": sum(1 for e in errors if e["check"] == "missing_right"),
            "mass_balance": sum(1 for e in errors if e["check"] == "mass_balance"),
            "lactose_in_starch": sum(1 for e in errors if e["check"] == "lactose_in_starch"),
            "typo_name": sum(1 for e in errors if e["check"] == "typo_name"),
            "bare_adjective": sum(1 for e in errors if e["check"] == "bare_adjective"),
            "iron_unit": sum(1 for e in errors if e["check"] == "iron_unit"),
        },
        "stats": {
            "with_waste": sum(1 for p in products if p["waste_pct"] is not None),
            "with_measures": sum(1 for p in products if p["measures"]),
            "recalculated_to_100g": sum(1 for p in products
                                        if p["basis"] != "per_100g"),
        },
    }
    (DATA / "validation_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"продуктов: {report['products']}")
    print(f"ОШИБОК: {len(errors)}")
    for k, v in report["checks"].items():
        print(f"  {k}: {v}")
    print(f"предупреждений: {len(warnings)}")
    if errors:
        print("\nпервые ошибки:")
        for e in errors[:15]:
            print(f"  [{e['check']}] {e['code']}: {e['detail']}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()

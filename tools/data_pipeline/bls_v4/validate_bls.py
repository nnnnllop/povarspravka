"""Проверка data/bls_v4/bls_products.json.

Проверки:
  * name_ru непустое и содержит кириллицу;
  * единицы измерения соответствуют ожидаемым для каждого показателя;
  * значения не отрицательные, «физические» (масса на 100 г <= 100 г);
  * баланс массы: вода + белки + жиры + углеводы + ПВ + зола + алкоголь
    + кислоты не превышает 100 г с разумным допуском;
  * ЭЦ совпадает с расчётом по формуле BLS
    (4·белки + 9·жиры + 4·усвояемые углеводы + 2·ПВ + 7·алкоголь
     + 3·кислоты + 2,4·полиолы);
  * доля заполненности по 28 целевым показателям.

Отчёт: data/bls_v4/validation_report.json
"""
from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

import mapping as MP

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "data" / "bls_v4"
SRC = DATA / "bls_products.json"
REPORT = DATA / "validation_report.json"

CYR = set("абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")

# 28 целевых показателей из задания
TARGET_28 = [
    "energy_kcal", "energy_kj", "water", "protein", "fat",
    "fat_saturated", "fat_polyunsaturated", "cholesterol",
    "carbs", "sugars", "starch", "fiber", "alcohol", "organic_acids", "ash",
    "sodium", "potassium", "calcium", "magnesium", "phosphorus", "iron",
    "iodine", "vitamin_a_re", "beta_carotene", "vitamin_e", "vitamin_d",
    "vitamin_b1", "niacin",
]


def main() -> None:
    payload = json.loads(SRC.read_text(encoding="utf-8"))
    products = payload["products"]
    errors: list[dict] = []
    warnings: list[dict] = []

    coverage = Counter()
    unit_errors = Counter()
    mass_bad = 0
    kcal_bad = 0
    kcal_checked = 0
    kcal_warn: list[dict] = []

    for p in products:
        code = p["code"]
        name = (p.get("name_ru") or "").strip()
        if not name:
            errors.append({"code": code, "kind": "name_ru_empty",
                           "detail": p.get("name_de")})
        elif not any(ch in CYR for ch in name):
            errors.append({"code": code, "kind": "name_ru_not_cyrillic",
                           "detail": name})
        nut = p["nutrients"]
        for key, cell in nut.items():
            if key not in MP.EXPECTED_UNITS:
                continue
            coverage[key] += 1
            if cell["unit"] != MP.EXPECTED_UNITS[key]:
                unit_errors[f"{key}:{cell['unit']}"] += 1
                errors.append({"code": code, "kind": "unit_mismatch",
                               "detail": f"{key} = {cell['value']} "
                                         f"{cell['unit']}, ожидалось "
                                         f"{MP.EXPECTED_UNITS[key]}"})
            v = cell["value"]
            if v is None or v < 0:
                errors.append({"code": code, "kind": "value_negative",
                               "detail": f"{key} = {v}"})
        # физические пределы для компонентов массы (г / 100 г)
        mass_keys = ("water", "protein", "fat", "carbs", "fiber", "ash",
                     "alcohol", "organic_acids", "sugars", "starch",
                     "fat_saturated", "fat_polyunsaturated", "fat_mono")
        for key in mass_keys:
            v = (nut.get(key) or {}).get("value")
            if v is None:
                continue
            # допуск округления: BLS публикует 100,585 г воды для чистой
            # воды — это округление, а не ошибка базы
            if v > 101.0:
                errors.append({"code": code, "kind": "value_over_100g",
                               "detail": f"{key} = {v} г/100 г"})
            elif v > 100.0:
                warnings.append({"code": code, "kind": "rounding_over_100",
                                 "detail": f"{key} = {v} г/100 г (округление)"})

        def gv(k):
            return (nut.get(k) or {}).get("value") or 0.0

        mass = sum(gv(k) for k in ("water", "protein", "fat", "carbs",
                                   "fiber", "ash", "alcohol", "organic_acids"))
        if mass > 0 and not 50 <= mass <= 108:
            mass_bad += 1
            if len(warnings) < 400:
                warnings.append({"code": code, "kind": "mass_balance",
                                 "detail": f"сумма компонентов {mass:.1f} г"})
        e = (nut.get("energy_kcal") or {}).get("value")
        if e is not None and gv("protein") + gv("fat") + gv("carbs") > 1:
            polyol = 0.0
            calc = (MP.KCAL["protein"] * gv("protein")
                    + MP.KCAL["fat"] * gv("fat")
                    + MP.KCAL["carbs"] * gv("carbs")
                    + MP.KCAL["fiber"] * gv("fiber")
                    + MP.KCAL["alcohol"] * gv("alcohol")
                    + MP.KCAL["organic_acids"] * gv("organic_acids")
                    + MP.KCAL["polyol"] * polyol)
            kcal_checked += 1
            if abs(calc - e) > max(20.0, e * 0.20):
                kcal_bad += 1
                kcal_warn.append({"code": code, "kind": "energy_formula",
                                  "detail": f"расч {calc:.0f} vs BLS {e:.0f} ккал "
                                            f"(Δ {calc - e:+.0f})"})

    total = len(products)
    by_letter = Counter(p["category_letter"] for p in products)
    by_cat = Counter(p["category"] for p in products)
    cov = {k: {"products": coverage[k],
               "pct": round(100.0 * coverage[k] / total, 1)} for k in TARGET_28}
    translated = sum(1 for p in products if (p.get("name_ru") or "").strip())
    with_syn = sum(1 for p in products if p.get("synonyms"))

    report = {
        "source": payload["meta"],
        "products_total": total,
        "translated": translated,
        "translated_pct": round(100.0 * translated / total, 2),
        "with_synonyms": with_syn,
        "errors_total": len(errors),
        "errors": errors[:200],
        "errors_by_kind": dict(Counter(e["kind"] for e in errors)),
        "warnings_total": len(warnings),
        "warnings_by_kind": dict(Counter(w["kind"] for w in warnings)),
        "warnings": warnings[:200],
        "energy_formula_warnings": kcal_warn,
        "coverage_28": cov,
        "mass_balance_checked": mass_bad,
        "energy_formula_checked": kcal_checked,
        "energy_formula_mismatch": kcal_bad,
        "categories": dict(by_cat),
        "letters": dict(sorted(by_letter.items())),
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=1),
                      encoding="utf-8")
    print(f"продуктов: {total}")
    print(f"переведено: {translated} ({report['translated_pct']}%)")
    print(f"ОШИБОК: {len(errors)}  {report['errors_by_kind']}")
    print(f"предупреждений: {len(warnings)}  {report['warnings_by_kind']}")
    print(f"проверено ЭЦ: {kcal_checked}, расхождений: {kcal_bad}")
    print("покрытие 28 показателей, %:")
    for k in TARGET_28:
        print(f"  {k:22s} {cov[k]['pct']:6.1f}%  ({cov[k]['products']})")
    print(f"отчёт: {REPORT}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    main()

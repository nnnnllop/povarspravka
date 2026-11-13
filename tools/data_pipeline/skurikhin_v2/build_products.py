"""Сборка итогового справочника: skurikhin_products.json / .csv.

Слой поверх assemble.py: канонические названия из LLM, меры из приложения 2,
несъедобная часть из приложения 1, пересчёт бутербродов на 100 г.
"""
from __future__ import annotations

import csv
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import parse_ocr as P  # noqa: E402
import polish_products as POLISH  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "data" / "skurikhin_v2"
INSPECT = Path(
    os.environ.get("SKURIKHIN_INSPECT_DIR") or (OUT / "_inspect")
)

# бутерброды: пересчёт с порции на 100 г
SANDWICHES = {"3.5.2.11", "3.6.1.16", "4.1.1.6", "4.1.1.19", "4.1.6.4",
              "4.3.8", "4.3.9"}

NUTRIENT_ORDER = [
    "water", "protein", "fat", "fat_saturated", "fat_polyunsaturated",
    "cholesterol", "sugars", "starch", "carbs", "fiber", "organic_acids",
    "ash", "sodium", "potassium", "calcium", "magnesium", "phosphorus",
    "iron", "vitamin_a", "beta_carotene", "vitamin_a_re", "vitamin_e",
    "vitamin_b1", "vitamin_b2", "niacin", "niacin_equivalent", "vitamin_c",
    "alcohol", "energy_kcal",
]
UNITS = {
    "water": "g", "protein": "g", "fat": "g", "fat_saturated": "g",
    "fat_polyunsaturated": "g", "cholesterol": "mg", "sugars": "g",
    "starch": "g", "carbs": "g", "fiber": "g", "organic_acids": "g",
    "ash": "g", "sodium": "mg", "potassium": "mg", "calcium": "mg",
    "magnesium": "mg", "phosphorus": "mg", "iron": "mg", "vitamin_a": "mcg",
    "beta_carotene": "mcg", "vitamin_a_re": "mcg", "vitamin_e": "mg",
    "vitamin_b1": "mg", "vitamin_b2": "mg", "niacin": "mg",
    "niacin_equivalent": "mg", "vitamin_c": "mg", "alcohol": "g",
    "energy_kcal": "kcal",
}
LABELS = {
    "water": "Вода, г", "protein": "Белки, г", "fat": "Жиры, г",
    "fat_saturated": "НЖК, г", "fat_polyunsaturated": "ПНЖК, г",
    "cholesterol": "Холестерин, мг", "sugars": "МДС, г",
    "starch": "Крахмал, г", "carbs": "Углеводы, г", "fiber": "ПВ, г",
    "organic_acids": "ОК, г", "ash": "Зола, г", "sodium": "Na, мг",
    "potassium": "K, мг", "calcium": "Ca, мг", "magnesium": "Mg, мг",
    "phosphorus": "P, мг", "iron": "Fe, мг", "vitamin_a": "A, мкг",
    "beta_carotene": "β-каротин, мкг", "vitamin_a_re": "РЭ, мкг",
    "vitamin_e": "TЭ, мг", "vitamin_b1": "B1, мг", "vitamin_b2": "B2, мг",
    "niacin": "PP, мг", "niacin_equivalent": "НЭ, мг", "vitamin_c": "C, мг",
    "alcohol": "Алкоголь, г", "energy_kcal": "ЭЦ, ккал",
}
# ручные правки названий по результатам сверки со сканами
NAME_OVERRIDES = {
    "7.2.4": "Орех лещина (фундук лесной)",   # скан: «Лешина»
    "7.2.2": "Орех грецкий",
    # OCR-опечатки, найденные при разборе таблиц 4–11 (см. validation_report)
    "4.1.6.2": "Горбуша отварная по 1-342",
    "4.1.6.5": "Горбуша натуральная. Консервы",
    "4.1.6.6": "Горбуша в томатном соусе. Консервы",
    "5.4.4": "Масло какао",
    "10.2.3": "Карамель с молочной начинкой",
    "11.2.2.2": "Вина полусухие белые и красные (в т.ч. шампанское)",
    "11.2.2.6": "Вина виноградные полудесертные",
    "11.2.2.7": "Вина виноградные десертные",
    "11.2.3.1": "Настойка горькая «Русский сувенир»",
}

# продукты, к которым несъедобная часть НЕ применяется
NO_WASTE_PREFIX = ("по 1-", "по 2-")


def norm_key(s: str) -> str:
    s = s.lower().replace("ё", "е")
    s = re.sub(r"«|»|\"|\(|\)|,", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def load_waste() -> dict[str, float]:
    path = INSPECT / "appendix1_waste.json"
    if not path.exists():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {norm_key(k): v["waste_pct"] for k, v in raw.items()}


def load_measures() -> dict[str, list[dict]]:
    path = INSPECT / "appendix2_measures.json"
    if not path.exists():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {norm_key(k): v["measures"] for k, v in raw.items()}


def is_finished(name: str) -> bool:
    """Готовое блюдо/изделие — несъедобная часть не нормируется.

    Правило: waste_pct допускается только для сырья (овощи, мясо, рыба в
    чешуе/панцире, яйцо в скорлупе). Колбасы, консервы, сыры, хлеб, масло,
    молоко, сахар и готовые блюда получают null, даже если в приложении 1
    для похожего названия есть значение.
    """
    low = name.lower()
    markers = ("по 1-", "по 2-", "консерв", "сыр", "колбас", "сосиск",
               "сардельк", "окорок", "буженин", "ветчин", "хлеб",
               "бутерброд", "салат", "суп", "борщ", "соус", "заправк",
               "котлет", "биточк", "пельмен", "вареник", "запекан",
               "пудинг", "каша", "гарнир", "масло", "сахар", "молоко",
               "сливк", "сметан", "творог", "кефир", "сок", "напиток",
               "компот", "кисель", "варенье", "джем",
               "мармелад", "карамел", "конфет", "печенье", "торт",
               "пирожное", "пирог", "булк", "батон", "макарон", "вермишел",
               "паштет", "зефир", "халва", "икра", "балык", "копчен")
    return any(m in low for m in markers)


def main() -> None:
    raw = json.loads((INSPECT / "assembled_raw.json").read_text(encoding="utf-8"))
    products = raw["products"]
    sections = raw["sections"]
    raw = json.loads((INSPECT / "names_llm.json").read_text(encoding="utf-8"))
    names = {e["code"]: e for e in raw}
    waste = load_waste()
    measures = load_measures()
    # умное сопоставление с приложениями 1–3 (appendix_map.py)
    amap = {}
    mp = INSPECT / "appendix_mapping.json"
    if mp.exists():
        amap = json.loads(mp.read_text(encoding="utf-8"))

    out = []
    for p in products:
        code = p["code"]
        n = names.get(code, {})
        name = n.get("name") or p["name_raw"]
        name = NAME_OVERRIDES.get(code, name)
        values = dict(p["values"])
        portion = p.get("portion")
        notes: list[str] = []

        # --- бутерброды: пересчёт на 100 г -------------------------------
        basis = "per_100g"
        base_portion = None
        if code in SANDWICHES and portion and float(portion) > 0:
            # В книге бутерброды даны на порцию; пересчитываем ВСЕ показатели
            # на 100 г продукта (умножаем на 100/масса порции)
            k = 100.0 / float(portion)
            base_portion = float(portion)
            for key, v in list(values.items()):
                if v is None:
                    continue
                values[key] = round(float(v) * k, 2)
            basis = "per_100g_recalc"
            notes.append(f"пересчитано с порции {base_portion:g} г на 100 г")
            # ЭЦ книги тоже дана на порцию — приводим её к 100 г тем же
            # коэффициентом, иначе она остаётся втрое-вдвое больше расчётной
            calc = p.get("energy_calc")
            book = p.get("energy_book")
            if calc is not None:
                calc = round(float(calc) * k, 1)
            if book is not None:
                book = round(float(book) * k, 1)
            p["energy_calc"] = calc
            p["energy_book"] = book
            values["energy_kcal"] = book

        # --- несъедобная часть ------------------------------------------
        # Сопоставление с приложением 1 идёт двумя путями:
        #   1) по ИСХОДНОМУ названию (то, что видел OCR в книге);
        #   2) после полировки названий — `polish.fix_measures` применяет
        #      `BASE_WASTE` уже по ИТОГОВЫМ названиям («Корнеплоды. Морковь»
        #      → «Морковь»). Раньше этот шаг стоял до переименования, и
        #      17 базовых овощей/фруктов/грибов оставались без отходов (H1).
        waste_pct = None
        piece_g: list[float] = []
        amap_rec = amap.get(code) or {}
        if not is_finished(name) and portion and not any(
                s in name.lower() for s in NO_WASTE_PREFIX):
            waste_pct = waste.get(norm_key(name))
            if waste_pct is None and n.get("name_fixed"):
                waste_pct = waste.get(norm_key(n["name_fixed"]))
            if waste_pct is None and amap_rec.get("waste_pct") is not None:
                waste_pct = amap_rec["waste_pct"]

        # --- меры ---------------------------------------------------------
        meas = measures.get(norm_key(name)) or measures.get(
            norm_key(p["name_raw"]))
        meas_list = list(meas) if meas else []
        if not meas_list and amap_rec.get("measures"):
            meas_list = [dict(m) for m in amap_rec["measures"]]
        # масса 1 штуки (приложение 3) -> запись меры «1 шт.»
        for g in amap_rec.get("piece_g") or []:
            meas_list.append({"name": "1 шт.", "grams": g})
        piece_g = list(amap_rec.get("piece_g") or [])
        if code in SANDWICHES and base_portion:
            meas_list.insert(0, {"name": "порция (бутерброд)",
                                 "grams": base_portion})

        nutrients = {}
        for key in NUTRIENT_ORDER:
            if key not in values:
                continue
            v = values[key]
            nutrients[key] = {"value": v, "unit": UNITS[key],
                              "label": LABELS[key]}

        out.append({
            "code": code,
            "name": name,
            "name_raw": p["name_raw"],
            # номер таблицы книги 1..12 — первая цифра кода
            "table": int(code.split(".")[0]) if code.split(".")[0].isdigit() else None,
            "section_path": p.get("section_path") or [],
            "basis": basis,
            "portion_g": base_portion or (float(portion) if portion else None),
            "nutrients": nutrients,
            "waste_pct": waste_pct,
            "piece_g": piece_g,
            "measures": meas_list,
            "synonyms": n.get("synonyms") or [],
            "energy_calc_kcal": p.get("energy_calc"),
            "energy_calc_scaled": code in SANDWICHES,
            "energy_book_kcal": p.get("energy_book"),
            "source": {"book": "Скурихин, Тутельян (2002)",
                       "page_left": p.get("page_left"),
                       "page_right": p.get("page_right")},
            "notes": notes,
        })

    # дубликаты по коду
    seen, unique = set(), []
    for item in out:
        if item["code"] in seen:
            continue
        seen.add(item["code"])
        unique.append(item)
    unique.sort(key=lambda x: [int(t) if t.isdigit() else 0
                               for t in x["code"].split(".")])

    # финальная полировка (этап 3): порционные строки правой страницы,
    # сдвиг p142, технические префиксы названий, меры и отходы
    polish_stats = POLISH.polish_payload({"products": unique})
    problems = POLISH.check({"products": unique})
    if problems:
        raise SystemExit("полировка не сошлась: " + "; ".join(problems[:10]))

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "skurikhin_products.json").write_text(
        json.dumps({"products": unique, "sections": sections,
                    "meta": {"source": "Скурихин В.А., Тутельян В.А. "
                                       "«Химический состав российских пищевых "
                                       "продуктов», 2002",
                             "count": len(unique),
                             "nutrient_count": len(NUTRIENT_ORDER),
                             "polished": polish_stats}},
                   ensure_ascii=False, indent=1), encoding="utf-8")

    # CSV
    cols = ["code", "name", "section_path", "basis", "portion_g",
            "waste_pct"] + NUTRIENT_ORDER + ["energy_calc_kcal", "measures"]
    with (OUT / "skurikhin_products.csv").open("w", encoding="utf-8-sig",
                                               newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        for item in unique:
            row = {"code": item["code"], "name": item["name"],
                   "section_path": " / ".join(item["section_path"]),
                   "basis": item["basis"], "portion_g": item["portion_g"],
                   "waste_pct": item["waste_pct"],
                   "energy_calc_kcal": item["energy_calc_kcal"],
                   "measures": "; ".join(
                       f"{m['name']}={m['grams']:g}" for m in item["measures"])}
            for k in NUTRIENT_ORDER:
                row[k] = item["nutrients"].get(k, {}).get("value")
            w.writerow(row)

    print(f"продуктов: {len(unique)}")
    print(f"с мерами: {sum(1 for x in unique if x['measures'])}")
    print(f"с несъедобной частью: {sum(1 for x in unique if x['waste_pct'])}")
    print(f"пересчитано на 100 г: "
          f"{sum(1 for x in unique if x['basis'] != 'per_100g')}")
    print(f"записано в {OUT}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()

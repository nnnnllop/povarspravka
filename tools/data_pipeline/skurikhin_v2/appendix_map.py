"""Приложения 1–3 Скурихина: разбор и умное сопоставление с продуктами.

  appendix1  — «Отходы и потери при холодной обработке» (% несъедобной части)
  appendix2  — «Меры и масса продуктов в граммах» (стакан, ст. л., ч. л., шт.)
  appendix3  — «Сведения о массе 1 штуки пищевых продуктов»

Приложение 3 берётся из текстового слоя PDF с координатами слов: колонка
«Продукт» — левее x=270, масса — в диапазоне 470…520, вторая колонка — правее.
Названия и массы связываются по строкам (ближайшая подпись слева по вертикали).

Затем строится отображение «продукт книги -> запись приложения»:
  1) точное совпадение по нормализованной строке;
  2) вхождение нормализованного названия (словоформы в родительном падеже
     учитываются грубым стеммингом);
  3) LLM-проверка остатка пакетами (кэш в JSONL).
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

import pymupdf

ROOT = Path(__file__).resolve().parents[3]
INSPECT = Path(
    os.environ.get("SKURIKHIN_INSPECT_DIR")
    or (ROOT / "data" / "skurikhin_v2" / "_inspect")
)
PDF = Path(
    os.environ.get("SKURIKHIN_PDF_PATH")
    or (ROOT / "data" / "skurikhin_v2" / "skurikhin.pdf")
)


# ------------------------------------------------------------------ разбор
def parse_appendix3() -> dict[str, dict]:
    """{название: {"grams": [...], "note": "диаметр 5,5 см"}}."""
    if not PDF.exists():
        raise FileNotFoundError(
            f"PDF справочника Скурихина не найден ({PDF}). "
            "Задайте путь через переменную окружения SKURIKHIN_PDF_PATH."
        )
    # подписи о размере, которые в PDF-слое съезжают в соседние строки
    NOTE_FIX = {
        "Томаты": None,          # «75» — это масса, а не размер
        "Пряники": None,
        "Яблоки": "диаметр 5,0/6,5/7,5 см",
        "Апельсин": "диаметр 6,5/7,5 см",
        "Абрикосы": None, "Бананы": None, "Гранат": None,
        "Груша": None, "Инжир": None, "Персики": None,
        "Слива": None, "Хурма японская": None,
    }
    doc = pymupdf.open(PDF)
    page = doc[210]
    words = page.get_text("words")
    left, right = [], []
    for x0, y0, x1, y1, txt, *_ in words:
        if y0 < 150 or y0 > 700:
            continue
        cy = (y0 + y1) / 2
        if x0 < 270:
            left.append((cy, x0, txt))
        elif 270 <= x0 < 460:
            right.append((cy, x0, txt))
    out: dict[str, dict] = {}

    def scan(col, mass_lo, mass_hi, label_hi):
        col = sorted(col)
        entries = []          # (y, [words])
        for cy, x0, txt in col:
            if entries and abs(entries[-1][0] - cy) <= 3:
                entries[-1][1].append((x0, txt))
            else:
                entries.append([cy, [(x0, txt)]])
        label = None
        last_y = None
        for cy, ws in entries:
            ws.sort()
            text = " ".join(t for _, t in ws).strip()
            masses = [t for x, t in ws if mass_lo <= x <= mass_hi
                      and re.fullmatch(r"\d+(?:[.,]\d+)?", t)]
            is_label = not any(mass_lo <= x <= mass_hi for x, _ in ws) and \
                bool(re.search(r"[А-Яа-яЁё]{3}", text))
            if is_label and not re.match(r"^(диаметр|\d)", text):
                label = re.sub(r"^[|\[\]I Ц]+", "", text).strip()
                last_y = cy
                continue
            if label and masses:
                grams = [float(m.replace(",", ".")) for m in masses]
                rec = out.setdefault(label, {"grams": [], "note": None})
                for g in grams:
                    if g not in rec["grams"]:
                        rec["grams"].append(g)
                # запись вида «диаметр 6,5 см | 100» дополняет ту же подпись
            elif label and re.match(r"^(диаметр|\d+,\d+ см)", text):
                out.setdefault(label, {"grams": [], "note": None})["note"] = text
                last_y = cy
            elif re.fullmatch(r"\d+(?:[.,]\d+)?", text) and label and last_y is not None:
                rec = out.setdefault(label, {"grams": [], "note": None})
                g = float(text.replace(",", "."))
                if g not in rec["grams"]:
                    rec["grams"].append(g)

    scan(left, 470, 520, 270)
    scan(right, 470, 520, 470)
    # ручные поправки по координатной сетке (OCR/PDF-слой путают подписи)
    FIX = {
        "Печенье сдобное": [35],
        "Сдоба выборгская": [50],
        "Сдоба обыкновенная": [50],
        "Рожки сдобные": [60],
        "Хлебобулочные изделия с молоком": [50],
        "Сырки глазированные": [50],
        "Сыры плавленые": [30, 100],
        "Мороженое": [100, 250],
        "Яйца куриные 1 категории": [47],
        "Яйца перепелиные": [9],
        "Галеты": [15.5], "Крекеры": [13], "Вафли": [14], "Пряники": [20],
        "Пирожные": [75],
        "Булки городские": [200], "Булка черкизовская": [200],
        "Булочка молочная": [200], "Булка ярославская": [200],
        "Лепешки оби-нон": [200],
        "Баранки простые": [25], "Баранки молочные": [30],
        "Сушки простые": [10], "Сухари сливочные": [20],
        "Сахар-рафинад прессованный": [7.5],
        "Сахар-рафинад быстрорастворимый": [6],
        "Карамель с начинками": [6],
        "Конфеты": [12.5, 15],
        "Ассорти с пралиновыми начинками": [11.5],
        "Батончики": [15], "Ирис": [7], "Мармелад": [12.5],
        "Пастила": [15], "Зефир": [33],
        "Печенье сахарное": [13.5], "Печенье затяжное": [10],
        "Картофель": [100], "Лук репчатый": [75], "Морковь красная": [75],
        "Огурцы грунтовые": [100], "Петрушка (корень)": [50],
        "Томаты": [75],
        "Абрикосы": [26], "Бананы": [72], "Гранат": [125], "Груша": [135],
        "Инжир": [40], "Персики": [85], "Слива": [30], "Хурма японская": [85],
        "Яблоки": [90, 130, 200, 115], "Апельсин": [100, 150, 200],
        "Грейпфрут": [130], "Лимон": [60], "Земляника садовая": [8],
        "Сардельки": [100], "Сосиски": [50],
    }
    for k, v in FIX.items():
        rec = out.setdefault(k, {"grams": [], "note": None})
        rec["grams"] = v
    for k, v in NOTE_FIX.items():
        rec = out.setdefault(k, {"grams": [], "note": None})
        rec["note"] = v
    return out


def normalize(s: str) -> str:
    s = s.lower().replace("ё", "е")
    s = re.sub(r"[«»\"'(),.;:*]", " ", s)
    s = re.sub(r"\bпо\s+\d+-\d+\b", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def stem(word: str) -> str:
    """Грубый стемминг: «яблоки»/«яблок» -> «яблок»."""
    if len(word) <= 4:
        return word
    for suf in ("ами", "ями", "ов", "ев", "ые", "ий", "ый", "ая", "яя", "ое",
                "ее", "ой", "ей", "ую", "юю", "ам", "ям", "ах", "ях", "и", "ы",
                "а", "я", "о", "е", "у", "ю", "ь"):
        if word.endswith(suf) and len(word) - len(suf) >= 4:
            return word[:-len(suf)]
    return word


def stems(s: str) -> set[str]:
    return {stem(w) for w in normalize(s).split() if len(w) > 1}


def match_scores(app_id: str, product_name: str) -> float:
    a, b = normalize(app_id), normalize(product_name)
    if not a or not b:
        return 0.0
    if a == b:
        return 100.0
    if a in b or b in a:
        return 80.0 - abs(len(a) - len(b)) * 0.1
    sa, sb = stems(app_id), stems(product_name)
    if not sa:
        return 0.0
    common = sa & sb
    if not common:
        return 0.0
    return 60.0 * len(common) / len(sa | sb)


SECTION_HINT = {
    "овощ": ("овощ", "капуст", "картоф", "морков", "свекл", "лук", "луков",
             "петрушк", "сельдер", "пастернак", "брюкв", "редьк", "редіс",
             "редис", "реп", "тыкв", "кабач", "баклаж", "перец", "томат",
             "помидор", "огурц", "шпинат", "салат", "щавел", "арбуз", "дын",
             "горош", "фасол", "боб", "чеснок", "хрен", "кукуруз", "батат"),
    "фрукт": ("яблок", "груш", "слив", "вишн", "абрикос", "персик", "виноград",
              "смородин", "крыжовник", "малин", "земляник", "клубник", "лимон",
              "апельсин", "мандарин", "банан", "гранат", "айв", "алыч", "хурм",
              "инжир", "облепих", "брусник", "клюкв", "черник", "голубик"),
    "ягод": ("земляник", "клубник", "малин", "смородин", "крыжовник",
             "брусник", "клюкв", "черник", "голубик", "облепих", "вишн",
             "виноград", "ежевик", "рябин", "калин", "черемух"),
    "цитрус": ("лимон", "апельсин", "мандарин", "грейпфрут", "помел"),
    "бахчев": ("арбуз", "дын", "тыкв"),
    "гриб": ("гриб", "белые", "подберезовик", "подосиновик", "лисичк",
             "маслят", "опят", "шампиньон", "вешенк", "грузд", "рыжик"),
    "рыб": ("рыб", "треск", "минтай", "окун", "камбал", "судак", "карп",
            "сазан", "сельд", "кильк", "салак", "мойв", "наваг", "зубатк",
            "палтус", "лосос", "кет", "горбуш", "семг", "форел", "осетр",
            "севрюг", "белуг", "сом", "щук", "лещ", "язь", "налим", "икра"),
    "мяс": ("мяс", "говяд", "свин", "баран", "телят", "курин", "кур",
            "индейк", "утк", "гус", "крол", "печен", "сердц", "язык"),
    "говяд": ("говяд", "телят", "мяс"),
    "баран": ("баран", "мяс"),
    "свин": ("свин", "мяс"),
    "птиц": ("курин", "кур", "индейк", "утк", "гус", "цыплят", "бройлер"),
    "яйц": ("яйц", "яичн", "белок", "желт", "меланж"),
    "молоч": ("молок", "кефир", "творог", "сыр", "сметан", "сливк",
              "ряженк", "простокваш", "йогурт", "ацидофилин", "кумыс", "пахта"),
    "сметан": ("сметан", "сливк"),
    "хлеб": ("хлеб", "батон", "булк", "булочк", "баранк", "сушк", "сухар",
             "макарон", "вермишел", "лапш", "рожк"),
    "круп": ("круп", "рис", "греч", "пшен", "перлов", "овсян", "манн",
             "толокн", "геркулес", "ячнев", "кукурузн", "горох", "фасол",
             "чечевиц", "соя", "пшениц", "рожь", "овес", "ячмен", "просо",
             "мука", "отруб", "крахмал", "макарон"),
    "ринe": ("рис", "греч", "пшен", "перлов", "овсян", "манн", "толокн",
             "ячнев", "кукурузн", "горох", "фасол", "чечевиц", "соя",
             "пшениц", "рожь", "овес", "ячмен", "просо", "мука", "отруб",
             "крахмал", "макарон", "круп"),
    "кондитер": ("сахар", "карамел", "конфет", "шоколад", "печенье",
                 "пряник", "вафл", "зефир", "пастил", "мармелад", "ирис",
                 "халв", "торт", "пирожн", "мед", "варень", "повидл",
                 "джем", "какао", "пектин", "агар"),
    "масл": ("масло", "маргарин", "жир", "сало", "шпик"),
    "напит": ("сок", "напиток", "компот", "морс", "квас", "чай", "кофе",
              "минеральн", "вод"),
    "колбас": ("колбас", "сосиск", "сардельк", "балык", "окорок", "ветчин",
               "шинк", "корейк", "буженин", "карбонад", "грудинк", "бекон"),
    "сосис": ("сосиск", "сардельк", "колбас"),
}


def hint_section(app_section: str) -> tuple[str, ...]:
    """Слова, которые должны встречаться в названии продукта этого раздела."""
    s = (app_section or "").lower()
    words: list[str] = []
    for key, vals in SECTION_HINT.items():
        if key in s:
            words.extend(vals)
    return tuple(dict.fromkeys(words))


def build_mapping(products: list[dict], pieces: dict, waste: dict,
                  measures: dict) -> dict:
    """Сопоставить продукты книги с записями приложений 1–3.

    products: [{"code", "name"}] (уже с каноническими названиями).
    Возвращает {code: {"measures": [...], "waste_pct": ..., "piece_g": [...]}}.
    """
    out: dict[str, dict] = {}
    waste_items = [(k, v) for k, v in waste.items()
                   if len(normalize(k).split()) >= 2 or len(normalize(k)) >= 5]
    meas_items = [(k, v) for k, v in measures.items()]
    pie_items = [(k, v) for k, v in pieces.items()]

    for p in products:
        code, name = p["code"], p["name"]
        best = {}
        for label, items, kind in (("waste", waste_items, "waste"),
                                   ("measures", meas_items, "meas"),
                                   ("pieces", pie_items, "pie")):
            scored = []
            for key, val in items:
                s = match_scores(key, name)
                if not s:
                    continue
                if kind == "waste":
                    hint = hint_section(val.get("section", ""))
                    if hint and not any(h in normalize(name) for h in hint):
                        s *= 0.4      # продукт не из раздела приложения
                if s > 0:
                    scored.append((s, key, val))
            scored.sort(key=lambda t: -t[0])
            best[code, kind] = scored[0] if scored and scored[0][0] >= 55 else None
        # меры: только точные/вложенные совпадения (стакан ≠ «овсяная каша»)
        rec = {"measures": [], "waste_pct": None, "piece_g": [],
               "matched": {}}
        m = best[code, "meas"]
        if m and m[0] >= 80:
            rec["measures"] = [dict(x) for x in m[2]["measures"]]
            rec["matched"]["measures"] = m[1]
        w = best[code, "waste"]
        if w and w[2]["waste_pct"] <= 70:      # > 70 % — явно не та строка
            rec["waste_pct"] = w[2]["waste_pct"]
            rec["matched"]["waste"] = w[1]
        pi = best[code, "pie"]
        if pi:
            rec["piece_g"] = list(pi[2]["grams"])
            rec["matched"]["pieces"] = pi[1]
        out[code] = rec
    return out


def main() -> None:
    INSPECT.mkdir(parents=True, exist_ok=True)
    pieces = parse_appendix3()
    (INSPECT / "appendix3_pieces.json").write_text(
        json.dumps(pieces, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"приложение 3: {len(pieces)} записей с массой "
          f"{sum(1 for v in pieces.values() if v['grams'])}")
    for k, v in pieces.items():
        if not v["grams"]:
            print("  без массы:", k)

    names = json.loads((INSPECT / "names_llm.json").read_text(encoding="utf-8"))
    waste = json.loads((INSPECT / "appendix1_waste.json").read_text(encoding="utf-8"))
    measures = json.loads((INSPECT / "appendix2_measures.json").read_text(encoding="utf-8"))
    mapping = build_mapping(names, pieces, waste, measures)
    (INSPECT / "appendix_mapping.json").write_text(
        json.dumps(mapping, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"сопоставлено: меры {sum(1 for v in mapping.values() if v['measures'])}, "
          f"несъедобная часть {sum(1 for v in mapping.values() if v['waste_pct'])}, "
          f"масса 1 шт {sum(1 for v in mapping.values() if v['piece_g'])}")
    for code in ("1.1.1.1", "8.1.1.1", "9.1.1.1", "9.1.4.1", "2.1.1", "6.1.1.1"):
        if code in mapping:
            print(code, mapping[code]["matched"], mapping[code]["waste_pct"],
                  mapping[code]["piece_g"], len(mapping[code]["measures"]))

if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    main()

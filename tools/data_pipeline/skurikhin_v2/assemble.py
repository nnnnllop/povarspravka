"""Слой 2: сборка товарных записей из левых и правых страниц.

Левая страница даёт название, порцию, БЖУ и энергетическую ценность не даёт;
правая — минералы, витамины и ЭЦ. Связка идёт по коду продукта, а для строк без
кода — по порядку следования с проверкой калорийности.

Проверка калорийности: 4·Бел + 9·Жир + 3.75·Угл + 3·ОК + 2·ПВ + 7·Алк ≈ ЭЦ.
По этой формуле подтверждаем, что справа стоит именно тот продукт, и ловим
сдвиги столбцов.
"""
from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import parse_ocr as P  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "data" / "skurikhin_v2"
INSPECT = Path(
    os.environ.get("SKURIKHIN_INSPECT_DIR") or (OUT / "_inspect")
)

LEFT_PAGES = list(range(25, 195, 2))
RIGHT_PAGES = list(range(26, 195, 2))

# коэффициенты энергетической ценности, ккал/г
KCAL = {"protein": 4.0, "fat": 9.0, "carbs": 3.75, "organic_acids": 3.0,
        "fiber": 2.0, "alcohol": 7.0}

# канонический порядок правых столбцов (для ручных исправлений)
CANON_KEYS = ["sodium", "potassium", "calcium", "magnesium", "phosphorus",
              "iron", "vitamin_a", "beta_carotene", "vitamin_a_re",
              "vitamin_e", "vitamin_b1", "vitamin_b2", "niacin",
              "niacin_equivalent", "vitamin_c", "energy_kcal"]


@dataclass
class Product:
    code: str
    page_left: int
    page_right: int | None
    name: str
    portion: str
    values: dict[str, float | int | None] = field(default_factory=dict)
    portion_values: dict[str, float | int | None] = field(default_factory=dict)
    percent_daily: dict[str, float | int | None] = field(default_factory=dict)
    alcohol_vol: float | None = None
    table: int = 0
    section_path: list[str] = field(default_factory=list)
    energy_calc: float | None = None
    energy_book: float | None = None
    energy_delta: float | None = None
    flags: list[str] = field(default_factory=list)


def energy_from(values: dict[str, float | int | None]) -> float | None:
    total = 0.0
    seen = False
    for key, k in KCAL.items():
        v = values.get(key)
        if v is None:
            continue
        seen = True
        total += float(v) * k
    return round(total, 1) if seen else None


def collect_left() -> tuple[list[Product], list[dict]]:
    """Товары слева с путём разделов и прикреплёнными порциями."""
    products: list[Product] = []
    sections: list[dict] = []
    table_no = 0
    path: list[str] = []
    for page in LEFT_PAGES:
        items, _ = P.read_left_page(page)
        for it in items:
            if isinstance(it, P.SectionHeading):
                title = it.title.strip()
                m_banner = re.match(r"^Таблица\s+(\d+)\.?\s*(.*)$", title, re.I)
                if m_banner:
                    # «Таблица N. НАЗВАНИЕ» — баннер новой таблицы: глубина 0 и
                    # полный сброс пути, иначе в таблицах 3–12 остаётся
                    # «ЖИРНОСТЬ < 1,0%» из таблицы 1.
                    table_no = int(m_banner.group(1))
                    path = [title]
                    sections.append({"code": str(table_no), "title": title,
                                     "page": page, "table": table_no})
                    continue
                if it.code is None:
                    # Верхняя колонтитульная строка разворота: «Таблица N.
                    # НАЗВАНИЕ» может не распознаться и остаться пустой
                    # подписью — всё равно начинаем путь заново.
                    if not title or re.search(r"таблиц", title, re.I):
                        m = re.search(r"Таблица\s+(\d+)", title, re.I)
                        table_no = int(m.group(1)) if m else table_no
                        path = [f"Таблица {table_no}. {title}"] if title else [f"Таблица {table_no}"]
                        continue
                    continue
                depth = it.code.count(".") + 1
                # номер таблицы книги = первая цифра кода («11.2.1.1» → 11)
                head = it.code.split(".")[0]
                if head.isdigit():
                    table_no = int(head)
                if depth == 1:
                    path = [f"Таблица {table_no}. {title}"]
                elif depth == 2:
                    label = path[0] if path and path[0].startswith("Таблица ") \
                        else f"Таблица {table_no}"
                    path = [label, title]
                elif path and path[0].startswith("Таблица "):
                    path = path[:depth - 1] + [title]
                else:
                    # В таблицах 3–12 подпись «Таблица N. НАЗВАНИЕ» на скане
                    # не распознана: имя таблицы берём из верхнего раздела,
                    # номер — из кода; полный путь не теряем.
                    root = path[0] if path else title
                    path = [f"Таблица {table_no}. {root}", title]
                sections.append({"code": it.code, "title": title,
                                 "page": page, "table": table_no})
                continue
            if isinstance(it, P.LeftRow):
                # номер таблицы = первая цифра кода («11.2.1.1» → 11):
                # так путь остаётся верным, даже если заголовок раздела
                # не распознан или разрыв страницы пришёлся на товар
                head = it.code.split(".")[0]
                if head.isdigit():
                    table_no = int(head)
                if not (path and path[0].startswith("Таблица ")):
                    root = path[0] if path else "ПРОДУКТЫ"
                    path = [f"Таблица {table_no}. {root}"] + path[1:]
                elif not path[0].startswith(f"Таблица {table_no}"):
                    # новая таблица, а подпись на скане не распознана —
                    # берём верхний раздел старого пути как имя таблицы
                    root = path[1] if len(path) > 1 else "ПРОДУКТЫ"
                    path = [f"Таблица {table_no}. {root}"] + path[2:]
                sections.append({"code": it.code, "title": f"Таблица {table_no}",
                                 "page": page, "table": table_no,
                                 "kind": "product"})
                products.append(Product(
                    code=it.code, page_left=page, page_right=None,
                    name=it.name, portion=it.portion, values=dict(it.values),
                    table=table_no, section_path=list(path)))
                continue
            if isinstance(it, P.PortionRow) and products:
                products[-1].portion_values = dict(it.values)
                if not products[-1].portion:
                    products[-1].portion = str(it.grams)
                continue
            if isinstance(it, P.PercentRow) and products:
                products[-1].percent_daily = dict(it.values)
                continue
    # фантомные дубликаты (один код дважды из-за повторного чтения строки)
    seen: dict[str, Product] = {}
    uniq: list[Product] = []
    for p in products:
        if p.code in seen:
            prev = seen[p.code]
            if sum(1 for v in p.values.values() if v is not None) > \
                    sum(1 for v in prev.values.values() if v is not None):
                uniq[uniq.index(prev)] = p
                seen[p.code] = p
            continue
        seen[p.code] = p
        uniq.append(p)
    return uniq, sections


def _block_rows(rows: list[dict]) -> list[list[dict]]:
    """Разбить строки правой страницы на блоки «один товар = 1–3 строки».

    На правой странице каждый товар занимает три строки: 100 г, порция и
    «% с.п.». Код печатается у первой строки, но OCR иногда переносит его во
    вторую или третью. Поэтому блок начинается там, где стоит код, а также
    там, где предыдущая строка уже завершила тройку.
    """
    blocks: list[list[dict]] = []
    cur: list[dict] = []
    for row in rows:
        if row["code"] and cur:
            blocks.append(cur)
            cur = []
        cur.append(row)
        if len(cur) >= 3:
            blocks.append(cur)
            cur = []
    if cur:
        blocks.append(cur)
    return blocks


def _looks_like_portion(row_vals: dict, base: dict) -> bool:
    """Строка похожа на порцию: значения ≈ k·(100 г), k ≈ 2…3."""
    ratios = []
    for key in ("protein", "fat", "carbs"):
        a, b = row_vals.get(key), base.get(key)
        if a is None or b is None or float(b) <= 0:
            continue
        ratios.append(float(a) / float(b))
    if not ratios:
        return False
    mid = sorted(ratios)[len(ratios) // 2]
    return 1.8 <= mid <= 3.3 and all(1.5 <= r <= 3.6 for r in ratios)


def pick_hundred_gram(block: list[dict],
                      left: dict[str, float | int | None] | None
                      ) -> dict | None:
    """Выбрать из блока строку «на 100 г»."""
    coded = [r for r in block if r["code"]]
    nocode = [r for r in block if not r["code"]]
    if not block:
        return None
    # 1. Строка, чья ЭЦ ближе всего к расчёту по БЖУ слева, — это 100 г.
    best, best_err = None, None
    for row in block:
        calc = energy_from({**(left or {}), **row["values"]})
        e = row["values"].get("energy_kcal")
        if calc is None or e is None:
            continue
        err = abs(float(e) - calc)
        if best_err is None or err < best_err:
            best, best_err = row, err
    if best is not None and best_err is not None and best_err < 40:
        return best
    # 2. Иначе первая строка блока, а не строка с кодом.
    if coded and coded[0] is not block[0]:
        first = block[0]
        if not _looks_like_portion(first["values"], (left or {})):
            return first
    if coded:
        return coded[0]
    return block[0] if block else None


def collect_right() -> dict[int, list[dict]]:
    """Страница -> строки данных справа в порядке следования.

    Строки-копии (OCR иногда вставляет кусок таблицы дважды) удаляются по
    совпадению кодов: остаётся та копия, где больше заполненных значений
    (в первом вхождении обычно потерян столбец «Алк»).
    """
    out: dict[int, list[dict]] = {}
    for page in RIGHT_PAGES:
        items, _ = P.read_right_page(page)
        by_code: dict[str, dict] = {}
        order: list[str] = []
        anon: list[dict] = []
        for it in items:
            if not isinstance(it, P.RightRow):
                continue
            code = next((c for c in reversed(it.raw_cells)
                         if P.CODE_RE.match(c)), None)
            rec = {"values": it.values, "alcohol_vol": it.alcohol_vol,
                   "raw": it.raw_cells, "code": code}
            if code is None:
                anon.append(rec)
                continue
            filled = sum(1 for v in it.values.values() if v is not None)
            if code in by_code:
                old = by_code[code]
                old_filled = sum(1 for v in old["values"].values() if v is not None)
                # Дубликат-«огрызок» без метки спирта («8,8» вместо
                # «8,8(11,0)**») даёт на одну заполненную ячейку БОЛЬШЕ
                # (спирт попадает в «ЭЦ», а сама «ЭЦ» уезжает за границу
                # разбора), поэтому одного счётчика мало: строку с меткой
                # спирта предпочитаем ВСЕГДА — только она размечена по
                # заголовку с колонкой «Алк». Иначе у 11.2.2.1 спирт
                # записывается как 64 г (это ЭЦ), ЭЦ = 454,9 вместо 64.
                has_alc = rec["alcohol_vol"] is not None
                old_alc = old["alcohol_vol"] is not None
                if has_alc != old_alc:
                    better = has_alc
                else:
                    better = filled > old_filled
                if better:
                    by_code[code] = rec
                continue
            by_code[code] = rec
            order.append(code)
        out[page] = [by_code[c] for c in order] + anon
    return out


def attach_right(products: list[Product],
                 right: dict[int, list[dict]]) -> list[str]:
    """Разложить правые строки по продуктам.

    Основной путь — по коду в последней ячейке. Строки без кода относятся к
    предыдущему блоку (порция / %с.п. того же продукта) и отбрасываются, так
    как БЖУ уже есть слева.
    """
    problems: list[str] = []
    by_code = {p.code: p for p in products}
    # Ручные исправления — ДО автопривязки, чтобы они не «приклеили» продукт
    # к правой странице раньше времени и не заблокировали нормальную связку.
    import manual_repairs
    for code, fix in manual_repairs.REPAIRS.items():
        prod = by_code.get(code)
        if prod is None:
            problems.append(f"repair: нет товара {code}")
            continue
        keys = CANON_KEYS
        vals = {keys[i]: P.parse_number(v) for i, v in enumerate(fix["row"])
                if i < len(keys)}
        vals["alcohol"] = None
        vals["energy_kcal"] = P.parse_number(fix["row"][15]) if len(
            fix["row"]) > 15 else None
        prod.values.update(vals)
    # ---- восстановленный столбец ЭЦ (полосовое распознавание) ----------
    strips_path = INSPECT / "energy_strips.json"
    strips: dict = {}
    if strips_path.exists():
        strips = json.loads(strips_path.read_text(encoding="utf-8"))
        filled = 0
        for key, energy in strips.items():
            for code, val in energy.items():
                prod = by_code.get(code)
                if prod is None or code.count(".") < 2:
                    continue
                cur = prod.values.get("energy_kcal")
                if cur is None:
                    prod.values["energy_kcal"] = val
                    filled += 1
                elif code.startswith(str(cur)):
                    prod.values["energy_kcal"] = val
                    filled += 1
        print(f"ЭЦ восстановлено из полос: {filled}")
    for page in RIGHT_PAGES:
        rows = right.get(page, [])
        for block in _block_rows(rows):
            codes = [r["code"] for r in block if r["code"]]
            code = codes[0] if codes else None
            if not code:
                continue
            prod = by_code.get(code)
            if prod is None:
                problems.append(f"p{page}: код {code} справа без товара слева")
                continue
            if prod.page_right is not None:
                problems.append(f"p{page}: код {code} справа повторно")
                continue
            row = pick_hundred_gram(block, prod.values)
            if row is None:
                continue
            if row is not block[0]:
                problems.append(f"p{page}: код {code} стоял не в первой строке "
                                f"блока — взята строка 100 г")
            prod.values.update({k: v for k, v in row["values"].items()
                                if v is not None or k not in prod.values})
            for k, v in row["values"].items():
                if k not in prod.values:
                    prod.values[k] = v
            prod.alcohol_vol = row["alcohol_vol"]
            prod.page_right = page
    for p in products:
        if p.page_right is None:
            problems.append(f"нет правой части: {p.code} {p.name} "
                            f"(p{p.page_left})")
    return problems


def main() -> None:
    products, sections = collect_left()
    right = collect_right()
    problems = attach_right(products, right)

    for p in products:
        P.repair_energy(p.values, p.values)
        # Коды, столкнувшиеся с числом ЭЦ (OCR склеил код «5.4.4» с ячейкой
        # «7» в одно «74»): если ЭЦ подозрительно мала для БЖУ, а правый
        # столбец ЕЦ пуст или тоже мал — столбец потерян целиком.
        calc = energy_from(p.values)
        e = p.values.get("energy_kcal")
        if calc is not None and e is not None and calc > 40 and \
                float(e) < calc * 0.25:
            # ЭЦ вида «74» при коде «5.4.4» — склейка кода со значением ЭЦ;
            # в этом случае ЭЦ теряется (см. правку в assemble.py).
            if str(e) in (p.code + "" ).replace(".", "") or \
                    p.code.replace(".", "") == str(e):
                p.values.pop("energy_kcal", None)
                p.flags.append("energy_lost_code_glued")
                p.values.setdefault("energy_kcal", calc)
    # ЭЦ, противоречащая энергетическому балансу, заменяется значением из
    # полосового распознавания (если оно там есть и ближе к расчёту)
    strips_path = INSPECT / "energy_strips.json"
    strips = (json.loads(strips_path.read_text(encoding="utf-8"))
              if strips_path.exists() else {})
    for p in products:
        calc = energy_from(p.values)
        e = p.values.get("energy_kcal")
        if calc is None or calc <= 20 or e is None:
            continue
        if abs(float(e) - calc) > max(25.0, calc * 0.45):
            p.flags.append(f"energy_book_mismatch:{float(e):g}!={calc:g}")
            # ЭЦ, противоречащая энергетическому балансу, заменяется
            # значением из полосового распознавания (если оно ближе к
            # расчёту) — но только при уверенном расхождении
            cand = strips.get(f"p{p.page_right:03d}", {}).get(p.code) \
                if p.page_right else None
            if cand is not None:
                # полосовое распознавание надёжно только при близкой
                # согласованности самого кандидата с расчётом
                if abs(float(cand) - calc) < abs(float(e) - calc):
                    p.values["energy_kcal"] = cand
                elif abs(float(cand) - calc) > max(20.0, calc * 0.35) and \
                        abs(float(cand) - calc) >= abs(float(e) - calc):
                    # ни книга, ни полосы не сходятся с расчётом — ЭЦ
                    # всё равно снимаем: она врёт.
                    p.values["energy_kcal"] = calc
                    p.flags.append("energy_recomputed_both_bad")
    # Восстановить потерянную ЭЦ, если в строке съехал столбец:
    #   * БЖУ есть, а ЭЦ нет (код стоял на месте ЭЦ — «5.4.7»);
    #   * ЭЦ подозрительно мала относительно расчёта — в ячейке остался
    #     «огрызок» склеенного значения («85.5» вместо «43», «0.2»).
    for p in products:
        calc = energy_from(p.values)
        e = p.values.get("energy_kcal")
        if calc is None or calc <= 20:
            continue
        if e is None:
            p.values["energy_kcal"] = calc
            p.flags.append("energy_recomputed_missing")
        elif float(e) < calc * 0.4:
            p.values["energy_kcal"] = calc
            p.flags.append("energy_recomputed_shift")
    for p in products:
        calc = energy_from(p.values)
        p.energy_calc = calc
        book = p.values.get("energy_kcal")
        p.energy_book = book
        if calc is not None and book not in (None, 0):
            p.energy_delta = round(calc - float(book), 1)

    OUT.mkdir(parents=True, exist_ok=True)
    payload = []
    for p in products:
        payload.append({
            "code": p.code, "table": p.table, "section_path": p.section_path,
            "name_raw": p.name, "portion": p.portion,
            "page_left": p.page_left, "page_right": p.page_right,
            "flags": list(p.flags),
            "values": p.values, "portion_values": p.portion_values,
            "percent_daily": p.percent_daily, "alcohol_vol": p.alcohol_vol,
            "energy_calc": p.energy_calc, "energy_book": p.energy_book,
            "energy_delta": p.energy_delta,
        })
    (INSPECT / "assembled_raw.json").write_text(
        json.dumps({"products": payload, "sections": sections,
                    "problems": problems}, ensure_ascii=False, indent=1),
        encoding="utf-8")

    print(f"товаров: {len(products)}")
    print(f"разделов: {len(sections)}")
    print(f"с правой частью: {sum(1 for p in products if p.page_right)}")
    print(f"проблем связывания: {len(problems)}")
    big = [p for p in products if p.energy_delta is not None
           and abs(p.energy_delta) > 8]
    print(f"расхождение ЭЦ > 8 ккал: {len(big)}")
    for p in big[:25]:
        print(f"  {p.code:12s} {p.name[:38]:38s} расч={p.energy_calc} "
              f"книга={p.energy_book} Δ={p.energy_delta}")
    for msg in problems[:25]:
        print("  !", msg)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()

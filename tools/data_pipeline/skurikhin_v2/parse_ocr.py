"""Слой 1: разбор постраничного OCR (ocr_md/pNNN.md) в плоские структуры.

Никаких решений о названиях и синонимах здесь нет — только аккуратный разбор
HTML-таблиц с учётом реальных особенностей источника:

  * левые страницы Таблиц 1-12: Код | Продукты | Порция | Вода | Бел | Жир |
    НЖК | [ПНЖК] | Хол | МДС | [Кр] | Угл | [ПВ] | [ОК] | Зола
    (набор столбцов меняется от таблицы к таблице — определяем по шапке);
  * правые страницы: Na K Ca Mg P Fe A Кар РЭ ТЭ B1 B2 PP НЭ C [Алк] ЭЦ Код;
    код стоит в последней ячейке и может быть задан через rowspan, а у части
    строк отсутствовать вовсе — такие строки относятся к предыдущему блоку;
  * числа вида «53,6 (49,5-57,8)» — берём число до скобок;
    «14,6 (18,0)**» в таблице алкоголя — это спирт в % масс. и % об.;
  * «0» (и «-») означают «в пределах чувствительности метода», пустая ячейка —
    «нет данных»; поэтому 0 и null различаются.
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from pathlib import Path

from lxml import html as lxml_html

ROOT = Path(__file__).resolve().parents[3]      # .../povarspravka
OCR_DIR = Path(
    os.environ.get("SKURIKHIN_OCR_DIR")
    or (ROOT / "data" / "skurikhin_v2" / "ocr_md")
)

TABLE_TITLES = {
    1: "Молоко и молочные продукты",
    2: "Яйцепродукты",
    3: "Мясо и мясные продукты",
    4: "Рыба и рыбные продукты",
    5: "Жировые продукты",
    6: "Зерно и продукты его переработки",
    7: "Бобовые, орехи",
    8: "Овощи, грибы и продукты их переработки",
    9: "Фрукты, ягоды и продукты их переработки",
    10: "Кондитерские изделия",
    11: "Напитки",
    12: "Вспомогательные пищевые продукты и усилители вкуса",
}

# --------------------------------------------------------------- нормализация
LAT2CYR = str.maketrans({
    "A": "А", "B": "В", "C": "С", "E": "Е", "H": "Н", "K": "К", "M": "М",
    "O": "О", "P": "Р", "T": "Т", "X": "Х", "Y": "У", "c": "с", "e": "е",
    "o": "о", "p": "р", "x": "х", "y": "у", "a": "а", "k": "к", "K": "К",
})


def _fold(text: str | None) -> str:
    """Верхний регистр с заменой латиницы на кириллицу (для поиска в заголовках).

    OCR регулярно пишет «НАПИТКИ АЛКОГОЛЬНЫЕ» латиницей: «AЛКOГОЛЬНЫЕ».
    """
    if not text:
        return ""
    up = text.upper()
    return up.translate(str.maketrans({
        "A": "А", "B": "В", "C": "С", "E": "Е", "H": "Н", "K": "К", "M": "М",
        "O": "О", "P": "Р", "T": "Т", "X": "Х", "Y": "У", "I": "I",
    }))


CODE_RE = re.compile(r"^\d{1,2}(?:\.\d{1,3}){1,4}$")
NUM_RE = re.compile(r"^-?\d+(?:[.,]\d+)?$")
DASHES = {"-", "–", "—", "‒", "−"}


def clean_text(value: str | None) -> str:
    if value is None:
        return ""
    text = value.replace("\n", " ").replace("\u00a0", " ")
    text = re.sub(r"[ \t]{2,}", " ", text).strip()
    return text


def parse_number(raw: str | None) -> float | int | None:
    """Число из ячейки. «-» и пусто -> None, «0» -> 0."""
    if raw is None:
        return None
    text = clean_text(raw)
    if not text or text in DASHES:
        return None
    # основное число — до скобки со сноской/диапазоном
    head = re.split(r"[(\[]", text, maxsplit=1)[0].strip()
    head = head.replace("**", "").replace("*", "").strip()
    head = head.rstrip(".,")
    if not head or head in DASHES:
        return None
    head = head.replace(",", ".")
    if not NUM_RE.match(head):
        m = re.match(r"^-?\d+(?:\.\d+)?", head)
        if not m:
            return None
        head = m.group(0)
    value = float(head)
    return int(value) if value.is_integer() and "." not in head else value


def parse_alcohol(raw: str | None) -> tuple[float | int | None, float | None]:
    """«14,6 (18,0)**» -> (14.6 г/100 г, 18.0 % об.)."""
    grams = parse_number(raw)
    volume = None
    if raw:
        m = re.search(r"\(([\d.,]+)\)", raw)
        if m:
            volume = parse_number(m.group(1))
    return grams, volume


# ------------------------------------------------------------------- модель
@dataclass
class LeftRow:
    page: int
    code: str | None
    name: str
    portion: str
    values: dict[str, float | int | None]
    raw_cells: list[str] = field(default_factory=list)


@dataclass
class PortionRow:
    """Вторая строка продукта: нутриенты на указанную порцию."""
    page: int
    grams: float | int
    values: dict[str, float | int | None]
    raw_cells: list[str] = field(default_factory=list)
    alt: int | None = None      # вторая масса из записи «55 (75)»


@dataclass
class PercentRow:
    """Строка «%с.п. N» — % удовлетворения суточной потребности."""
    page: int
    grams: float | int
    values: dict[str, float | int | None]
    raw_cells: list[str] = field(default_factory=list)


@dataclass
class SectionHeading:
    page: int
    code: str | None
    title: str


@dataclass
class RightRow:
    page: int
    values: dict[str, float | int | None]
    alcohol_vol: float | None = None
    raw_cells: list[str] = field(default_factory=list)


@dataclass
class RightSection:
    page: int
    code: str | None
    title: str


# ------------------------------------------------------------- чтение таблиц
def read_table(path: Path):
    text = path.read_text(encoding="utf-8")
    if "<table" not in text:
        return None
    doc = lxml_html.fromstring(text)
    table = doc if doc.tag == "table" else doc.find(".//table")
    return table


def drop_duplicate_runs(table):
    """Убрать повторно скопированные блоки строк.

    В OCR части страниц (p108, p128, p142, p144, p150) один и тот же кусок
    таблицы вставлен дважды — второй раз ещё и с признаками разрушения
    rowspan/colspan. Копии сшиты встык, в том числе по границе тройки
    «100 г / порция / % с.п.». Поэтому оставляем первое вхождение минимума,
    остаток повторной копии обрезаем.
    """
    if table is None:
        return table
    body = table.find(".//tbody")
    if body is None:
        return table

    def key(tr) -> str:
        return "".join(row_cells(tr)) + "|" + "".join(map(str, colspans(tr)))

    rows = body.findall("./tr")
    keys = [key(tr) for tr in rows]

    def drop(lo: int, hi: int) -> None:
        for tr in rows[lo:hi]:
            body.remove(tr)

    # 1. минимальный повторяющийся блок подряд
    n = len(rows)
    for size in range(1, n // 2 + 1):
        found = None
        for start in range(n - 2 * size + 1):
            if keys[start:start + size] == keys[start + size:start + 2 * size]:
                found = start
                break
        if found is None:
            continue
        drop(found + size, found + 2 * size)
        # хвост второй копии: тот же порядок кода, что и в начале таблицы
        rows = [tr for tr in rows if tr.getparent() is not None]
        tail = [i for i, tr in enumerate(rows)
                if any(CODE_RE.match(c or "") for c in row_cells(tr))]
        if tail:
            first_code = next((row_cells(rows[i]) for i in tail
                               if any(CODE_RE.match(c or "")
                                      for c in row_cells(rows[i]))), None)
            if first_code is not None:
                head_key = key(rows[tail[0]])
                again = [i for i in tail[1:] if key(rows[i]) == head_key]
                if again:
                    drop(again[-1], len(rows))
        return drop_duplicate_runs(table)

    # 2. повтор, разрезанный шапкой столбцов
    def is_head(tr) -> bool:
        c = [x.lower() for x in row_cells(tr)]
        return sum(1 for x in c if x in HEADER_WORDS) >= 3

    for h in [i for i, tr in enumerate(rows) if is_head(tr) and i > 0]:
        part1 = [k for k, tr in zip(keys[:h], rows[:h]) if not is_head(tr)]
        j = h
        while j < n and is_head(rows[j]):
            j += 1
        tail = keys[j:]
        distinct = set(part1)
        if len(distinct) < 4 or not tail:
            continue
        if len(distinct & set(tail)) < max(4, len(distinct) * 0.9):
            continue
        last = max(i for i, kk in enumerate(tail, start=j) if kk in distinct)
        if last + 1 < n:
            drop(last + 1, n)
            return drop_duplicate_runs(table)

    # 3. повтор от начала копии, сшитый по любой границе: ищем в хвосте
    #    фрагмент, с которого копия начинается заново (первая строка таблицы).
    rows2 = [tr for tr in rows if tr.getparent() is not None]
    keys2 = [key(tr) for tr in rows2]
    if len(rows2) > 8 and len(set(keys2[:4])) == 4:
        third = (keys2[2], keys2[3])
        for i in range(4, len(rows2) - 1):
            if (keys2[i], keys2[i + 1]) == third:
                drop(i, len(rows2))
                return drop_duplicate_runs(table)

    # 5. повтор, разрезанный шапкой столбцов внутри тела таблицы (p128):
    #    первая копия, шапка «Na K … Код», вторая копия целиком.
    for h in [i for i, tr in enumerate(rows) if is_head(tr)]:
        if h == 0:
            continue
        start = None
        for i in range(h + 1, len(rows) - 1):
            if keys[i] == keys[2] and keys[i + 1] == keys[3]:
                start = i
                break
        if start is not None:
            drop(start, len(rows))
            return drop_duplicate_runs(table)

    # 6. повтор, начинающийся в середине тройки: копия стартует со второй
    #    или третьей строки блока, поэтому ищем повтор составных пар.
    for step in (2, 1):
        blocks = ["".join(keys[i:i + 3]) for i in range(0, n - 2, 3)]
        for size in range(2, len(blocks) // 2 + 1):
            hit = None
            for start in range(len(blocks) - 2 * size + 1):
                if blocks[start:start + size] == blocks[start + size:start + 2 * size]:
                    hit = start
                    break
            if hit is not None:
                drop((hit + size) * 3, (hit + 2 * size) * 3)
                return drop_duplicate_runs(table)
        break
    return table


# Канонический порядок столбцов в книге. Шапка, распознанная OCR, часто
# недосчитывает столбцы (например, «ОК» в таблицах 2, 4, 6, 7, 9, 11, 12),
# поэтому привязываем столбцы не по индексу, а к этой канве.
CANON_LEFT = ["code", "name", "portion", "water", "protein", "fat",
              "fat_saturated", "cholesterol", "sugars", "starch", "carbs",
              "fiber", "organic_acids", "ash"]
CANON_LEFT_T5 = ["code", "name", "portion", "water", "protein", "fat",
                 "fat_saturated", "fat_polyunsaturated", "cholesterol",
                 "sugars", "carbs", "ash"]
CANON_RIGHT = ["sodium", "potassium", "calcium", "magnesium", "phosphorus",
               "iron", "vitamin_a", "beta_carotene", "vitamin_a_re",
               "vitamin_e", "vitamin_b1", "vitamin_b2", "niacin",
               "niacin_equivalent", "vitamin_c", "energy_kcal"]
CANON_RIGHT_ALC = CANON_RIGHT[:15] + ["alcohol", "energy_kcal"]


def row_cells(tr) -> list[str]:
    return [clean_text(c.text_content()) for c in tr.iter("td", "th")]


def colspans(tr) -> list[int]:
    return [int(c.get("colspan") or 1) for c in tr.iter("td", "th")]


# ------------------------------------------------------------- шапка колонок
# Ключи нутриентов. Для каждой таблицы шапка своя, поэтому сопоставляем по
# названию столбца, а не по позиции.
LEFT_COLUMN_ALIASES = {
    "вода": "water", "бел": "protein", "жир": "fat", "нжк": "fat_saturated",
    "пнжк": "fat_polyunsaturated", "хол": "cholesterol", "мдс": "sugars",
    "кр": "starch", "угл": "carbs", "пв": "fiber",
    "ок": "organic_acids", "ok": "organic_acids", "зола": "ash",
}
RIGHT_COLUMN_ALIASES = {
    "na": "sodium", "k": "potassium", "ca": "calcium", "mg": "magnesium",
    "p": "phosphorus", "fe": "iron", "a": "vitamin_a", "kap": "beta_carotene",
    "кар": "beta_carotene", "pэ": "vitamin_a_re", "рэ": "vitamin_a_re",
    "tэ": "vitamin_e", "тэ": "vitamin_e", "b1": "vitamin_b1", "b2": "vitamin_b2",
    "pp": "niacin", "hэ": "niacin_equivalent", "нэ": "niacin_equivalent",
    "c": "vitamin_c", "с": "vitamin_c", "alk": "alcohol", "алк": "alcohol",
    "эц": "energy_kcal", "ккал": "energy_kcal",
}


def _is_alcohol_column(name: str) -> bool:
    """Столбец «Алк» в таблице напитков.

    В шапке OCR его часто нельзя восстановить целиком: распознаются обрывки
    «лк», «Ал», «Алк,», «Алк, % масс.» или «Ал.». Введём один строгий
    признак: короткая строка, начинающаяся на «алк/ал.» или равная «лк».
    """
    t = name.strip().lower().rstrip(" .,%")
    t = t.split(" ")[0] if t else t
    return t in {"лк", "алк", "ал", "алкоголь"} or t.startswith("алк")


def norm_header(text: str) -> str:
    t = clean_text(text)
    # «<br>мг%» и прочие единицы — отрезаем, оставляем только название столбца
    t = re.split(r"[\s<]*(?:мг|мкг|ккал)\s*%?", t, maxsplit=1)[0]
    t = t.lower().replace("₁", "1").replace("₂", "2").replace("ё", "е")
    t = t.replace("<br>", " ").replace("/", " ")
    t = t.rstrip(" .,%")
    # латиница в шапке (Na, K, Ca, Mg, P, Fe, A, Kap, B1, B2, PP, C) остаётся
    # латиницей — иначе «P» станет «Р» и перестанет отличаться от «PP»
    return t


def build_left_map(table) -> tuple[dict[int, str], int]:
    """Позиция столбца -> ключ. Шапка OCR часто недосчитывает столбец «ОК»,
    поэтому привязываем монотонно к канонической канве, а не по индексу."""
    mapping: dict[int, str] = {}
    pos = 0
    named: list[tuple[int, str]] = []
    trs = table.findall(".//thead/tr") or table.findall(".//tr")[:2]
    for cell in trs[0].iter("td", "th"):
        name = norm_header(cell.text_content())
        span = int(cell.get("colspan") or 1)
        if name.startswith("код"):
            mapping[pos] = "code"
        elif name.startswith("продук"):
            mapping[pos] = "name"
        elif name.startswith("порц"):
            mapping[pos] = "portion"
        elif name in LEFT_COLUMN_ALIASES:
            named.append((pos, LEFT_COLUMN_ALIASES[name]))
        pos += span
    t5 = any(k == "fat_polyunsaturated" for _, k in named)
    canon = CANON_LEFT_T5 if t5 else CANON_LEFT
    order = {k: i for i, k in enumerate(canon)}
    last = -1
    for p, key in named:
        target = order[key]
        if target <= last:
            continue
        mapping[p] = key
        last = target
    return mapping, len(canon)


def right_header_map(table) -> tuple[dict[int, str], int]:
    mapping: dict[int, str] = {}
    pos = 0
    named: list[tuple[int, str]] = []
    heads = table.findall(".//thead/tr")
    if not heads:
        # шапка отсутствует (страница пересобрана) — эталонный порядок
        return {}, 0
    for cell in heads[0].iter("td", "th"):
        name = norm_header(cell.text_content())
        span = int(cell.get("colspan") or 1)
        if name.startswith("код"):
            mapping[pos] = "code"
        elif _is_alcohol_column(name):
            named.append((pos, "alcohol"))
        elif name in RIGHT_COLUMN_ALIASES:
            named.append((pos, RIGHT_COLUMN_ALIASES[name]))
        pos += span
    canon = CANON_RIGHT_ALC if any(k == "alcohol" for _, k in named) else CANON_RIGHT
    order = {k: i for i, k in enumerate(canon)}
    last = -1
    for p, key in named:
        target = order[key]
        if target <= last:
            continue
        mapping[p] = key
        last = target
    return mapping, len(canon)


def expand(cells: list[str], spans: list[int] | None = None) -> list[str]:
    if not spans:
        return cells
    out = []
    for text, span in zip(cells, spans):
        out.extend([text] + [""] * (span - 1))
    return out


# ------------------------------------------------- таблица 11: столбец «Алк»
def table_has_alcohol(table) -> bool:
    """Таблица напитков с алкоголем (11.2): в шапке есть «Алк» или его обрывок.

    На сканах p187–p190 OCR регулярно распознаёт у шапки только «Алк» без
    остальных ячеек, а иногда — обрывок «лк»/«Ал». Признак: шапка на один
    столбец короче тела таблицы, а на месте потерянного стоит «Алк».
    """
    heads = [c for c in table.iter("thead")]
    if heads:
        heads = heads[0].findall("./tr")[:1]
    if not heads:
        # OCR потерял <thead>; шапка — первая строка, где встречается «Код»/«Na»
        heads = [tr for tr in table.findall(".//tr")[:3]
                 if sum(1 for c in row_cells(tr)
                        if norm_header(c) in HEADER_WORDS) >= 4]
    if not heads:
        return False
    names = [norm_header(c.text_content()) for c in heads[0].iter("td", "th")]
    if sum(1 for n in names if n.startswith("код")) >= 2:
        return False
    if any(_is_alcohol_column(n) for n in names):
        return True
    header_width = sum(int(c.get("colspan") or 1) for c in heads[0].iter("td", "th"))
    body_width = max((len(expand(row_cells(tr), colspans(tr)))
                      for tr in table.findall(".//tbody/tr")), default=0)
    # шапка недосчитала ровно один столбец — это «Алк» в таблице напитков
    canonical = {RIGHT_COLUMN_ALIASES.get(n, "") for n in names}
    return (header_width in (body_width - 1, body_width)
            and {"vitamin_c", "energy_kcal"} <= canonical)

def is_alcohol_11_2(table) -> bool:
    """Таблица 11.2 «Алкогольные напитки» (а не 11.1 «Безалкогольные»).

    Кроме того, в данных обязана быть хотя бы одна «спиртовая» метка — число
    вида «12,9(16,0)**», которого нет ни у одного другого продукта.
    """
    widths = [len(expand(row_cells(tr), colspans(tr)))
              for tr in table.findall(".//tbody/tr")]
    # 17 столбцов: «Продолжение» таблицы 11.2, где столбец «Наименование»
    # на скане пуст и OCR его не создал. 18 — первая страница разворота
    # («описание | Na…C | Алк | ЭЦ | Код»).
    if not widths or max(widths) < len(CANON_RIGHT):
        return False
    pattern = re.compile(r"^[−-]?\d+[.,]\d+\(\d+[.,]\d+\)\*{1,3}$")
    strong = re.compile(r"^[2-9]\d?[.,]\d+\(|^\d{2,}[.,]\d+\(")
    marks = [c for tr in table.findall(".//tbody/tr")
             for c in row_cells(tr) if pattern.match(c or "")]
    if any(strong.match(m) for m in marks):
        return True
    # Метки бывают только «слабыми» (0,2(0,2)**) — тогда нужный признак это
    # «Код | ЭЦ | ЭЦ» в конце строки короткого разворота.
    if max(widths) != len(CANON_RIGHT):
        return False
    dup_energy = 0
    for tr in table.findall(".//tbody/tr"):
        cs = row_cells(tr)
        if len(cs) >= 3 and CODE_RE.match(cs[-1] or "") and \
                re.fullmatch(r"-?\d+(?:[.,]\d+)?", (cs[-2] or "").strip()) and \
                re.fullmatch(r"-?\d+(?:[.,]\d+)?", (cs[-3] or "").strip()):
            dup_energy += 1
    return dup_energy >= 2 and bool(marks)


def alcohol_header_map(hmap: dict[int, str]) -> dict[int, str]:
    """Вставить недостающий «Алк» перед столбцом «ЭЦ».

    OCR таблицы 11.2 после потери ячеек шапки идёт так: … НЭ | C | ЭЦ | Код,
    а на скане: … НЭ | C | Алк | ЭЦ | Код. То есть все столбцы после C
    сдвинуты на один влево — ЭЦ попадает на «C», а настоящая ЭЦ теряется.
    """
    if "alcohol" in hmap.values():
        return hmap                       # «Алк» распознан прямо в шапке
    named = {p: k for p, k in hmap.items() if k != "code"}
    if not named:
        # шапки нет вовсе: после описания продукта идут 14 значений (Na…НЭ),
        # затем Алк (15-й) и ЭЦ (16-й), затем Код (17-й)
        out = {i: k for i, k in enumerate(CANON_RIGHT_ALC[:14])}
        out[14] = "alcohol"
        out[15] = "energy_kcal"
        out[16] = "code"
        return out
    if "vitamin_c" not in named.values():
        return hmap
    c_pos = next(p for p, k in named.items() if k == "vitamin_c")
    out: dict[int, str] = {}
    for p, k in hmap.items():
        if p <= c_pos or k == "code":
            out[p] = k
        else:
            out[p + 1] = k
    out[c_pos + 1] = "alcohol"
    return out



# -------------------------------------------------------------- левые страницы
PORTION_RE = re.compile(r"^(\d{1,3})(?:,\d+)?$")
PORTION_RANGE_RE = re.compile(r"^(\d{1,3})(?:,\d+)?\s*\(\d{1,3}\)$")
PCT_RE = re.compile(r"^%\s*[сc]\s*[.,]?\s*[пn]?\.?\s*(\d{1,3})", re.I)
PERCENT_CELL_RE = re.compile(r"^\d{1,3}(\s*\(\d{1,3}\))?$")
HEADER_WORDS = {"код", "продукты", "порция", "вода", "бел", "жир", "нжк",
                "пнжк", "хол", "мдс", "кр", "угл", "пв", "ok", "ок", "зола",
                "%", "мг%"}


def is_percent_row(cells: list[str], num_idx: list[int]) -> bool:
    """Строка «%с.п.»: все числовые ячейки — целые 0..300, часть пуста."""
    vals = [cells[i] if i < len(cells) else "" for i in num_idx]
    filled = [v for v in vals if v not in ("", "-", "–")]
    if not filled:
        return False
    if not all(PERCENT_CELL_RE.match(v) for v in filled):
        return False
    return True


def core_of(cells: list[str]) -> list[str]:
    """Только числовые ячейки строки (определяет тип строки)."""
    out = []
    for c in cells:
        if c == "":
            continue
        out.append(c)
    return out


def read_left_page(page: int):
    table = read_table(OCR_DIR / f"p{page:03d}.md")
    if table is None:
        return [], {}
    hmap, canon_len = build_left_map(table)
    num_cols = sorted(i for i, k in hmap.items()
                      if k not in ("code", "name", "portion"))
    name_pos = next((i for i, k in hmap.items() if k == "name"), 1)
    portion_pos = next((i for i, k in hmap.items() if k == "portion"), 2)
    # сырые строки — нужен доступ к следующей строке для проверки заголовка
    raw_rows = []
    for tr in table.findall(".//tbody/tr"):
        cells = expand(row_cells(tr), colspans(tr))
        if not cells or all(c == "" for c in cells):
            continue
        if sum(1 for c in cells if c.lower() in HEADER_WORDS) >= 4:
            continue
        # ведущие пустые ячейки (сдвиг вправо) убираем: первая непустая —
        # масса порции
        lead = 0
        while lead < len(cells) and cells[lead] == "":
            lead += 1
        if 0 < lead < len(cells) - 2 and (
                PORTION_RE.match(cells[lead])
                or PORTION_RANGE_RE.match(cells[lead])):
            cells = cells[lead:]
        # код с точкой на конце («4.1.2.» / «4.1.2.3.») — нормализуем
        if cells and cells[0].endswith(".") and CODE_RE.match(cells[0][:-1]):
            cells = [cells[0][:-1]] + cells[1:]
        raw_rows.append(cells)

    def row_kind(cs: list[str]) -> str:
        """'data' — строка с числами или порцией, иначе 'other'."""
        f = cs[0] if cs else ""
        if PCT_RE.match(f) or re.match(r"^%\s*[сc]", " ".join(cs[:3])):
            return "pct"
        if CODE_RE.match(f) or any(CODE_RE.match(c) for c in cs[:2]
                                   if c) or re.match(r"^\d[\d.]*\.?\s+\S", f):
            if PORTION_RE.match(f) or PORTION_RANGE_RE.match(f):
                return "other"
            return "data"
        if any(re.fullmatch(r"-?\d+(?:[.,]\d+)?", c) for c in cs[1:3]):
            return "data"
        return "other"

    items: list = []
    for idx, cells in enumerate(raw_rows):
        first = cells[0]

        def pick(i: int) -> str:
            return cells[i] if i < len(cells) else ""

        m = PCT_RE.match(first)
        if m:
            items.append(PercentRow(page, int(m.group(1)),
                                    {hmap[i]: parse_number(pick(i))
                                     for i in num_cols}, cells))
            continue
        m = PCT_RE.match(" ".join(c for c in cells[:3] if c))
        if m and not CODE_RE.match(first):
            items.append(PercentRow(page, int(m.group(1)),
                                    {hmap[i]: parse_number(pick(i))
                                     for i in num_cols}, cells))
            continue

        code = None
        backup_name = None
        for i, key in hmap.items():
            if key == "code" and CODE_RE.match(pick(i)):
                code = pick(i)
                break
        if code is None and CODE_RE.match(first):
            code = first
        if code is None:
            mc = re.match(r"^(\d{1,2}(?:\.\d{1,3}){2,4})\.?\s+(\S.*)$", first)
            if mc and mc.group(2):
                code, backup_name = mc.group(1), mc.group(2)

        portion_cell = pick(portion_pos)
        has_portion = bool(portion_cell) and bool(
            PORTION_RANGE_RE.match(portion_cell))
        has_num_portion = bool(portion_cell) and bool(PORTION_RE.match(portion_cell))
        # код вида «4.1.2.3.» + название в 1-й ячейке: строка сдвинута влево,
        # поэтому порция ищется в первых ячейках, а не строго на позиции
        code_dot = False
        # строка короче канона на 1 и без числа в «Порции»: потерян столбец
        # «Порция» (он пуст на скане), значения сдвинуты на 1 влево
        missing_portion = (bool(code) and not has_num_portion
                           and 0 < len(cells) - 1 < canon_len
                           and bool(cells[2]) if len(cells) > 2 else False)
        if missing_portion:
            cells = cells[:2] + [""] + cells[2:]
            portion_cell = ""
            has_portion = False
            has_num_portion = False
        data_like = sum(1 for i in num_cols if pick(i) not in ("", "-", "–"))

        # продавленная концом строки ячейка «Зола» — дополняем строку справа
        def pad_to_canon(cs: list[str]) -> list[str]:
            if code and len(cs) < canon_len:
                return cs + [""] * (canon_len - len(cs))
            return cs

        # --- заголовки разделов -------------------------------------------
        if code and not has_num_portion:
            after = [c for c in cells[1:] if c]
            # «Код | Текст | (пусто)…» и в строке нет нутриентов
            if len(after) == 1 and data_like == 0:
                items.append(SectionHeading(page, code.rstrip("."), after[0]))
                continue
            if not after:
                # «[Код, Текст]» с названием в первой ячейке («4.1.2.3. Скумбрия»)
                mc = re.match(r"^(\d{1,2}(?:\.\d{1,3}){1,4})\.?\s+(\D.*)$", first)
                if mc:
                    items.append(SectionHeading(page, mc.group(1).rstrip("."),
                                                mc.group(2)))
                    continue
        if not code:
            # «МОРОЖЕНОЕ» / «7.2 Орехи» / «10.1 САХАР» без отдельного кода
            has_numbers = any(
                re.fullmatch(r"-?\d+(?:[.,]\d+)?", c) for c in cells[2:])
            if not has_numbers:
                text = " ".join(c for c in cells if c)
                ms = re.match(r"^(\d{1,2}(?:\.\d{1,3}){0,3})\.?\s+(.+)$", text)
                if ms and not PORTION_RE.match(first):
                    items.append(SectionHeading(page, ms.group(1), ms.group(2)))
                    continue
                if re.search(r"[А-Яа-я]", text) and not PORTION_RE.match(first):
                    # повтор баннера раздела («МОРОЖЕНОЕ») — не отдельный код
                    if all(ch.isupper() or not ch.isalpha() for ch in text):
                        continue
                    items.append(SectionHeading(page, None, text))
                    continue

        # код с точкой на конце («4.1.2.3.») — нормализуем и продолжаем
        if code and not portion_cell:
            after = [c for c in cells[1:] if c]
            if len(after) == 1:
                name_guess = after[0]
                nxt = raw_rows[idx + 1] if idx + 1 < len(raw_rows) else []
                looks_like_product = bool(nxt) and CODE_RE.match(nxt[0] or "x") is None
                if looks_like_product:
                    items.append(LeftRow(page, code.rstrip("."), name_guess,
                                         nxt[2] if len(nxt) > 2 else "",
                                         {hmap[i]: parse_number(
                                             nxt[i] if i < len(nxt) else "")
                                          for i in num_cols},
                                         cells))
                    continue

        if code:
            name = pick(name_pos)
            if not name and backup_name:
                name = backup_name
            if code_dot:
                # «4.1.2.3. | Название | 100 | …» — код и имя слиты в 0-й
                # ячейке, поэтому вся строка сдвинута на одну влево
                mc = re.match(r"^(\d{1,2}(?:\.\d{1,3}){1,4})\.?$", first)
                shifted = [""] + cells[:-1]
                name = pick(name_pos) or (cells[1] if len(cells) > 1 else "")
                cells_full = shifted + [""] * (canon_len - len(shifted))
                values = {hmap[i]: parse_number(
                    cells_full[i] if i < len(cells_full) else "")
                    for i in num_cols}
                items.append(LeftRow(page, code.rstrip("."), name,
                                     cells_full[portion_pos] if portion_pos
                                     < len(cells_full) else "",
                                     values, cells))
                continue
            cells = pad_to_canon(cells)
            values = {hmap[i]: parse_number(pick(i)) for i in num_cols}
            items.append(LeftRow(page, code, name, portion_cell, values, cells))
            continue
        if is_percent_row(cells, num_cols):
            gram = None
            for c in cells:
                mm = re.search(r"(\d{1,3})", c) if c.startswith("%") else None
                if mm:
                    gram = int(mm.group(1))
                    break
            items.append(PercentRow(page, gram or 0,
                                    {hmap[i]: parse_number(pick(i))
                                     for i in num_cols}, cells))
            continue

        # строка порции: без столбца «Порция», остальные значения сдвинуты на 1.
        # Если ячеек не хватает (крайняя «Зола» потеряна на скане), сдвиг = 2.
        mp = PORTION_RANGE_RE.match(first) or PORTION_RE.match(first)
        if mp:
            expected = canon_len - 1              # без «Код»
            shift = 1 if len(cells) >= expected else 2
            values = {}
            for pos, key in hmap.items():
                if key in ("code", "name", "portion"):
                    continue
                values[key] = parse_number(pick(pos - shift))
            extra = re.search(r"\((\d{1,3})\)", first)
            items.append(PortionRow(page, int(mp.group(1)), values, cells,
                                    alt=int(extra.group(1)) if extra else None))
            continue

        title = "|".join(c for c in cells if c) or first
        # обрывок предыдущей строки, распознанный повторно («тушеная|50|32,0|…»)
        head = first.strip().lower()
        if (head and not head[0].isdigit() and len(cells) > 2
                and PORTION_RE.match(cells[1] or "")):
            continue
        items.append(SectionHeading(page, None, title))
    return items, hmap


def _missing_columns(hmap: dict[int, str]) -> set[str]:
    """Какие столбцы канона не названы в шапке."""
    named = set(hmap.values())
    canon = CANON_RIGHT_ALC if "alcohol" in named else CANON_RIGHT
    return set(canon) - named


def fix_extra_energy_column(cells: list[str], hmap: dict[int, str],
                            row_width: int) -> list[str]:
    """Данные на 100 г + строка порции в одном <tr>.

    OCR иногда склеивает строку «100 г» с последующей строкой порции
    (например, в таблице напитков: Na…Алк ЭЦ | Код | ЭЦ порции). В такой
    строке на один столбец больше, чем в шапке, и последняя ячейка — не код.
    Отрезаем хвост, чтобы код вновь стал последним столбцом.
    """
    if not cells or not hmap:
        return cells
    if (len(cells) == len(CANON_RIGHT) + 1
            and CODE_RE.match(cells[-1] or "")
            and cells[-2] != "" and cells[-2] == cells[-3]):
        return cells[:-2] + [cells[-1]]
    has_alcohol = "alcohol" in hmap.values()
    has_energy = "energy_kcal" in hmap.values()
    dropped = _missing_columns(hmap)
    if has_alcohol and "alcohol" not in dropped:
        return cells
    # шапка без «ЭЦ» — тогда склейка и есть источник ЭЦ
    if not has_alcohol and not (has_energy or "energy_kcal" in dropped):
        return cells
    if not CODE_RE.match(cells[-2] or ""):
        return cells
    tail = cells[-1]
    if tail == "" or CODE_RE.match(tail):
        return cells
    if not re.fullmatch(r"-?\d+(?:[.,]\d+)?(?:\(.*\)\*{0,3})?", tail.strip()):
        return cells
    return cells[:-1]


def _alcohol_page(table, hmap: dict[int, str], row_width: int) -> bool:
    """Больше не используется: см. is_alcohol_11_2()."""
    return False


def product_section_left(table) -> bool:
    """Страница содержит названия номенклатурных строк.

    На правых страницах названия короткие («Водка», «Наливка «Сливянка»»),
    но они есть и отличают их от страниц-продолжений, где в первых столбцах
    только числа. Ищем слово из 4+ букв, не являющееся заголовком шапки.
    """
    letters = re.compile(r"[A-Za-zА-Яа-яЁё]{4,}")
    for tr in table.findall(".//tbody/tr"):
        for c in expand(row_cells(tr), colspans(tr))[:3]:
            word = (c or "").strip()
            if letters.search(word) and norm_header(word) not in HEADER_WORDS:
                return True
    return False


def _energy_values(table) -> list[float]:
    """Последние числовые ячейки строк-данных (кандидаты в «ЭЦ»)."""
    out: list[float] = []
    for tr in table.findall(".//tbody/tr"):
        cells = expand(row_cells(tr), colspans(tr))
        if not cells or not CODE_RE.match(cells[-1] or ""):
            continue
        v = parse_number(cells[-2] if len(cells) > 1 else None)
        if isinstance(v, (int, float)):
            out.append(float(v))
    return out


def _energy_moved_left(hmap: dict[int, str], table) -> bool:
    """Шапка «ЭЦ» стоит на несколько столбцов левее конца строки."""
    e_pos = next((p for p, k in hmap.items() if k == "energy_kcal"), None)
    code_pos = next((p for p, k in hmap.items() if k == "code"), None)
    if e_pos is None or code_pos is None:
        return False
    return code_pos - e_pos != 1


# ------------------------------------------------------------- правые страницы
def read_right_page(page: int) -> tuple[list[RightRow | RightSection], dict[int, str]]:
    table = read_table(OCR_DIR / f"p{page:03d}.md")
    if table is None:
        return [], {}
    hmap, canon_len = right_header_map(table)
    header_code_col = next((i for i, k in hmap.items() if k == "code"), None)
    row_width = max((len(expand(row_cells(tr), colspans(tr)))
                     for tr in table.findall(".//tbody/tr")), default=0)
    # Два разных формата правой страницы двухполосного разворота:
    #   * 17 столбцов — «Продолжение» без описания продукта (Код в конце);
    #   * 18 столбцов — начало таблицы 11.2 (п.187–190): описание + Код + Алк.
    # Поэтому «сдвиг шапки» определяем только для страниц без описаний:
    # иначе код продукта (в 16-м или 17-м столбце) неотличим от сдвига.
    labels = product_section_left(table)
    alcohol_page = is_alcohol_11_2(table)
    desc_layout = labels and not alcohol_page      # 11.1/p190-подобная страница
    if alcohol_page:
        # п.187–190 (таблица 11.2). Шапка OCR на этих страницах почти всегда
        # испорчена, а значения идут по позициям от начала данных:
        #   [Na K Ca Mg P Fe A Кар РЭ ТЭ B1 B2 PP НЭ C] [Алк] [ЭЦ] [Код]
        # — 18 ячеек. Признаки считаем внутри строки, а не по шапке.
        hmap = {i: k for i, k in enumerate(CANON_RIGHT_ALC[:15])}
        hmap[17] = "code"
        canon_len = len(CANON_RIGHT_ALC) + 1
    elif desc_layout and (not hmap or "code" not in hmap.values()):
        # страница с описаниями, но без шапки: в каждой строке
        # [описание или код][Na…ЭЦ][Код] — код стоит предпоследним
        hmap = {i + 1: k for i, k in enumerate(CANON_RIGHT)}
        hmap[len(CANON_RIGHT) + 1] = "code"
        canon_len = len(CANON_RIGHT) + 2
    elif not hmap or "code" not in hmap.values() or \
            (header_code_col != row_width - 1 and
             header_code_col != row_width - 2):
        hmap = {i: k for i, k in enumerate(CANON_RIGHT)}
        hmap[len(CANON_RIGHT)] = "code"
        canon_len = len(CANON_RIGHT) + 1
    items: list = []
    for tr in table.findall(".//tbody/tr"):
        cells = expand(row_cells(tr), colspans(tr))
        if not cells or all(c == "" for c in cells):
            continue
        if sum(1 for c in cells if c.lower() in HEADER_WORDS) >= 4:
            continue
        cells = fix_extra_energy_column(cells, hmap, row_width)
        # код с точкой на конце («2.5.1.») — нормализуем
        for i, c in enumerate(cells):
            if c.endswith(".") and CODE_RE.match(c[:-1]):
                cells[i] = c[:-1]
        # убрать хвостовую пустую ячейку после кода (артефакт rowspan)
        while len(cells) > 2 and cells[-1] == "" and CODE_RE.match(cells[-2]):
            cells = cells[:-1]
        # у части строк последняя ячейка (код) отсутствует — тогда все
        # значения стоят на своих местах по позиции, а не по индексу
        nonempty = [c for c in cells if c]
        # баннер «Таблица N. НАЗВАНИЕ» в начале разворота
        if nonempty and re.match(r"^Таблица\s+\d+", nonempty[0], re.I):
            continue
        code_cell = None
        for i, key in hmap.items():
            if key == "code" and i < len(cells) and CODE_RE.match(cells[i]):
                code_cell = cells[i]
        # код мог сместиться влево, если один из столбцов потерян: ищем его
        # по образцу, начиная с конца строки
        if code_cell is None:
            for i in range(len(cells) - 1, max(len(cells) - 4, -1), -1):
                if CODE_RE.match(cells[i]):
                    code_cell = cells[i]
                    hmap = dict(hmap)
                    for k in [k for k, v in hmap.items() if v == "code"]:
                        hmap.pop(k, None)
                    hmap[i] = "code"
                    break
        if code_cell and len(nonempty) <= 2:
            title = max(nonempty, key=len)
            items.append(RightSection(page, code_cell, title))
            continue
        has_trailing_code = len(cells) >= canon_len
        values: dict[str, float | int | None] = {}
        alcohol_vol = None
        keys = [k for i, k in sorted(hmap.items()) if k != "code"]
        # шапка могла недосчитать столбцы (часто теряется «C» или «ЭЦ»):
        # в этом случае порядок восстанавливаем по эталону
        if alcohol_page:
            keys = list(CANON_RIGHT_ALC)      # таблица 11.2: канон + «Алк»
        elif len(keys) < len(CANON_RIGHT) and "эн" not in keys:
            keys = list(CANON_RIGHT)
        n_keys = len(keys)
        # позиция ячейки с кодом
        code_pos = cells.index(code_cell) if code_cell else None
        # ячейки, доступные под значения
        limit = code_pos if code_pos is not None else len(cells)
        n = sum(1 for i in range(limit) if cells[i] != "")
        if not alcohol_page and _values_skipped_vitamin_c(cells, limit, n_keys):
            # Образец книги без витамина C: Na K Ca Mg P Fe A Kap РЭ TЭ B1 B2
            # PP НЭ ЭЦ (15 значений, p104-p110). Канон «с C» дал бы НЭ=C и
            # ЭЦ=НЭ, поэтому столбец C выкидывается явно.
            keys = [k for k in CANON_RIGHT if k != "vitamin_c"]
            n_keys = len(keys)
        if alcohol_page:
            # п.187–190: «Алк» помечен «(x,y)**», «ЭЦ» — следующее число.
            # Строки-«Продолжение» короче на два столбца от начала, так что
            # опираемся на позицию метки, а не на фиксированный индекс.
            alk = [i for i in range(len(cells))
                   if re.search(r"\(\d+[.,]\d+\)\*{1,3}$", cells[i] or "")
                   and 9 <= i <= 17]
            k = alk[0] if alk else (16 if len(cells) > 16 else len(cells) - 4)
            pairs = [(i, CANON_RIGHT_ALC[i]) for i in range(min(k, 15))]
            pairs.append((k, "alcohol"))
            e = k + 1
            while e < len(cells) and not re.fullmatch(
                    r"-?\d+(?:[.,]\d+)?", (cells[e] or "").strip()):
                e += 1
            if e < len(cells):
                pairs.append((e, "energy_kcal"))
            elif code_pos is not None:
                for j in range(code_pos + 1, len(cells)):
                    if re.fullmatch(r"-?\d+(?:[.,]\d+)?", (cells[j] or "").strip()):
                        pairs.append((j, "energy_kcal"))
                        break
        elif n == n_keys:
            # все столбцы на месте: строгое соответствие позиций. Если в
            # строке ровно позиций канона, но последний столбец «C» на месте
            # «ЭЦ», а НЭ повторяет ЭЦ — C на скане пуст.
            pairs = [(i, keys[i]) for i in range(min(limit, n_keys))]
            e_at = next((i for i, k in pairs if k == "energy_kcal"), None)
            c_at = next((i for i, k in pairs if k == "vitamin_c"), None)
            ne_at = next((i for i, k in pairs
                          if k == "niacin_equivalent"), None)
            if e_at is None and c_at is not None and \
                    c_at == limit - 1 and ne_at is not None and \
                    ne_at == c_at - 1 and _same_number(cells, ne_at, c_at):
                pairs = [(i, k) for i, k in pairs if k != "vitamin_c"]
                pairs.append((c_at, "energy_kcal"))
        elif limit == n_keys - 1 and limit > 0:
            # Слева от кода ровно столько ячеек, сколько столбцов в каноне,
            # но шапка недосчитала один (чаще всего «C»): последняя ячейка
            # перед кодом — это ЭЦ, а не «C».
            pairs = [(i, keys[i]) for i in range(min(limit - 1, n_keys - 1))]
            pairs.append((limit - 1, "energy_kcal"))
        else:
            # Столбцов меньше, чем в каноне. Значения идут подряд от Na.
            # Если ширина строки на единицу меньше ширины страницы, значит
            # этот столбец на скане пуст или потерян в середине; какой
            # именно — определяем по пустой ячейке, если она есть.
            pairs = []
            empties = [i for i in range(min(limit, n_keys)) if cells[i] == ""]
            if len(empties) == 1 and limit <= n_keys:
                # пустая ячейка указывает, где потерян столбец
                gap = empties[0]
                pairs = [(i, keys[i]) for i in range(gap)]
                pairs += [(i, keys[i + 1]) for i in range(gap, min(limit, n_keys - 1))]
            else:
                # пустых нет — последнее значение принадлежит ЭЦ,
                # а недостающий «C» считается отсутствующим
                pairs = [(i, keys[i]) for i in range(min(n, n_keys))]
                if 0 < n <= n_keys and keys[n - 1] == "vitamin_c":
                    pairs[-1] = (n - 1, "energy_kcal")
        for i, key in pairs:
            raw = cells[i] if 0 <= i < len(cells) else ""
            if key == "alcohol":
                grams, vol = parse_alcohol(raw)
                values["alcohol"] = grams
                alcohol_vol = vol
            else:
                values[key] = parse_number(raw)
        items.append(RightRow(page, values, alcohol_vol, cells))
    return items, hmap


def _same_number(cells: list[str], i: int, j: int) -> bool:
    """Две ячейки содержат одно и то же число (с точностью записи)."""
    a, b = parse_number(cells[i] if i < len(cells) else None), \
        parse_number(cells[j] if j < len(cells) else None)
    return a is not None and b is not None and float(a) == float(b)


def _values_skipped_vitamin_c(cells: list[str], limit: int,
                              n_keys: int) -> bool:
    """Строка содержит 15 значений образца «без витамина C».

    На p104-p110 (и на строке 5.1.8) в книге физически нет столбца «C»:
    Na K Ca Mg P Fe A Kap РЭ TЭ B1 B2 PP НЭ ЭЦ. Канон же с C ожидает 16
    значений, поэтому позиционный разбор ставил ЭЦ в «НЭ», а «НЭ» в «C»
    (`vitamin_c == niacin_equivalent == energy_kcal`, см. 5.1.5/5.1.8).
    """
    if n_keys != len(CANON_RIGHT):
        return False
    n = sum(1 for i in range(limit) if cells[i] != "")
    if n != len(CANON_RIGHT) - 1:
        return False
    ne_at, e_at = len(CANON_RIGHT) - 2, len(CANON_RIGHT) - 1
    if e_at >= limit:
        return False
    return _same_number(cells, ne_at, e_at)


def repair_energy(values: dict, left: dict | None = None) -> None:
    """Чистка ЭЦ по физической проверке.

    Иногда OCR меняет местами два последних числа (витамин C и ЭЦ). Признак:
    ЭЦ неправдоподобно мала — меньше расчётной по БЖУ в 3+ раза, а соседнее
    значение (витамин C) на неё похоже.
    """
    if not left:
        return
    calc = (4.0 * (left.get("protein") or 0)
            + 9.0 * (left.get("fat") or 0)
            + 3.75 * (left.get("carbs") or 0)
            + 3.0 * (left.get("organic_acids") or 0)
            + 2.0 * (left.get("fiber") or 0))
    if calc <= 20:
        return
    e = values.get("energy_kcal")
    c = values.get("vitamin_c")
    if e is None:
        if c is not None and abs(float(c) - calc) < max(40.0, calc * 0.5):
            values["energy_kcal"] = c
            values["vitamin_c"] = None
        return
    if float(e) < calc / 3 and c is not None and float(c) > calc / 2:
        values["energy_kcal"], values["vitamin_c"] = c, e


if __name__ == "__main__":
    items, hmap = read_left_page(27)
    print("hmap", hmap)
    for it in items[:6]:
        print(it)
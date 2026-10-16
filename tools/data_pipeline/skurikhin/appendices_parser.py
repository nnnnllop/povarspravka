"""Parser for Appendices (Приложения 1, 2, 3) of Skurikhin 2002 book.

Appendix 1 (pages 201-206): Waste percentage (размер несъедобной части, % отходов)
Appendix 2 (pages 207-209): Volume measures in grams (стаканы, ложки)
Appendix 3 (page 210): Single piece weights in grams (масса 1 штуки)
"""
from typing import Dict, List, Optional, Tuple
import re
import pymupdf


def parse_appendix_1(doc: pymupdf.Document) -> Dict[str, float]:
    """Parse Appendix 1: waste percentages (отходы / несъедобная часть) by product name."""
    waste_map: Dict[str, float] = {}

    for pno in range(201, 207):
        page = doc[pno]
        words = page.get_text("words")
        data_words = [w for w in words if w[1] > 35]

        # Multi-column layout:
        # Left half: name x < 230, pct x 230..275
        # Right half: name x 275..470, pct x 470..545
        left_words = [w for w in data_words if w[0] < 275]
        right_words = [w for w in data_words if w[0] >= 275]
        columns = [(left_words, 225), (right_words, 470)]

        for col_words, pct_thresh in columns:
            lines: Dict[float, List] = {}
            for w in col_words:
                y = round(w[1] / 6.0) * 6.0
                lines.setdefault(y, []).append(w)

            for y in sorted(lines.keys()):
                lw = sorted(lines[y], key=lambda w: w[0])
                name_tokens = [w[4] for w in lw if w[0] < pct_thresh]
                pct_tokens = [w[4] for w in lw if w[0] >= pct_thresh]

                name_str = " ".join(name_tokens).strip()
                if not name_str or any(h in name_str for h in ["Продукт", "Несъедобная", "Продолжение", "Приложение", "товарной"]):
                    continue

                if pct_tokens:
                    pct_str = "".join(pct_tokens)
                    m = re.search(r'\d+(?:[\.,]\d+)?', pct_str)
                    if m:
                        val = float(m.group(0).replace(',', '.'))
                        if 0 <= val <= 95:
                            clean_name = re.sub(r'^[-\~–—\s\d\.]+', '', name_str).strip()
                            # Normalize Roman numerals I -> 1, II -> 2
                            clean_name = re.sub(r'\bII\b', '2', clean_name, flags=re.I)
                            clean_name = re.sub(r'\bI\b', '1', clean_name, flags=re.I)
                            clean_name = re.sub(r'\s+', ' ', clean_name).strip()
                            if clean_name and len(clean_name) > 2:
                                norm_key = clean_name.lower()
                                waste_map[norm_key] = val

    return waste_map


def parse_appendix_2(doc: pymupdf.Document) -> Dict[str, Dict[str, float]]:
    """Parse Appendix 2: measures in grams (стакан чайный 250ml, граненый 200ml, ст. ложка 18ml, ч. ложка 5ml)."""
    measures_map: Dict[str, Dict[str, float]] = {}

    for pno in range(207, 210):
        page = doc[pno]
        words = page.get_text("words")
        data_words = [w for w in words if w[1] > 115]

        # Column boundaries for measures on pages 207-209:
        # Product name: x < 280
        # Стакан чайный (250 мл): x ~ 280..340
        # Стакан граненый (200 мл): x ~ 340..400
        # Столовая ложка (18 мл): x ~ 400..460
        # Чайная ложка (5 мл): x ~ 460..520
        lines: Dict[float, List] = {}
        for w in data_words:
            y = round(w[1] / 6.5) * 6.5
            lines.setdefault(y, []).append(w)

        for y in sorted(lines.keys()):
            lw = sorted(lines[y], key=lambda w: w[0])
            name_tokens = [w[4] for w in lw if w[0] < 280]
            c_tea = [w[4] for w in lw if 280 <= w[0] < 340]
            c_gran = [w[4] for w in lw if 340 <= w[0] < 400]
            spoon_tb = [w[4] for w in lw if 400 <= w[0] < 460]
            spoon_ts = [w[4] for w in lw if 460 <= w[0] < 530]

            name_str = " ".join(name_tokens).strip()
            if not name_str or any(h in name_str for h in ["Продукт", "Масса", "Продолжение", "Приложение"]):
                continue

            def parse_num(toks: List[str]) -> Optional[float]:
                if not toks:
                    return None
                m = re.search(r'\d+(?:[\.,]\d+)?', "".join(toks))
                return float(m.group(0).replace(',', '.')) if m else None

            v_tea = parse_num(c_tea)
            v_gran = parse_num(c_gran)
            v_tb = parse_num(spoon_tb)
            v_ts = parse_num(spoon_ts)

            if any(v is not None for v in [v_tea, v_gran, v_tb, v_ts]):
                clean_name = re.sub(r'^[-\~–—\s\d\.]+', '', name_str).strip()
                if clean_name:
                    meas: Dict[str, float] = {}
                    if v_tea: meas["стакан (чайный 250 мл)"] = v_tea
                    if v_gran: meas["стакан (граненый 200 мл)"] = v_gran
                    if v_tb: meas["столовая ложка"] = v_tb
                    if v_ts: meas["чайная ложка"] = v_ts
                    measures_map[clean_name.lower()] = meas

    return measures_map


def parse_appendix_3(doc: pymupdf.Document) -> Dict[str, float]:
    """Parse Appendix 3 (page 210): piece weights in grams (1 шт)."""
    pieces_map: Dict[str, float] = {}
    page = doc[210]
    words = page.get_text("words")
    data_words = [w for w in words if w[1] > 100]

    # Two columns on page 210:
    # Left: x < 280 (name x < 210, grams x 210..270)
    # Right: x >= 280 (name x 280..470, grams x 470..530)
    left_words = [w for w in data_words if w[0] < 280]
    right_words = [w for w in data_words if w[0] >= 280]

    for col_words, g_thresh in [(left_words, 205), (right_words, 465)]:
        lines: Dict[float, List] = {}
        for w in col_words:
            y = round(w[1] / 6.0) * 6.0
            lines.setdefault(y, []).append(w)

        for y in sorted(lines.keys()):
            lw = sorted(lines[y], key=lambda w: w[0])
            name_tokens = [w[4] for w in lw if w[0] < g_thresh]
            g_tokens = [w[4] for w in lw if w[0] >= g_thresh]

            name_str = " ".join(name_tokens).strip()
            if not name_str or any(h in name_str for h in ["Продукт", "Масса", "Приложение"]):
                continue

            if g_tokens:
                m = re.search(r'\d+(?:[\.,]\d+)?', "".join(g_tokens))
                if m:
                    val = float(m.group(0).replace(',', '.'))
                    clean_name = re.sub(r'^[-\~–—\s\d\.]+', '', name_str).strip()
                    if clean_name and len(clean_name) > 2:
                        pieces_map[clean_name.lower()] = val

    return pieces_map


def find_waste_percentage(product_name: str, waste_map: Dict[str, float]) -> Optional[float]:
    """Fuzzy / prefix match product name to waste percentage in Appendix 1.
    Cooked/prepared dishes (soups, purees, cutlets, fried/boiled items) NEVER receive cold raw waste.
    """
    p_lower = product_name.lower()

    # Guard: do not assign raw cold-processing waste to prepared dishes
    cooked_markers = [
        "суп", "борщ", "бульон", "каша", "пюре", "котлет", "бифштекс", "жарен",
        "отварн", "варен", "тушен", "печен", "запечен", "пирож", "ватрушк", "хлеб",
        "колбас", "сосиск", "сыр", "масло", "творог", "кефир", "молоко", "йогурт",
        "сметана", "соус", "сок", "напиток", "компот", "кисель", "паста", "по 1-", "по 2-"
    ]
    if any(m in p_lower for m in cooked_markers):
        return None

    # Base raw potato standard waste
    if p_lower.strip() in ["картофель", "картофель ранний", "картофель молодой"]:
        return 20.0

    # 1. Exact match
    if p_lower in waste_map:
        return waste_map[p_lower]

    # 2. Substring match
    words = re.findall(r'[а-яё]+', p_lower)
    for k, v in waste_map.items():
        if len(k) > 4 and k in p_lower:
            return v
        k_words = re.findall(r'[а-яё]+', k)
        if len(k_words) >= 2 and all(kw in words for kw in k_words):
            return v

    # 3. First significant word match for raw vegetables / fruits / raw meats
    if words:
        first_word = words[0]
        if len(first_word) >= 5:
            for k, v in waste_map.items():
                if k.startswith(first_word):
                    return v

    return None


def get_measures_for_product(product_name: str,
                             measures_map: Dict[str, Dict[str, float]],
                             pieces_map: Dict[str, float]) -> List[Tuple[str, float]]:
    """Return all available measures for product (cups, spoons, 1 piece)."""
    p_lower = product_name.lower()
    res: List[Tuple[str, float]] = []

    # Check piece weights (шт)
    matched_piece = None
    if p_lower in pieces_map:
        matched_piece = pieces_map[p_lower]
    else:
        for k, v in pieces_map.items():
            if len(k) > 4 and (k in p_lower or p_lower in k):
                matched_piece = v
                break
    if matched_piece:
        res.append(("1 шт.", matched_piece))

    # Check volume measures
    matched_vol = None
    if p_lower in measures_map:
        matched_vol = measures_map[p_lower]
    else:
        for k, v in measures_map.items():
            if len(k) > 4 and (k in p_lower or p_lower in k):
                matched_vol = v
                break

    if matched_vol:
        for m_name, grams in matched_vol.items():
            res.append((m_name, grams))

    return res


if __name__ == "__main__":
    import sys
    from config import DEFAULT_PDF_PATH
    sys.stdout.reconfigure(encoding="utf-8")
    doc = pymupdf.open(str(DEFAULT_PDF_PATH))
    w_map = parse_appendix_1(doc)
    m_map = parse_appendix_2(doc)
    p_map = parse_appendix_3(doc)
    print(f"Parsed Appendix 1 (waste %): {len(w_map)} items")
    print(f"Parsed Appendix 2 (measures): {len(m_map)} items")
    print(f"Parsed Appendix 3 (pieces): {len(p_map)} items")

    # Test some samples
    for test_prod in ["Картофель", "Капуста белокочанная", "Говядина 1 категории", "Кефир", "Яйцо куриное", "Яблоки"]:
        wp = find_waste_percentage(test_prod, w_map)
        meas = get_measures_for_product(test_prod, m_map, p_map)
        print(f"  {test_prod:<25} -> waste: {wp}% | measures: {meas}")

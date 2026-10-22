"""Comprehensive Table Extractor for Skurikhin 2002 book.

Extracts all data tables across pages 24-193 (all 12 food groups, 85 spreads),
including macronutrients, micronutrients, calories, waste %, and measures.
"""
from typing import Dict, List, Optional, Tuple, Any
import re
import pymupdf

from .config import (
    DEFAULT_PDF_PATH,
    FOOD_GROUPS,
    KNOWN_CANONICAL_NAMES,
    KNOWN_KCAL_FIXES,
    KNOWN_PROXIMATE_FIXES,
    KNOWN_WASTE_OVERRIDES,
)
from .subject_index_parser import parse_subject_index
from .appendices_parser import (
    parse_appendix_1,
    parse_appendix_2,
    parse_appendix_3,
    find_waste_percentage,
    get_measures_for_product
)


def clean_single_token(tok: str) -> str:
    """Clean individual OCR token, translating common OCR letter confusions."""
    t = tok.strip()
    if not t or re.fullmatch(r'[\W_jJ°•`^~\\/\[\]|!]+', t):
        return ""
    # Cyrillic OCR letter substitutions in numbers
    t = re.sub(r'^[ьЬ]', '5', t)
    t = re.sub(r'[оОoO]$', '0', t)
    t = re.sub(r'[оОoO][\.,]', '0.', t)
    t = re.sub(r'[\.,][оОoO]', '.0', t)
    t = re.sub(r'^[,\.]+(\d)', r'\1', t)
    t = re.sub(r'[^0-9,\.]', '', t).replace(',', '.')
    return t


def parse_cell_tokens(tokens: List[str]) -> float:
    """Clean OCR tokens in a cell and parse to float."""
    if not tokens:
        return 0.0

    valid = []
    for t in tokens:
        c = clean_single_token(t)
        if c:
            valid.append(c)

    if not valid:
        return 0.0

    # If first token is 100 anchor and there are other tokens, drop 100 anchor
    if len(valid) > 1 and valid[0] in ['100', '100.0', '1', '1.0', '1.']:
        valid = valid[1:]

    val_str = valid[0]
    for c in valid:
        if '.' in c:
            val_str = c
            break

    parts = val_str.split('.')
    if len(parts) > 2:
        val_str = parts[0] + '.' + parts[1]

    try:
        return float(val_str)
    except ValueError:
        return 0.0



def detect_columns_left(pe: pymupdf.Page) -> List[Tuple[str, float, float]]:
    """Detect dynamic column boundaries for left page (macronutrients)."""
    words = pe.get_text('words')
    hw = [w for w in words if 35 <= w[1] <= 75 and w[0] > 180]

    col_defs = [
        ('water', lambda t: 'вод' in t),
        ('protein', lambda t: 'бел' in t),
        ('fat', lambda t: 'жир' in t),
        ('sfa', lambda t: 'нжк' in t),
        ('pufa', lambda t: 'пнжк' in t),
        ('chol', lambda t: 'хол' in t),
        ('sugars', lambda t: 'мдс' in t or t == 'с'),
        ('starch', lambda t: t in ['кр', 'крахмал', 'гкр']),
        ('carbs', lambda t: 'угл' in t),
        ('fiber', lambda t: 'пв' in t),
        ('organic_acids', lambda t: 'ок' in t),
        ('ash', lambda t: 'зол' in t),
    ]

    detected = []
    for cname, matcher in col_defs:
        matching = [w for w in hw if matcher(w[4].lower())]
        if matching:
            xc = sum((w[0]+w[2])/2 for w in matching) / len(matching)
            detected.append((cname, xc))

    # Fallback default positions if headers not detected
    if len(detected) < 6:
        return [
            ('water', 225, 255),
            ('protein', 255, 285),
            ('fat', 285, 315),
            ('sfa', 315, 345),
            ('chol', 345, 375),
            ('sugars', 375, 400),
            ('starch', 400, 425),
            ('carbs', 425, 455),
            ('fiber', 455, 485),
            ('organic_acids', 485, 515),
            ('ash', 515, 550),
        ]

    detected.sort(key=lambda x: x[1])
    bounds = []
    for i in range(len(detected)):
        cname, xc = detected[i]
        x_min = (detected[i-1][1] + xc) / 2 if i > 0 else xc - 18
        x_max = (xc + detected[i+1][1]) / 2 if i < len(detected) - 1 else xc + 18
        bounds.append((cname, x_min, x_max))
    return bounds


def detect_columns_right(po: pymupdf.Page) -> List[Tuple[str, float, float]]:
    """Detect dynamic column boundaries for right page (micronutrients & energy)."""
    words = po.get_text('words')
    hw = [w for w in words if 35 <= w[1] <= 65]

    col_defs = [
        ('na', lambda t: t in ['na']),
        ('k', lambda t: t in ['к', 'k']),
        ('ca', lambda t: t in ['са', 'ca']),
        ('mg', lambda t: t in ['мд', 'mg', 'гмд']),
        ('p', lambda t: t in ['р', 'p']),
        ('fe', lambda t: t in ['fe', 'жел']),
        ('vit_a', lambda t: t in ['а', 'a']),
        ('carotene', lambda t: t in ['кар', 'car']),
        ('re', lambda t: t in ['рэ', 're']),
        ('te', lambda t: t in ['тэ', 'te']),
        ('b1', lambda t: t in ['bi', 'b1', 'в1', 'вi']),
        ('b2', lambda t: t in ['в2', 'b2', 'гвг']),
        ('pp', lambda t: t in ['рр', 'pp']),
        ('ne', lambda t: t in ['нэ', 'ne']),
        ('c', lambda t: t in ['с', 'c']),
        ('alcohol', lambda t: 'алк' in t),
        ('kcal', lambda t: t in ['эц', 'ккал']),
        ('code', lambda t: t in ['код']),
    ]

    detected = []
    for cname, matcher in col_defs:
        matching = [w for w in hw if matcher(w[4].lower())]
        if matching:
            xc = sum((w[0]+w[2])/2 for w in matching) / len(matching)
            detected.append((cname, xc))

    # Fallback default positions
    if len(detected) < 8:
        return [
            ('na', 20, 55),
            ('k', 55, 95),
            ('ca', 95, 130),
            ('mg', 130, 165),
            ('p', 165, 195),
            ('fe', 195, 225),
            ('vit_a', 225, 250),
            ('carotene', 250, 275),
            ('re', 275, 300),
            ('te', 300, 325),
            ('b1', 325, 355),
            ('b2', 355, 385),
            ('pp', 385, 410),
            ('ne', 410, 435),
            ('c', 435, 455),
            ('kcal', 455, 480),
            ('code', 480, 550),
        ]

    # Ensure code is at far right if not detected
    has_code = any(d[0] == 'code' for d in detected)
    if not has_code:
        detected.append(('code', 500.0))

    detected.sort(key=lambda x: x[1])
    bounds = []
    for i in range(len(detected)):
        cname, xc = detected[i]
        x_min = (detected[i-1][1] + xc) / 2 if i > 0 else xc - 16
        x_max = (xc + detected[i+1][1]) / 2 if i < len(detected) - 1 else xc + 16
        bounds.append((cname, x_min, x_max))
    return bounds


def determine_food_group(code: str, page_num: int) -> Tuple[int, str]:
    """Map code or book page number to Food Group."""
    m = re.match(r'^(\d+)', code) if code else None
    grp_id = int(m.group(1)) if m else 1

    if grp_id > 12 or grp_id < 1:
        if page_num < 50: grp_id = 1
        elif page_num < 52: grp_id = 2
        elif page_num < 80: grp_id = 3
        elif page_num < 102: grp_id = 4
        elif page_num < 110: grp_id = 5
        elif page_num < 126: grp_id = 6
        elif page_num < 128: grp_id = 7
        elif page_num < 150: grp_id = 8
        elif page_num < 162: grp_id = 9
        elif page_num < 174: grp_id = 10
        elif page_num < 190: grp_id = 11
        else: grp_id = 12

    grp_dict = next((g for g in FOOD_GROUPS if g["id"] == grp_id), FOOD_GROUPS[0])
    return grp_dict["id"], grp_dict["name"]


def extract_all_products(doc: Optional[pymupdf.Document] = None) -> List[Dict[str, Any]]:
    """Run full extraction pipeline across all pages 24-193 and appendices."""
    if doc is None:
        doc = pymupdf.open(str(DEFAULT_PDF_PATH))

    # 1. Parse Subject Index for official product codes and names
    subject_index_items = parse_subject_index(doc)
    index_by_code: Dict[str, Dict] = {item["code"]: item for item in subject_index_items}

    # Build page lookup for fallback
    index_by_page: Dict[int, List[Dict]] = {}
    for item in subject_index_items:
        index_by_page.setdefault(item["page_index"], []).append(item)

    # 2. Parse Appendices
    waste_map = parse_appendix_1(doc)
    measures_map = parse_appendix_2(doc)
    pieces_map = parse_appendix_3(doc)

    extracted_products: List[Dict[str, Any]] = []
    seen_codes = set()

    # 3. Iterate over table spreads (pages 24 to 192, step 2)
    for pno in range(24, 194, 2):
        pe = doc[pno]
        po = doc[pno+1]
        we = pe.get_text('words')
        wo = po.get_text('words')

        bounds_l = detect_columns_left(pe)
        bounds_r = detect_columns_right(po)

        # Find 100g portion anchors on left page (y > 65 captures first rows at y=71..82)
        rows_100 = [w for w in we if w[1] > 65 and 160 <= w[0] <= 265 and w[4].strip() == '100']

        for h in rows_100:
            yc = (h[1] + h[3]) / 2

            # Filter out %с.п. rows (daily value requirement)
            same_y_tokens = [w[4] for w in we if abs((w[1]+w[3])/2 - yc) < 4]
            same_y_str = " ".join(same_y_tokens).lower()
            if re.search(r'%\s*с[\.,]п|с[\.,]п', same_y_str) or any(t.startswith('%') for t in same_y_tokens):
                continue

            # 1. Extract product code: find code candidates and sort by proximity to row yc
            codes_l = [w for w in we if abs((w[1]+w[3])/2 - yc) < 20 and w[0] < 95]
            codes_r = [w for w in wo if abs((w[1]+w[3])/2 - yc) < 20 and w[0] > 465]
            cand_words = codes_l + codes_r
            cand_words.sort(key=lambda w: abs((w[1]+w[3])/2 - yc))

            code = ""
            for w in cand_words:
                norm_w = re.sub(r'[,;:]', '.', w[4])
                m = re.search(r'\d+(?:\.\d+)+', norm_w)
                if m:
                    cand_code = m.group(0)
                    if cand_code.startswith('35.2.'):
                        cand_code = '3.5.2.' + cand_code[5:]
                    elif cand_code.startswith('111.1.'):
                        cand_code = '11.1.' + cand_code[6:]
                    # Check if missing dot e.g. 1.1.15 -> 1.1.1.5
                    parts = cand_code.split('.')
                    if len(parts) >= 2 and len(parts[-1]) >= 2:
                        alt_code = '.'.join(parts[:-1]) + '.' + parts[-1][0] + '.' + parts[-1][1:]
                        if alt_code in index_by_code:
                            cand_code = alt_code
                    code = cand_code
                    break

            # 2. Extract product name words from table column
            name_words = [w[4] for w in we if abs((w[1]+w[3])/2 - yc) < 16 and 85 <= w[0] <= 185]
            table_name = " ".join(name_words).strip()

            # 3. Extract nutrient values
            # The macro (left) and micronutrient (right) tables of a spread have
            # independent row grids, so their baselines drift by several points.
            # Anchor the right row on the product code printed in the right
            # page's "Код" column instead of reusing the left row's y.
            yc_r = yc
            anchor = None
            right_codes = [
                w for w in wo
                if w[0] > 455 and re.search(r'\d+(?:[.,:;]\d+)+', w[4])
            ]
            if right_codes:
                if code:
                    norm_code = re.sub(r'[,:;]', '.', code)
                    for w in right_codes:
                        if re.sub(r'[,:;]', '.', w[4]) == norm_code:
                            anchor = w
                            break
                if anchor is None:
                    candidate = min(right_codes,
                                    key=lambda w: abs((w[1]+w[3])/2 - yc))
                    if abs((candidate[1]+candidate[3])/2 - yc) <= 6:
                        anchor = candidate
                if anchor is not None:
                    yc_r = (anchor[1]+anchor[3])/2

            row_we = [w for w in we if abs((w[1]+w[3])/2 - yc) < 7]
            row_wo = [w for w in wo if abs((w[1]+w[3])/2 - yc_r) < 7]

            l_vals = {c[0]: parse_cell_tokens([w[4] for w in row_we if c[1] <= (w[0]+w[2])/2 < c[2]]) for c in bounds_l}
            r_words = {c[0]: [w for w in row_wo if c[1] <= (w[0]+w[2])/2 < c[2]] for c in bounds_r}
            r_vals = {k: parse_cell_tokens([w[4] for w in v]) for k, v in r_words.items()}

            # A numeric value can look like a code ("5.1" grams of something) and
            # pull the anchor onto a section header row. Only keep the anchored
            # row when it really carries the energy value.
            if yc_r != yc and r_vals.get('kcal', 0.0) <= 0.0:
                alt_wo = [w for w in wo if abs((w[1]+w[3])/2 - yc) < 7]
                alt_vals = {c[0]: parse_cell_tokens([w[4] for w in alt_wo if c[1] <= (w[0]+w[2])/2 < c[2]]) for c in bounds_r}
                if alt_vals.get('kcal', 0.0) > 0.0:
                    r_vals = alt_vals
                    r_words = {c[0]: [w for w in alt_wo if c[1] <= (w[0]+w[2])/2 < c[2]] for c in bounds_r}

            # The right table always ends "... | ЭЦ | Код". When the vitamin C
            # column header is lost in OCR its band is absorbed by its
            # neighbours, so a stray "0" (vitamin C) or a separator "1" can land
            # on a kcal band edge next to the real energy value. Ignore tokens
            # hugging the band edges before reading the cell.
            kcal_band = next((c for c in bounds_r if c[0] == 'kcal'), None)
            if kcal_band is not None and len(r_words.get('kcal', [])) > 1:
                lo, hi = kcal_band[1], kcal_band[2]
                inner = [w for w in r_words['kcal']
                         if lo + 4.0 <= (w[0] + w[2]) / 2 <= hi - 4.0]
                if inner:
                    value = parse_cell_tokens([w[4] for w in inner])
                    if 0.0 < value <= 950.0:
                        r_vals['kcal'] = value

            # Proximates
            water = l_vals.get('water', 0.0)
            prot = l_vals.get('protein', 0.0)
            fat = l_vals.get('fat', 0.0)
            carb = l_vals.get('carbs', 0.0)
            ash = l_vals.get('ash', 0.0)
            oa = l_vals.get('organic_acids', 0.0)
            fiber = l_vals.get('fiber', 0.0)
            alc_val = r_vals.get('alcohol', 0.0)

            # Auto-correct water if obscured by smudge
            sum_other = prot + fat + carb + ash + oa + fiber + alc_val
            if water == 0.0 and sum_other < 90.0:
                w_toks = [w[4] for w in we if abs((w[1]+w[3])/2 - yc) < 11 and 225 <= (w[0]+w[2])/2 < 265]
                cand_water = parse_cell_tokens(w_toks)
                if cand_water > 0.0:
                    water = cand_water
                    l_vals['water'] = water

            # Auto-correct carbs if listed only under sugars/starch
            sugars_val = l_vals.get('sugars', 0.0)
            starch_val = l_vals.get('starch', 0.0)
            if carb == 0.0 and (sugars_val > 0.0 or starch_val > 0.0):
                carb = round(sugars_val + starch_val, 1)
                l_vals['carbs'] = carb

            # Comprehensive physical mass conservation and OCR smudge correction
            # 1) Values >= 200 without decimal point (e.g. 940 -> 94.0, 910 -> 91.0)
            if water >= 200.0:
                water = round(water / 10.0, 1)
            # 2) Protein >= 100 with stray border '1' (e.g. 124.0 -> 24.0)
            if prot >= 100.0:
                if (water + (prot - 100.0) + fat + carb + ash + oa + alc_val) <= 105.0:
                    prot = round(prot - 100.0, 1)
                else:
                    prot = round(prot / 10.0, 1)
            if fat >= 100.0:
                fat = round(fat / 10.0, 1)
            if carb >= 100.0:
                carb = round(carb / 10.0, 1)
            if ash >= 100.0:
                ash = round(ash / 10.0, 1)

            # 3) Integer values where decimal was missed and proximate sum exceeds 108g
            prox_sum_now = water + prot + fat + carb + ash + oa + alc_val
            if prox_sum_now > 108.0:
                for name, val in [('water', water), ('protein', prot), ('fat', fat), ('carbs', carb)]:
                    if val >= 10.0:
                        new_sum = prox_sum_now - val + round(val / 10.0, 1)
                        if 92.0 <= new_sum <= 104.0:
                            if name == 'water': water = round(val / 10.0, 1)
                            elif name == 'protein': prot = round(val / 10.0, 1)
                            elif name == 'fat': fat = round(val / 10.0, 1)
                            elif name == 'carbs': carb = round(val / 10.0, 1)
                            break

            # 4) Abnormally small water on dishes / salads (<20g) where other proximates < 40g
            prox_sum_now = water + prot + fat + carb + ash + oa + alc_val
            if water < 20.0 and prox_sum_now < 40.0:
                est_water = round(100.0 - (prot + fat + carb + ash + oa + alc_val), 1)
                if est_water > 50.0:
                    water = est_water

            # 5) Missing fat in fried dishes with OCR smudge (e.g. fried cod)
            kcal_book = r_vals.get('kcal', 0.0)
            if fat <= 1.0 and kcal_book > 100.0 and (water + prot + carb + ash + oa + alc_val) < 96.0:
                est_fat = round((kcal_book - 4.0 * prot - 4.0 * carb) / 9.0, 1)
                if 2.0 <= est_fat <= 30.0 and 95.0 <= (water + prot + est_fat + carb + ash + oa + alc_val) <= 104.0:
                    fat = est_fat

            # 6) Missing protein & fat in soups with OCR blots (e.g. fish solyanka)
            if (prot + fat) <= 1.0 and kcal_book >= 20.0 and (water + carb + ash) > 94.0:
                rem_mass = 100.0 - (water + carb + ash + oa + alc_val)
                rem_kcal = kcal_book - 4.0 * carb - 3.0 * oa - 7.0 * alc_val
                if rem_mass > 0 and rem_kcal > 0:
                    est_fat = round((rem_kcal - 4.0 * rem_mass) / 5.0, 1)
                    est_prot = round(rem_mass - est_fat, 1)
                    if est_fat >= 0 and est_prot >= 0:
                        fat = est_fat
                        prot = est_prot

            l_vals['water'] = water
            l_vals['protein'] = prot
            l_vals['fat'] = fat
            l_vals['carbs'] = carb
            l_vals['ash'] = ash

            # Fix known single-token OCR errors
            if code == "5.1.5" and prot > 4.0:
                prot = 0.8
                l_vals['protein'] = 0.8

            # Manually verified cells whose OCR text layer lost a digit or a
            # decimal point (see config.KNOWN_PROXIMATE_FIXES).
            for field, value in KNOWN_PROXIMATE_FIXES.get(code, {}).items():
                if field == 'water':
                    water = value
                    l_vals['water'] = value
                elif field == 'protein':
                    prot = value
                    l_vals['protein'] = value
                elif field == 'fat':
                    fat = value
                    l_vals['fat'] = value
                elif field == 'carbs':
                    carb = value
                    l_vals['carbs'] = value
                elif field == 'fiber':
                    fiber = value
                    l_vals['fiber'] = value
                elif field == 'ash':
                    ash = value
                    l_vals['ash'] = value
                elif field == 'organic_acids':
                    oa = value
                    l_vals['organic_acids'] = value

            # Energy (kcal) - include alcohol (7 kcal/g) and organic acids (3 kcal/g)
            kcal_calc = round(4.0 * prot + 9.0 * fat + 4.0 * carb + 7.0 * alc_val + 3.0 * oa, 1)
            # OCR digit error check (e.g. 387 vs 287 on jam where hundreds digit was smudged)
            if kcal_book > 350.0 and abs(kcal_book - 100.0 - kcal_calc) < 25.0:
                kcal_book -= 100.0

            # If book kcal was missed by OCR or drastically mismatched (>40% and >25 kcal), use calculated
            if code == "10.8.1":
                kcal_final = 289.0
            elif kcal_book <= 5.0 and kcal_calc > 15.0:
                kcal_final = kcal_calc
            elif kcal_book > 0.0 and abs(kcal_book - kcal_calc) / kcal_book > 0.4 and abs(kcal_book - kcal_calc) > 25.0:
                kcal_final = kcal_calc
            else:
                kcal_final = kcal_book if kcal_book > 0.0 else kcal_calc

            # Verified energy values whose OCR text layer bound to a neighbour.
            if code in KNOWN_KCAL_FIXES:
                kcal_final = KNOWN_KCAL_FIXES[code]

            # 4. Resolve official name and hierarchy from Subject Index & Canonical overrides
            official_name = ""
            category_name = ""
            if code in KNOWN_CANONICAL_NAMES:
                official_name = KNOWN_CANONICAL_NAMES[code]
            elif code in index_by_code and abs(index_by_code[code].get("page_index", pno) - pno) <= 4:
                official_name = index_by_code[code]["name"]
                category_name = index_by_code[code].get("parent_category", "")
            else:
                cand_page = pno
                candidates = index_by_page.get(cand_page, []) + index_by_page.get(cand_page + 1, [])
                if table_name and len(table_name) > 2:
                    t_words = [w.lower() for w in re.findall(r'[а-яёА-ЯЁa-zA-Z]+', table_name) if len(w) > 2]
                    for cand in candidates:
                        c_name_lower = cand["name"].lower()
                        if any(tw in c_name_lower for tw in t_words):
                            official_name = cand["name"]
                            category_name = cand.get("parent_category", "")
                            if not code:
                                code = cand["code"]
                            break


            final_name = official_name if official_name else table_name
            if not final_name:
                final_name = f"Продукт {code}" if code else f"Продукт стр. {pno}"

            if not code:
                code = f"{pno//2}.{len(extracted_products)+1}"

            if code in seen_codes:
                suffix = 2
                while f"{code}_{suffix}" in seen_codes:
                    suffix += 1
                code = f"{code}_{suffix}"
            seen_codes.add(code)

            # 5. Food Group
            group_id, group_name = determine_food_group(code, pno)

            # 6. Waste Percentage
            waste_pct = find_waste_percentage(final_name, waste_map)
            if waste_pct is None and category_name:
                waste_pct = find_waste_percentage(category_name, waste_map)
            if code in KNOWN_WASTE_OVERRIDES:
                waste_pct = KNOWN_WASTE_OVERRIDES[code]

            # 7. Measures
            measures = get_measures_for_product(final_name, measures_map, pieces_map)

            product_record: Dict[str, Any] = {
                "id": len(extracted_products) + 1,
                "code": code,
                "name": final_name,
                "group_id": group_id,
                "group_name": group_name,
                "source": "skurikhin",
                "page_num": pno,
                "waste_pct": waste_pct,
                "measures": measures,
                # Macronutrients per 100g
                "water": water,
                "protein": prot,
                "fat": fat,
                "carbs": carb,
                "kcal": kcal_final,
                "kcal_calculated": kcal_calc,
                "fiber": fiber,
                "ash": ash,
                "organic_acids": oa,
                "sugars": l_vals.get('sugars', 0.0),
                "starch": l_vals.get('starch', 0.0),
                "sfa": l_vals.get('sfa', 0.0),
                "pufa": l_vals.get('pufa', 0.0),
                "chol": l_vals.get('chol', 0.0),
                "alcohol": r_vals.get('alcohol', 0.0),
                # Micronutrients per 100g
                "minerals": {
                    "na": r_vals.get('na', 0.0),
                    "k": r_vals.get('k', 0.0),
                    "ca": r_vals.get('ca', 0.0),
                    "mg": r_vals.get('mg', 0.0),
                    "p": r_vals.get('p', 0.0),
                    "fe": r_vals.get('fe', 0.0),
                },
                "vitamins": {
                    "vit_a": r_vals.get('vit_a', 0.0),
                    "carotene": r_vals.get('carotene', 0.0),
                    "re": r_vals.get('re', 0.0),
                    "te": r_vals.get('te', 0.0),
                    "b1": r_vals.get('b1', 0.0),
                    "b2": r_vals.get('b2', 0.0),
                    "pp": r_vals.get('pp', 0.0),
                    "ne": r_vals.get('ne', 0.0),
                    "c": r_vals.get('c', 0.0),
                }
            }
            extracted_products.append(product_record)

    return extracted_products


if __name__ == "__main__":
    import sys
    sys.stdout.reconfigure(encoding="utf-8")
    doc = pymupdf.open(str(DEFAULT_PDF_PATH))
    products = extract_all_products(doc)
    print(f"\nExtraction complete! Total products: {len(products)}")
    print("\nSample extracted products:")
    for p in products[::100]:
        print(f"  [{p['code']}] {p['name']} | P:{p['protein']} F:{p['fat']} C:{p['carbs']} Kcal:{p['kcal']} | waste: {p['waste_pct']}% | measures: {len(p['measures'])}")

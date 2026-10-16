import pymupdf
import re
import json
import csv
import os
import sys

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"
DATA_DIR = r"data\skurikhin"
JSON_OUTPUT = os.path.join(DATA_DIR, "products_skurikhin.json")
CSV_OUTPUT = os.path.join(DATA_DIR, "products_skurikhin.csv")

TABLE_METADATA = [
    (1, 25, 50, "Молоко и молочные продукты"),
    (2, 51, 52, "Яйцепродукты"),
    (3, 53, 80, "Мясо и мясные продукты"),
    (4, 81, 102, "Рыба, нерыбные объекты промысла и продукты из них"),
    (5, 103, 110, "Жировые продукты"),
    (6, 111, 126, "Зерно и продукты его переработки"),
    (7, 127, 128, "Бобовые, орехи"),
    (8, 129, 150, "Овощи, грибы и продукты их переработки"),
    (9, 151, 162, "Фрукты, ягоды и продукты их переработки"),
    (10, 163, 174, "Кондитерские изделия"),
    (11, 175, 190, "Напитки"),
    (12, 191, 194, "Вспомогательные вещества и улучшители вкуса"),
]

def clean_num(txt):
    if not txt:
        return None
    txt = txt.strip()
    if txt in ['!', '|', 'I', '[', ']', '/', '\\', '^', '~', '\'', 'i', 'l', ';', ':', 'j', 'J', '°']:
        return None
    if txt in ['-', '—', '–', '0', '0.0', '0,0', '0J', '0,J', 'O', 'о']:
        return 0.0
    txt = txt.replace(',', '.')
    txt = re.sub(r'(\d)J', r'\1.7', txt)
    txt = re.sub(r'^[!|lI:;~^jJ\']+\s*', '', txt)
    txt = re.sub(r'[\'!|lI:;~^jJ°]+$', '', txt)
    m = re.match(r'^([0-9.]+)', txt)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            pass
    return None

def extract_appendix1(doc):
    """Extracts waste percentages (% отходов) from Appendix 1 (pages 202-207)."""
    waste_dict = {}
    for pno in range(201, 207):
        page = doc[pno]
        words = page.get_text("words")
        for col_name_x, col_val_x in [((30, 195), (195, 265)), ((260, 465), (465, 560))]:
            vals = [w for w in words if col_val_x[0] <= w[0] <= col_val_x[1] and re.search(r'\d', w[4]) and w[1] > 100]
            for v in vals:
                y_val = v[1]
                nw = [w for w in words if col_name_x[0] <= w[0] <= col_name_x[1] and abs(w[1] - y_val) < 10]
                nw.sort(key=lambda w: w[0])
                name = " ".join([w[4] for w in nw]).strip().lower()
                m = re.match(r'^([0-9.]+)', v[4].replace(',', '.'))
                if m and name and len(name) > 2 and not name.isupper():
                    waste_dict[name] = float(m.group(1))
    return waste_dict

def detect_page_cols_left(words, t_id):
    headers = {}
    patterns = [
        ("portion", r"^[Пп]орци"),
        ("water", r"^[Вв]ода"),
        ("protein", r"^[Бб]ел"),
        ("fat", r"^[Жж]ир$"),
        ("sfa", r"^[Нн][Жж][Кк]"),
        ("chol_pufa", r"(?:[Хх]ол|[Пп][Нн][Жж][Кк])"),
        ("mds", r"(?:[Мм][Дд][Сс]|Ыдс)"),
        ("starch", r"(?:[Кк]р|Гкр)"),
        ("carbohydrates", r"^[Уу]гл"),
        ("fiber", r"(?:[Пп][Вв]|РПВ)"),
        ("organic_acids", r"(?:[Оо][Кк]|НПВ)"),
        ("ash", r"^[Зз]ола"),
    ]
    for w in words:
        if w[1] > 100: continue
        for key, pat in patterns:
            if key not in headers:
                if key != 'portion' and w[0] < 220:
                    continue
                if re.search(pat, w[4]):
                    headers[key] = (w[0] + w[2]) / 2.0
                
    x_port = headers.get("portion", 215.0 if t_id != 10 else 243.0)
    
    if t_id == 5:
        defaults = {
            "water": x_port + 28,
            "protein": x_port + 55,
            "fat": x_port + 82,
            "sfa": x_port + 115,
            "chol_pufa": x_port + 145,
            "carbohydrates": x_port + 205,
            "ash": x_port + 300,
        }
    elif t_id == 10:
        defaults = {
            "water": 279.0,
            "protein": 306.0,
            "fat": 330.0,
            "sfa": 354.0,
            "chol_pufa": 378.0,
            "mds": 396.0,
            "starch": 426.0,
            "carbohydrates": 446.0,
            "fiber": 478.0,
            "organic_acids": 502.0,
            "ash": 523.0,
        }
    else:
        defaults = {
            "water": x_port + 33,
            "protein": x_port + 60,
            "fat": x_port + 88,
            "sfa": x_port + 117,
            "chol_pufa": x_port + 144,
            "mds": x_port + 168,
            "starch": x_port + 195,
            "carbohydrates": x_port + 222,
            "fiber": x_port + 250,
            "organic_acids": x_port + 273,
            "ash": x_port + 301,
        }
        
    for k, def_x in defaults.items():
        if k not in headers:
            headers[k] = def_x
            
    return headers

def detect_page_cols_right(words, t_id):
    headers = {}
    patterns = [
        ("na", r"^Na$"),
        ("k", r"^К$"),
        ("ca", r"^Са$"),
        ("mg", r"(?:^Мд$|^Mg$)"),
        ("p", r"^Р$"),
        ("fe", r"^Fe$"),
        ("vit_a", r"^А$"),
        ("carotene", r"^[Кк]ар"),
        ("re", r"^[Рр]Э$"),
        ("te", r"^[Тт]Э$"),
        ("vit_b1", r"(?:^[ВвB]1$|^Bi$)"),
        ("vit_b2", r"(?:^[ВвB]2$)"),
        ("vit_pp", r"^[РрP][РрP]$"),
        ("ne", r"^[НнN][ЭэE]$"),
        ("vit_c", r"(?:^[СcC]$|Гс)"),
        ("alk", r"^[Аа]лк$"),
        ("kcal", r"(?:[Ээ][Цц]|[Кк]кал)"),
        ("code", r"^[Кк]од$"),
    ]
    for w in words:
        if w[1] > 100: continue
        for key, pat in patterns:
            if key not in headers and re.search(pat, w[4]):
                headers[key] = (w[0] + w[2]) / 2.0
                
    x_code = headers.get("code", 480.0 if t_id != 10 else 468.0)
    x_kcal = headers.get("kcal", x_code - 30 if t_id != 10 else 427.0)
    defaults = {
        "na": 42.0,
        "k": 72.0,
        "ca": 105.0,
        "mg": 133.0,
        "p": 160.0,
        "fe": 186.0,
        "vit_a": 213.0,
        "carotene": 240.0,
        "re": 268.0,
        "te": 293.0,
        "vit_b1": 316.0,
        "vit_b2": 344.0,
        "vit_pp": 372.0,
        "ne": 402.0,
        "vit_c": x_kcal - 23,
        "kcal": x_kcal,
        "code": x_code,
    }
    if t_id == 11:
        defaults["alk"] = x_kcal - 20
        defaults["vit_c"] = x_kcal - 40
        
    for k, def_x in defaults.items():
        if k not in headers:
            headers[k] = def_x
            
    return headers

def parse_row(wl, wr, cols_l, cols_r, y_curr, y_curr_r, t_id):
    # Left page: explicitly filter grid border lines ('1', '|', '!')
    row_words_l = [w for w in wl if abs(w[1] - y_curr) < 5 and w[0] > 220 and w[4] not in ['1', '|', '!', 'I', 'l']]
    row_words_l.sort(key=lambda w: w[0])
    
    # Merge faint-comma digits
    merged_l = []
    idx = 0
    while idx < len(row_words_l):
        w = row_words_l[idx]
        if idx + 1 < len(row_words_l):
            w_next = row_words_l[idx + 1]
            gap = w_next[0] - w[2]
            if 0 <= gap <= 6.0 and w[4].isdigit() and len(w[4]) == 1 and w_next[4].isdigit() and len(w_next[4]) == 1:
                merged_text = f"{w[4]}.{w_next[4]}"
                merged_w = (w[0], w[1], w_next[2], w_next[3], merged_text)
                merged_l.append(merged_w)
                idx += 2
                continue
        merged_l.append(w)
        idx += 1
        
    vl = {}
    for w in merged_l:
        num = clean_num(w[4])
        if num is None:
            continue
        best_col, best_dist = None, 999.0
        for col_name, col_x in cols_l.items():
            if col_name in ['portion', 'code']: continue
            dist = abs(w[0] - col_x)
            if dist < best_dist:
                best_dist = dist
                best_col = col_name
        if best_dist <= 16:
            if best_col not in vl or best_dist < vl[best_col][1]:
                vl[best_col] = (num, best_dist)
                
    # Right page: use y_curr_r from matching code on right page if available
    row_words_r = [w for w in wr if abs(w[1] - y_curr_r) < 5]
    row_words_r.sort(key=lambda w: w[0])
    
    merged_r = []
    idx = 0
    while idx < len(row_words_r):
        w = row_words_r[idx]
        if idx + 1 < len(row_words_r):
            w_next = row_words_r[idx + 1]
            gap = w_next[0] - w[2]
            if 0 <= gap <= 6.0 and w[4].isdigit() and len(w[4]) == 1 and w_next[4].isdigit() and len(w_next[4]) == 1:
                merged_text = f"{w[4]}.{w_next[4]}"
                merged_w = (w[0], w[1], w_next[2], w_next[3], merged_text)
                merged_r.append(merged_w)
                idx += 2
                continue
        merged_r.append(w)
        idx += 1
        
    vr = {}
    code_words = [w for w in merged_r if w[0] > (455 if t_id == 10 else 465) and re.search(r'\d', w[4])]
    x_code_row = code_words[0][0] if code_words else (468.0 if t_id == 10 else 480.0)
    
    min_x_kcal = 415 if t_id == 10 else 435
    kcal_cands = [w for w in merged_r if min_x_kcal <= w[0] < x_code_row and clean_num(w[4]) is not None and w[4] not in ['1', '|', '!']]
    if kcal_cands:
        vr["kcal"] = clean_num(kcal_cands[-1][4])
        
    for w in merged_r:
        num = clean_num(w[4])
        if num is None:
            continue
        if kcal_cands and w == kcal_cands[-1]:
            continue
        best_col, best_dist = None, 999.0
        for col_name, col_x in cols_r.items():
            if col_name in ['portion', 'code', 'kcal']: continue
            dist = abs(w[0] - col_x)
            if dist < best_dist:
                best_dist = dist
                best_col = col_name
        if best_dist <= 16:
            if best_col not in vr or (isinstance(vr[best_col], tuple) and best_dist < vr[best_col][1]):
                vr[best_col] = (num, best_dist)
                
    res_l = {k: v[0] for k, v in vl.items()}
    res_r = {k: (v[0] if isinstance(v, tuple) else v) for k, v in vr.items()}
    return res_l, res_r

def match_waste(name, waste_dict):
    name_low = name.lower()
    if name_low in waste_dict:
        return waste_dict[name_low]
    for k, v in waste_dict.items():
        if k in name_low:
            return v
    first_word = name_low.split()[0] if name_low.split() else ""
    if len(first_word) > 3 and first_word in waste_dict:
        return waste_dict[first_word]
    return None

def main():
    print("=== Starting Skurikhin Data Extraction Pipeline ===")
    os.makedirs(DATA_DIR, exist_ok=True)
    
    doc = pymupdf.open(PDF_PATH)
    total_pages = len(doc)
    print(f"Loaded PDF: {PDF_PATH} ({total_pages} pages)")
    
    # 1. Extract Appendix 1
    waste_dict = extract_appendix1(doc)
    print(f"Extracted {len(waste_dict)} waste percentage entries from Appendix 1")
    
    all_products = []
    pages_processed = 0
    
    for t_id, start_p, end_p, group_name in TABLE_METADATA:
        table_products = []
        for left_pno in range(start_p, end_p + 1, 2):
            right_pno = left_pno + 1
            pages_processed += 2
            pl = doc[left_pno - 1]
            pr = doc[right_pno - 1]
            
            wl = pl.get_text("words")
            wr = pr.get_text("words")
            
            cols_l = detect_page_cols_left(wl, t_id)
            cols_r = detect_page_cols_right(wr, t_id)
            
            x_portion = cols_l.get("portion", 215.0 if t_id != 10 else 243.0)
            
            # Find 100 portion rows, strictly excluding %с.п. / %с,п rows
            candidates = [w for w in wl if abs(w[0] - x_portion) < 25 and w[4] == '100' and w[1] > 80]
            p100 = []
            for cw in candidates:
                is_sp = any(('с.п' in w[4] or 'с,п' in w[4] or '%с' in w[4]) for w in wl if abs(w[1] - cw[1]) < 4)
                if not is_sp:
                    p100.append(cw)
            p100.sort(key=lambda w: w[1])
            
            for i, p_word in enumerate(p100):
                y_curr = p_word[1]
                y_next = p100[i+1][1] if i + 1 < len(p100) else pl.rect.height - 25
                
                # Product code
                code_cands = [w for w in wl if w[0] < 85 and abs(w[1] - y_curr) < 16 and re.search(r'\d', w[4])]
                code_cands.sort(key=lambda w: (abs(w[1] - y_curr) > 8, -w[4].count('.'), abs(w[1] - y_curr)))
                code = ""
                for c in code_cands:
                    if re.match(r'^\d+(\.\d+)+$', c[4]):
                        code = c[4]
                        break
                if not code and code_cands:
                    code = code_cands[0][4]
                    
                y_curr_r = y_curr
                code_r_cands = [w for w in wr if w[0] > (455 if t_id == 10 else 460) and abs(w[1] - y_curr) < 16 and re.search(r'\d', w[4])]
                code_r_cands.sort(key=lambda w: (abs(w[1] - y_curr) > 8, -w[4].count('.'), abs(w[1] - y_curr)))
                for c in code_r_cands:
                    if re.match(r'^\d+(\.\d+)+$', c[4]):
                        if not code or len(c[4]) > len(code):
                            code = c[4]
                        y_curr_r = c[1]
                        break
                        
                # Product name
                max_x_name = x_portion - 16
                name_words = [w for w in wl if 75 <= w[0] < max_x_name and (y_curr - 4) <= w[1] < (y_next - 4)]
                filtered_nw = []
                for w in name_words:
                    if re.match(r'^\d+$', w[4]) or '%с.п' in w[4] or 'с.п' in w[4] or 'с,п' in w[4]:
                        continue
                    filtered_nw.append(w)
                filtered_nw.sort(key=lambda w: (round(w[1] / 5) * 5, w[0]))
                raw_name = " ".join([w[4] for w in filtered_nw]).strip()
                clean_name = re.sub(r'^(?:[0-9.]+\s*)+', '', raw_name)
                clean_name = re.sub(r'[\s|!:]+$', '', clean_name).strip()
                if not clean_name:
                    clean_name = f"Продукт {code}"
                    
                # Parse nutrients
                vl, vr = parse_row(wl, wr, cols_l, cols_r, y_curr, y_curr_r, t_id)
                
                # Conservation of mass auto-correction
                w_val = vl.get("water") or 0.0
                for k in ["protein", "fat", "carbohydrates"]:
                    v = vl.get(k)
                    if v and v > 10.0 and (w_val + v) > 100.0:
                        vl[k] = round(v / 10.0, 2)
                        
                # Food chemistry identity: Carbs >= MDS + Starch
                mds_val = vl.get("mds") or 0.0
                starch_val = vl.get("starch") or 0.0
                if mds_val > 0 or starch_val > 0:
                    current_carbs = vl.get("carbohydrates") or 0.0
                    sum_sugars = round(mds_val + starch_val, 2)
                    if current_carbs < mds_val:
                        vl["carbohydrates"] = sum_sugars
                        
                # Waste percentage
                waste_p = match_waste(clean_name, waste_dict)
                
                # Assemble structured product
                prot = vl.get("protein") or 0.0
                fat = vl.get("fat") or 0.0
                carb = vl.get("carbohydrates") or 0.0
                oa = vl.get("organic_acids") or 0.0
                alk = vr.get("alk") or 0.0
                kcal = vr.get("kcal")
                
                # Validation check
                is_valid = True
                reason = "Valid"
                if not (0 <= prot <= 100 and 0 <= fat <= 100 and 0 <= carb <= 100):
                    is_valid = False
                    reason = f"B={prot}, J={fat}, U={carb} out of range 0..100"
                elif kcal is None:
                    is_valid = False
                    reason = "Missing energy kcal"
                else:
                    kcal_calc = 4.0 * prot + 9.0 * fat + 4.0 * carb + 3.0 * oa + 7.0 * alk
                    diff = abs(kcal_calc - kcal)
                    tol = max(12.0, 0.20 * kcal)
                    if diff > tol:
                        is_valid = False
                        reason = f"kcal diff: actual={kcal}, calc={kcal_calc:.1f}, diff={diff:.1f}"
                        
                product_record = {
                    "id": code or f"{t_id}.{len(table_products)+1}",
                    "code": code,
                    "name": clean_name,
                    "group": group_name,
                    "table_id": t_id,
                    "page_spread": [left_pno, right_pno],
                    "macronutrients": {
                        "protein_g": prot,
                        "fat_g": fat,
                        "carbohydrates_g": carb,
                        "energy_kcal": kcal,
                        "water_g": vl.get("water"),
                        "fiber_g": vl.get("fiber"),
                        "organic_acids_g": vl.get("organic_acids"),
                        "ash_g": vl.get("ash"),
                        "sfa_g": vl.get("sfa"),
                        "cholesterol_mg": vl.get("chol_pufa") if t_id != 5 else None,
                        "pufa_g": vl.get("chol_pufa") if t_id == 5 else None,
                        "mono_di_saccharides_g": vl.get("mds"),
                        "starch_g": vl.get("starch"),
                        "alcohol_g": alk if t_id == 11 else None,
                    },
                    "minerals_mg": {
                        "na_mg": vr.get("na"),
                        "k_mg": vr.get("k"),
                        "ca_mg": vr.get("ca"),
                        "mg_mg": vr.get("mg"),
                        "p_mg": vr.get("p"),
                        "fe_mg": vr.get("fe"),
                    },
                    "vitamins": {
                        "vit_a_mcg": vr.get("vit_a"),
                        "carotene_mcg": vr.get("carotene"),
                        "re_mcg": vr.get("re"),
                        "te_mg": vr.get("te"),
                        "vit_b1_mg": vr.get("vit_b1"),
                        "vit_b2_mg": vr.get("vit_b2"),
                        "vit_pp_mg": vr.get("vit_pp"),
                        "ne_mg": vr.get("ne"),
                        "vit_c_mg": vr.get("vit_c"),
                    },
                    "waste_percent": waste_p,
                    "validation": {
                        "is_valid": is_valid,
                        "reason": reason,
                        "kcal_calculated": round(4.0 * prot + 9.0 * fat + 4.0 * carb + 3.0 * oa + 7.0 * alk, 1),
                    }
                }
                table_products.append(product_record)
                
        all_products.extend(table_products)
        print(f"Table {t_id:2d}: {group_name:<50} -> {len(table_products)} products")
        
    print(f"\nTotal spreads processed: {pages_processed // 2} (pages 25 to 194)")
    print(f"Total products extracted: {len(all_products)}")
    
    valid_count = sum(1 for p in all_products if p["validation"]["is_valid"])
    val_rate = valid_count / len(all_products) * 100 if all_products else 0
    print(f"Validation rate: {valid_count} / {len(all_products)} ({val_rate:.1f}%)")
    
    # Save to JSON
    with open(JSON_OUTPUT, "w", encoding="utf-8") as f:
        json.dump(all_products, f, ensure_ascii=False, indent=2)
    print(f"Saved JSON: {JSON_OUTPUT} ({os.path.getsize(JSON_OUTPUT) / 1024:.1f} KB)")
    
    # Save to CSV
    csv_fields = [
        "id", "code", "name", "group", "protein_g", "fat_g", "carbohydrates_g",
        "energy_kcal", "waste_percent", "water_g", "fiber_g", "organic_acids_g",
        "ash_g", "sfa_g", "cholesterol_mg", "mono_di_saccharides_g", "starch_g",
        "alcohol_g", "na_mg", "k_mg", "ca_mg", "mg_mg", "p_mg", "fe_mg",
        "vit_a_mcg", "carotene_mcg", "vit_b1_mg", "vit_b2_mg", "vit_pp_mg",
        "vit_c_mg", "is_valid", "validation_reason"
    ]
    with open(CSV_OUTPUT, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=csv_fields)
        writer.writeheader()
        for p in all_products:
            m = p["macronutrients"]
            mins = p["minerals_mg"]
            vits = p["vitamins"]
            val = p["validation"]
            writer.writerow({
                "id": p["id"],
                "code": p["code"],
                "name": p["name"],
                "group": p["group"],
                "protein_g": m["protein_g"],
                "fat_g": m["fat_g"],
                "carbohydrates_g": m["carbohydrates_g"],
                "energy_kcal": m["energy_kcal"],
                "waste_percent": p["waste_percent"],
                "water_g": m["water_g"],
                "fiber_g": m["fiber_g"],
                "organic_acids_g": m["organic_acids_g"],
                "ash_g": m["ash_g"],
                "sfa_g": m["sfa_g"],
                "cholesterol_mg": m["cholesterol_mg"],
                "mono_di_saccharides_g": m["mono_di_saccharides_g"],
                "starch_g": m["starch_g"],
                "alcohol_g": m["alcohol_g"],
                "na_mg": mins["na_mg"],
                "k_mg": mins["k_mg"],
                "ca_mg": mins["ca_mg"],
                "mg_mg": mins["mg_mg"],
                "p_mg": mins["p_mg"],
                "fe_mg": mins["fe_mg"],
                "vit_a_mcg": vits["vit_a_mcg"],
                "carotene_mcg": vits["carotene_mcg"],
                "vit_b1_mg": vits["vit_b1_mg"],
                "vit_b2_mg": vits["vit_b2_mg"],
                "vit_pp_mg": vits["vit_pp_mg"],
                "vit_c_mg": vits["vit_c_mg"],
                "is_valid": val["is_valid"],
                "validation_reason": val["reason"]
            })
    print(f"Saved CSV: {CSV_OUTPUT} ({os.path.getsize(CSV_OUTPUT) / 1024:.1f} KB)")

if __name__ == "__main__":
    main()

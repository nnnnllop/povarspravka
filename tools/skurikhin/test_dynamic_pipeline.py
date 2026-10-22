import pymupdf
import re

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

TABLE_METADATA = [
    (1, 25, 50, "Молоко и молочные продукты"),
    (2, 51, 52, "Яйцепродукты"),
    (3, 53, 80, "Мясо и мясные продукты"),
    (4, 81, 102, "Рыба и продукты из нее"),
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
    if txt in ['!', '|', 'I', '[', ']', '/', '\\', '^', '~', '\'', 'i', 'l', ';', ':']:
        return None
    if txt in ['-', '—', '–', '0', '0.0', '0,0', '0J', '0,J', 'O', 'о']:
        return 0.0
    txt = txt.replace(',', '.')
    txt = re.sub(r'(\d)J', r'\1.7', txt)
    txt = re.sub(r'^[!|lI:;~^]+\s*', '', txt)
    txt = re.sub(r'[\'!|lI:;~^]+$', '', txt)
    m = re.match(r'^([0-9.]+)', txt)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            pass
    return None

def detect_page_cols_left(words):
    # Detect header anchors
    headers = {}
    patterns = [
        ("portion", r"^[Пп]орци"),
        ("water", r"^[Вв]ода"),
        ("protein", r"^[Бб]ел"),
        ("fat", r"^[Жж]ир"),
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
            if key not in headers and re.search(pat, w[4]):
                headers[key] = (w[0] + w[2]) / 2.0
                
    # Fallback missing anchors relative to water or portion
    x_port = headers.get("portion", 215.0)
    defaults = {
        "water": x_port + 35,
        "protein": x_port + 63,
        "fat": x_port + 90,
        "sfa": x_port + 118,
        "chol_pufa": x_port + 144,
        "mds": x_port + 170,
        "starch": x_port + 195,
        "carbohydrates": x_port + 222,
        "fiber": x_port + 250,
        "organic_acids": x_port + 275,
        "ash": x_port + 303,
    }
    for k, def_x in defaults.items():
        if k not in headers:
            headers[k] = def_x
            
    return headers

def detect_page_cols_right(words):
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
                
    # Fallback missing anchors
    x_kcal = headers.get("kcal", 452.0)
    defaults = {
        "na": 45.0,
        "k": 75.0,
        "ca": 108.0,
        "mg": 136.0,
        "p": 162.0,
        "fe": 188.0,
        "vit_a": 215.0,
        "carotene": 242.0,
        "re": 270.0,
        "te": 295.0,
        "vit_b1": 320.0,
        "vit_b2": 348.0,
        "vit_pp": 374.0,
        "ne": 405.0,
        "vit_c": x_kcal - 25,
        "kcal": x_kcal,
        "code": x_kcal + 30,
    }
    for k, def_x in defaults.items():
        if k not in headers:
            headers[k] = def_x
            
    return headers

def assign_row_to_nearest_cols(words, cols_dict, y, y_tol=5, max_dist=17):
    row_words = [w for w in words if abs(w[1] - y) < y_tol]
    vals = {}
    for w in row_words:
        num = clean_num(w[4])
        if num is None:
            continue
        best_col, best_dist = None, 999.0
        for col_name, col_x in cols_dict.items():
            if col_name in ['portion', 'code']:
                continue
            dist = abs(w[0] - col_x)
            if dist < best_dist:
                best_dist = dist
                best_col = col_name
        if best_dist <= max_dist:
            if best_col not in vals:
                vals[best_col] = (num, best_dist, w[4])
            else:
                if best_dist < vals[best_col][1]:
                    vals[best_col] = (num, best_dist, w[4])
    return {k: v[0] for k, v in vals.items()}

def run_dynamic_pipeline():
    doc = pymupdf.open(PDF_PATH)
    all_products = []
    
    for t_id, start_p, end_p, group_name in TABLE_METADATA:
        table_products = []
        for left_pno in range(start_p, end_p + 1, 2):
            right_pno = left_pno + 1
            pl = doc[left_pno - 1]
            pr = doc[right_pno - 1]
            
            wl = pl.get_text("words")
            wr = pr.get_text("words")
            
            cols_l = detect_page_cols_left(wl)
            cols_r = detect_page_cols_right(wr)
            
            x_portion = cols_l.get("portion", 215.0)
            
            # Find all 100 portion rows
            p100 = [w for w in wl if abs(w[0] - x_portion) < 25 and w[4] == '100' and w[1] > 80]
            p100.sort(key=lambda w: w[1])
            
            for i, p_word in enumerate(p100):
                y_curr = p_word[1]
                y_next = p100[i+1][1] if i + 1 < len(p100) else pl.rect.height - 25
                
                # Code
                code_cands = [w for w in wl if w[0] < 85 and abs(w[1] - y_curr) < 16 and re.search(r'\d', w[4])]
                code = ""
                for c in code_cands:
                    if re.match(r'^\d+(\.\d+)+$', c[4]):
                        code = c[4]
                        break
                if not code and code_cands:
                    code = code_cands[0][4]
                    
                code_r_cands = [w for w in wr if w[0] > 460 and abs(w[1] - y_curr) < 16 and re.search(r'\d', w[4])]
                for c in code_r_cands:
                    if re.match(r'^\d+(\.\d+)+$', c[4]):
                        if not code or len(c[4]) > len(code):
                            code = c[4]
                        break
                        
                # Name
                name_words = [w for w in wl if 75 <= w[0] < x_portion - 8 and (y_curr - 4) <= w[1] < (y_next - 4)]
                name_words.sort(key=lambda w: (round(w[1] / 5) * 5, w[0]))
                raw_name = " ".join([w[4] for w in name_words]).strip()
                clean_name = re.sub(r'^(?:[0-9.]+\s*)+', '', raw_name)
                clean_name = re.sub(r'[\s|!]+$', '', clean_name).strip()
                if not clean_name:
                    clean_name = f"Продукт {code}"
                    
                # Assign values
                vl = assign_row_to_nearest_cols(wl, cols_l, y_curr)
                vr = assign_row_to_nearest_cols(wr, cols_r, y_curr)
                
                row = {
                    "table_id": t_id,
                    "group": group_name,
                    "code": code,
                    "name": clean_name,
                    "portion": 100,
                }
                row.update(vl)
                row.update(vr)
                
                table_products.append(row)
                
        all_products.extend(table_products)
        print(f"Table {t_id} ({group_name}): extracted {len(table_products)} products")
        
    print(f"\nTOTAL PRODUCTS EXTRACTED: {len(all_products)}")
    
    # Run validation statistics
    valid_count = 0
    invalid_examples = []
    
    for p in all_products:
        prot = p.get("protein") or 0.0
        fat = p.get("fat") or 0.0
        carb = p.get("carbohydrates") or 0.0
        oa = p.get("organic_acids") or 0.0
        alk = p.get("alk") or p.get("alcohol") or 0.0
        kcal_act = p.get("kcal")
        
        if not (0 <= prot <= 100 and 0 <= fat <= 100 and 0 <= carb <= 100):
            p["valid"] = False
            p["reason"] = f"B={prot}, J={fat}, U={carb} out of range 0..100"
            invalid_examples.append(p)
            continue
            
        if not p.get("name"):
            p["valid"] = False
            p["reason"] = "Empty name"
            invalid_examples.append(p)
            continue
            
        if kcal_act is None:
            p["valid"] = False
            p["reason"] = "Missing kcal"
            invalid_examples.append(p)
            continue
            
        kcal_calc = 4.0 * prot + 9.0 * fat + 4.0 * carb + 3.0 * oa + 7.0 * alk
        diff = abs(kcal_calc - kcal_act)
        tol = max(12.0, 0.20 * kcal_act)
        if diff <= tol:
            p["valid"] = True
            valid_count += 1
        else:
            p["valid"] = False
            p["reason"] = f"kcal mismatch: act={kcal_act}, calc={kcal_calc:.1f}, diff={diff:.1f}"
            invalid_examples.append(p)
            
    print(f"Validation rate: {valid_count} / {len(all_products)} ({valid_count / len(all_products) * 100:.1f}%)")
    print(f"Sample invalid examples ({len(invalid_examples)}):")
    for ie in invalid_examples[:10]:
        print(f"  [{ie['table_id']}] Code {ie['code']}: {ie['name'][:25]} -> {ie['reason']}")

if __name__ == "__main__":
    run_dynamic_pipeline()

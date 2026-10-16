import pymupdf
import re
import json

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

# Standard column X intervals if dynamic detection misses
# Left page (y ~ 100..750)
STD_COLS_L = {
    "water": (225, 260),
    "protein": (260, 288),
    "fat": (288, 318),
    "sfa": (318, 344),
    "chol_pufa": (344, 370),
    "mds": (370, 395),
    "starch": (395, 420),
    "carbohydrates": (420, 455),
    "fiber": (455, 480),
    "oa": (480, 510),
    "ash": (510, 550),
}

# Right page
STD_COLS_R = {
    "na": (25, 65),
    "k": (65, 100),
    "ca": (100, 138),
    "mg": (138, 172),
    "p": (172, 202),
    "fe": (202, 228),
    "vit_a": (228, 255),
    "carotene": (255, 282),
    "re": (282, 308),
    "te": (308, 332),
    "vit_b1": (332, 355),
    "vit_b2": (355, 380),
    "vit_pp": (380, 404),
    "ne": (404, 428),
    "vit_c": (425, 444),
    "kcal": (444, 472),
}

def clean_number(txt):
    if not txt:
        return None
    txt = txt.strip()
    # Filter pure grid line artifacts
    if txt in ['!', '|', 'I', '[', ']', '/', '\\', '^', '~', '\'']:
        return None
    if txt in ['-', '—', '–', '0', '0.0', '0,0', '0J', '0,J', 'O', 'о']:
        return 0.0
    txt = txt.replace(',', '.')
    txt = re.sub(r'(\d)J', r'\1.7', txt)
    txt = re.sub(r'^[!|lI]\s*', '', txt)
    # Remove range like 53.6(49.5-57.8) -> 53.6
    m = re.match(r'^([0-9.]+)', txt)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            pass
    return None

def extract_cell_value(words, x0, x1, y, y_tol=5):
    # Find words in box [x0, x1], [y - y_tol, y + y_tol]
    cands = [w for w in words if x0 <= w[0] < x1 and abs(w[1] - y) < y_tol]
    if not cands:
        return None
    cands.sort(key=lambda w: w[0])
    
    # Filter out single character border artifacts if more than one word
    valid_nums = []
    for w in cands:
        n = clean_number(w[4])
        if n is not None:
            # If length is 1 and value is 1, and there is another number in column, ignore 1 (grid border)
            if w[4] in ['1', '|', '!'] and len(cands) > 1:
                continue
            valid_nums.append(n)
            
    if valid_nums:
        return valid_nums[0]
    return clean_number(cands[0][4])

def run_test():
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
            
            # Find portion column header
            pw = [w for w in wl if w[1] < 120 and ("Порция" in w[4] or "порция" in w[4].lower())]
            x_portion = pw[0][0] if pw else 200.0
            
            # Find all '100' portion rows
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
                    
                # Check right page for code
                code_r_cands = [w for w in wr if w[0] > 470 and abs(w[1] - y_curr) < 16 and re.search(r'\d', w[4])]
                for c in code_r_cands:
                    if re.match(r'^\d+(\.\d+)+$', c[4]):
                        if not code or len(c[4]) > len(code):
                            code = c[4]
                        break
                        
                # Name: words between y_curr - 4 and y_next - 4
                name_words = [w for w in wl if 75 <= w[0] < x_portion - 8 and (y_curr - 4) <= w[1] < (y_next - 4)]
                name_words.sort(key=lambda w: (round(w[1] / 5) * 5, w[0]))
                raw_name = " ".join([w[4] for w in name_words]).strip()
                # Remove leading numbers/codes
                clean_name = re.sub(r'^(?:[0-9.]+\s*)+', '', raw_name)
                # Remove trailing border artifacts
                clean_name = re.sub(r'[\s|!]+$', '', clean_name).strip()
                
                if not clean_name:
                    clean_name = f"Продукт {code}"
                    
                # Extract left columns
                row = {
                    "table_id": t_id,
                    "group": group_name,
                    "code": code,
                    "name": clean_name,
                    "portion": 100,
                }
                
                # Check if Table 5 (Fats) where layout shifts slightly
                if t_id == 5:
                    cols_l = {
                        "water": (220, 255),
                        "protein": (255, 280),
                        "fat": (280, 315),
                        "sfa": (315, 345),
                        "pufa": (345, 375),
                        "cholesterol": (375, 405),
                        "carbohydrates": (405, 440),
                        "ash": (500, 540),
                    }
                elif t_id == 10: # Confectionery where portion is around 243
                    cols_l = {
                        "water": (270, 305),
                        "protein": (305, 335),
                        "fat": (335, 365),
                        "sfa": (365, 395),
                        "cholesterol": (395, 420),
                        "mds": (420, 445),
                        "starch": (445, 470),
                        "carbohydrates": (470, 500),
                        "fiber": (500, 525),
                        "ash": (525, 555),
                    }
                else:
                    cols_l = STD_COLS_L
                    
                for col_k, (x0, x1) in cols_l.items():
                    row[col_k] = extract_cell_value(wl, x0, x1, y_curr)
                    
                # Extract right columns
                for col_k, (x0, x1) in STD_COLS_R.items():
                    row[col_k] = extract_cell_value(wr, x0, x1, y_curr)
                    
                # In Table 11, extract alcohol
                if t_id == 11:
                    row["alcohol"] = extract_cell_value(wr, 428, 452, y_curr)
                    # Kcal in Tab 11 is slightly shifted:
                    row["kcal"] = extract_cell_value(wr, 452, 480, y_curr)
                    
                table_products.append(row)
                
        print(f"Table {t_id} ({group_name}): extracted {len(table_products)} products")
        all_products.extend(table_products)
        
    print(f"\nTOTAL PRODUCTS EXTRACTED: {len(all_products)}")
    
    # Run validation statistics
    valid_count = 0
    invalid_examples = []
    
    for p in all_products:
        prot = p.get("protein") or 0.0
        fat = p.get("fat") or 0.0
        carb = p.get("carbohydrates") or 0.0
        oa = p.get("oa") or 0.0
        alk = p.get("alcohol") or 0.0
        kcal_act = p.get("kcal")
        
        # Validation checks:
        # 1. B, J, U in [0..100]
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
        # Allowed tolerance: max(12 kcal, 20% of actual)
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
    run_test()

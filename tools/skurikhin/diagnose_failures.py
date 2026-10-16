import pymupdf
import re
from tools.skurikhin.test_dynamic_pipeline import (
    TABLE_METADATA, detect_page_cols_left, detect_page_cols_right,
    clean_num
)

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def diagnose():
    doc = pymupdf.open(PDF_PATH)
    
    # We want to see the first 30 invalid products
    invalid_cases = []
    
    for t_id, start_p, end_p, group_name in TABLE_METADATA:
        for left_pno in range(start_p, end_p + 1, 2):
            right_pno = left_pno + 1
            pl = doc[left_pno - 1]
            pr = doc[right_pno - 1]
            
            wl = pl.get_text("words")
            wr = pr.get_text("words")
            
            cols_l = detect_page_cols_left(wl)
            cols_r = detect_page_cols_right(wr)
            
            x_portion = cols_l.get("portion", 215.0)
            p100 = [w for w in wl if abs(w[0] - x_portion) < 25 and w[4] == '100' and w[1] > 80]
            p100.sort(key=lambda w: w[1])
            
            for i, p_word in enumerate(p100):
                y_curr = p_word[1]
                
                # Check line words on left and right
                row_l = [w for w in wl if abs(w[1] - y_curr) < 5 and w[0] > 70]
                row_l.sort(key=lambda w: w[0])
                row_r = [w for w in wr if abs(w[1] - y_curr) < 5]
                row_r.sort(key=lambda w: w[0])
                
                # Code
                code_cands = [w for w in wl if w[0] < 85 and abs(w[1] - y_curr) < 16 and re.search(r'\d', w[4])]
                code = code_cands[0][4] if code_cands else ""
                
                # Name
                name_words = [w for w in wl if 75 <= w[0] < 185 and abs(w[1] - y_curr) < 20]
                name = " ".join([w[4] for w in name_words])
                name = re.sub(r'^(?:[0-9.]+\s*)+', '', name)
                
                # Kcal candidates on right
                # Kcal is around x in 440..472
                kc_words = [w for w in row_r if 440 <= w[0] <= 472]
                kcal = clean_num(kc_words[0][4]) if kc_words else None
                
                # Let's extract all numbers on left row
                nums_l = [(w[0], w[4]) for w in row_l if w[0] > 230]
                
                # Protein around 270, Fat around 300, Carbs around 435
                p_words = [w for w in row_l if 260 <= w[0] <= 290]
                f_words = [w for w in row_l if 290 <= w[0] <= 325]
                c_words = [w for w in row_l if 420 <= w[0] <= 455]
                
                prot = clean_num(p_words[0][4]) if p_words else 0.0
                fat = clean_num(f_words[0][4]) if f_words else 0.0
                carb = clean_num(c_words[0][4]) if c_words else 0.0
                
                if kcal is not None and prot is not None and fat is not None and carb is not None:
                    calc = 4*prot + 9*fat + 4*carb
                    diff = abs(calc - kcal)
                    if diff > max(12.0, 0.20 * kcal):
                        invalid_cases.append({
                            "table": t_id,
                            "page": left_pno,
                            "code": code,
                            "name": name,
                            "y": y_curr,
                            "prot": (p_words, prot),
                            "fat": (f_words, fat),
                            "carb": (c_words, carb),
                            "kcal": (kc_words, kcal),
                            "calc": calc,
                            "diff": diff,
                            "all_l": nums_l,
                            "all_r": [(w[0], w[4]) for w in row_r if w[0] > 400]
                        })
                        if len(invalid_cases) >= 20:
                            break
            if len(invalid_cases) >= 20:
                break
        if len(invalid_cases) >= 20:
            break
            
    print(f"Collected {len(invalid_cases)} sample invalid cases:")
    for c in invalid_cases:
        print(f"\n[{c['table']}] p.{c['page']} Code {c['code']} '{c['name'][:30]}':")
        print(f"  Prot words: {c['prot'][0]} -> {c['prot'][1]}")
        print(f"  Fat words:  {c['fat'][0]} -> {c['fat'][1]}")
        print(f"  Carb words: {c['carb'][0]} -> {c['carb'][1]}")
        print(f"  Kcal words: {c['kcal'][0]} -> {c['kcal'][1]}")
        print(f"  Calc: {c['calc']:.1f} vs Act: {c['kcal'][1]} (diff={c['diff']:.1f})")
        print(f"  All left nums: {c['all_l']}")

if __name__ == "__main__":
    diagnose()

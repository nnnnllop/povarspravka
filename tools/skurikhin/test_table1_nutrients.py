import pymupdf
import re

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

COLUMNS_L = [
    ("water", 225, 260),
    ("protein", 260, 288),
    ("fat", 288, 318),
    ("sfa", 318, 344),
    ("cholesterol", 344, 370),
    ("mono_di_saccharides", 370, 395),
    ("starch", 395, 420),
    ("carbohydrates", 420, 455),
    ("fiber", 455, 480),
    ("organic_acids", 480, 510),
    ("ash", 510, 550),
]

COLUMNS_R = [
    ("na", 25, 65),
    ("k", 65, 100),
    ("ca", 100, 138),
    ("mg", 138, 172),
    ("p", 172, 202),
    ("fe", 202, 228),
    ("vit_a", 228, 255),
    ("carotene", 255, 282),
    ("re", 282, 308),
    ("te", 308, 332),
    ("vit_b1", 332, 355),
    ("vit_b2", 355, 380),
    ("vit_pp", 380, 404),
    ("ne", 404, 428),
    ("vit_c", 428, 450),
    ("kcal", 450, 478),
]

def clean_num(txt):
    if not txt:
        return None
    txt = txt.strip()
    if txt in ['-', '—', '–', '0', '0.0', '0,0', '0J', '0,J', 'O']:
        return 0.0
    txt = txt.replace(',', '.')
    # Fix OCR typos like 0J -> 0.7 or 0.1? Wait, 0J in Russian tables often means 0.7 or 0.1
    txt = re.sub(r'(\d)J', r'\1.7', txt)
    txt = re.sub(r'^[!|lI]\s*', '', txt)
    m = re.match(r'^([0-9.]+)', txt)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            pass
    return None

def main():
    doc = pymupdf.open(PDF_PATH)
    pl = doc[24]
    pr = doc[25]
    
    words_l = pl.get_text("words")
    words_r = pr.get_text("words")
    
    p100_list = [w for w in words_l if 185 <= w[0] <= 225 and w[4] == '100']
    p100_list.sort(key=lambda w: w[1])
    
    for w in p100_list:
        y = w[1]
        
        # Name
        nw = [nw for nw in words_l if 80 <= nw[0] < 185 and abs(nw[1] - y) < 25]
        nw.sort(key=lambda x: (round(x[1]/6)*6, x[0]))
        name = " ".join([x[4] for x in nw])
        name = re.sub(r'^(?:[0-9.]+\s*)+', '', name)
        
        # Left columns
        row_data = {}
        for col_name, x0, x1 in COLUMNS_L:
            c_words = [cw for cw in words_l if x0 <= cw[0] < x1 and abs(cw[1] - y) < 6]
            val = clean_num(c_words[0][4]) if c_words else None
            row_data[col_name] = val
            
        # Right columns
        for col_name, x0, x1 in COLUMNS_R:
            c_words = [cw for cw in words_r if x0 <= cw[0] < x1 and abs(cw[1] - y) < 6]
            val = clean_num(c_words[0][4]) if c_words else None
            row_data[col_name] = val
            
        # Check validation
        p = row_data.get("protein") or 0.0
        f = row_data.get("fat") or 0.0
        c = row_data.get("carbohydrates") or 0.0
        oa = row_data.get("organic_acids") or 0.0
        kcal_actual = row_data.get("kcal")
        kcal_calc = 4.0 * p + 9.0 * f + 4.0 * c + 3.0 * oa
        diff = abs(kcal_calc - kcal_actual) if kcal_actual is not None else 999
        status = "OK" if diff < 5 else f"DIFF={diff:.1f}"
        
        print(f"{name[:30]:<30} | Б={p:4.1f} Ж={f:4.2f} У={c:4.1f} | ккал={kcal_actual} (расчет={kcal_calc:.1f}) | {status}")

if __name__ == "__main__":
    main()

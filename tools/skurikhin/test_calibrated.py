import pymupdf
import re

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

# Standard reference positions for Table columns (normalized to typical spread width)
# Left page standard positions:
REF_COLS_L_STD = [
    ("water", 245),
    ("protein", 273),
    ("fat", 302),
    ("sfa", 331),
    ("chol_pufa", 357),
    ("mds", 383),
    ("starch", 408),
    ("carbohydrates", 436),
    ("fiber", 467),
    ("organic_acids", 495),
    ("ash", 522),
]

# Table 5 (Fats) left page positions:
REF_COLS_L_TAB5 = [
    ("water", 238),
    ("protein", 267),
    ("fat", 298),
    ("sfa", 330),
    ("pufa", 360),
    ("cholesterol", 390),
    ("carbohydrates", 423),
    ("ash", 520),
]

# Table 10 (Confectionery) left page positions (wide name column):
REF_COLS_L_TAB10 = [
    ("water", 288),
    ("protein", 320),
    ("fat", 350),
    ("sfa", 380),
    ("cholesterol", 408),
    ("mds", 433),
    ("starch", 458),
    ("carbohydrates", 485),
    ("fiber", 512),
    ("ash", 540),
]

# Right page standard positions (16 columns):
REF_COLS_R_STD = [
    ("na", 45),
    ("k", 80),
    ("ca", 118),
    ("mg", 155),
    ("p", 188),
    ("fe", 215),
    ("vit_a", 240),
    ("carotene", 267),
    ("re", 295),
    ("te", 320),
    ("vit_b1", 344),
    ("vit_b2", 368),
    ("vit_pp", 392),
    ("ne", 416),
    ("vit_c", 438),
    ("kcal", 462),
]

# Table 11 (Beverages) right page has alcohol before kcal:
REF_COLS_R_TAB11 = [
    ("na", 45),
    ("k", 80),
    ("ca", 118),
    ("mg", 155),
    ("p", 188),
    ("fe", 215),
    ("vit_a", 240),
    ("carotene", 267),
    ("re", 295),
    ("te", 320),
    ("vit_b1", 344),
    ("vit_b2", 368),
    ("vit_pp", 392),
    ("ne", 416),
    ("vit_c", 438),
    ("alcohol", 450),
    ("kcal", 466),
]

def clean_num(txt):
    if not txt:
        return None
    txt = txt.strip()
    if txt in ['!', '|', 'I', '[', ']', '/', '\\', '^', '~', '\'', 'i', 'l']:
        return None
    if txt in ['-', '—', '–', '0', '0.0', '0,0', '0J', '0,J', 'O', 'о']:
        return 0.0
    txt = txt.replace(',', '.')
    txt = re.sub(r'(\d)J', r'\1.7', txt)
    txt = re.sub(r'^[!|lI]\s*', '', txt)
    txt = re.sub(r'[\'!|lI]$', '', txt)
    m = re.match(r'^([0-9.]+)', txt)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            pass
    return None

def assign_row_to_cols(words, col_defs, y, y_tol=5, max_dist=16):
    row_words = [w for w in words if abs(w[1] - y) < y_tol]
    vals = {}
    for w in row_words:
        n = clean_num(w[4])
        if n is None:
            continue
        # Find nearest column
        best_col, best_dist = None, 999.0
        for col_name, col_x in col_defs:
            dist = abs(w[0] - col_x)
            if dist < best_dist:
                best_dist = dist
                best_col = col_name
        if best_dist <= max_dist:
            # If not assigned or closer than existing
            if best_col not in vals:
                vals[best_col] = (n, best_dist, w[4])
            else:
                # If existing was border artifact or farther
                if best_dist < vals[best_col][1]:
                    vals[best_col] = (n, best_dist, w[4])
    return {k: v[0] for k, v in vals.items()}

def main():
    doc = pymupdf.open(PDF_PATH)
    # Test on spread 29, 30
    pl = doc[28]
    pr = doc[29]
    wl = pl.get_text("words")
    wr = pr.get_text("words")
    
    # 1.1.4.1 at y=95.8
    vl = assign_row_to_cols(wl, REF_COLS_L_STD, 95.8)
    vr = assign_row_to_cols(wr, REF_COLS_R_STD, 95.5)
    print("Spread 29, 30 Product 1.1.4.1:")
    print("  Left:", vl)
    print("  Right:", vr)
    p = vl.get('protein', 0)
    f = vl.get('fat', 0)
    c = vl.get('carbohydrates', 0)
    oa = vl.get('organic_acids', 0)
    kcal_calc = 4*p + 9*f + 4*c + 3*oa
    print(f"  Calc kcal: {kcal_calc:.1f} vs Act kcal: {vr.get('kcal')}")

if __name__ == "__main__":
    main()

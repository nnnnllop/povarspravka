import pymupdf
import re
import json

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def parse_num(val_str):
    if not val_str:
        return None
    val_str = val_str.strip()
    if val_str in ['-', '—', '–', '0', '0.0', '0,0']:
        return 0.0
    # Clean up commas and OCR glitches like 'о', 'O', 'l', 'I'
    val_str = val_str.replace(',', '.')
    # If range like (49.5-57.8) or 53.6(49.5-57.8), keep main number
    m = re.match(r'^([0-9.]+)', val_str)
    if m:
        try:
            return float(m.group(1))
        except ValueError:
            pass
    return None

def extract_table_spread(doc, left_pno, right_pno, group_name=""):
    pl = doc[left_pno - 1]
    pr = doc[right_pno - 1]
    
    words_l = pl.get_text("words")
    words_r = pr.get_text("words")
    
    # 1. Detect headers on left page
    # Find "Порция"
    portion_words = [w for w in words_l if "Порция" in w[4] or "порция" in w[4].lower()]
    if not portion_words:
        print(f"Spread ({left_pno}, {right_pno}): 'Порция' header not found!")
        return []
    
    # Sort portion words by y
    pw = portion_words[0]
    x_portion = pw[0]
    y_header_bottom = pw[3] + 10 # Data is below header
    
    # Left page column boundaries:
    # Code: x < 85
    # Name: 85 <= x < x_portion - 5
    # Portion: x_portion - 10 <= x < x_portion + 35
    # Water: x_portion + 35 <= x < x_portion + 75
    # Protein: x_portion + 75 <= x < x_portion + 105
    # Fat: x_portion + 105 <= x < x_portion + 135
    # ...
    
    # Find all "100" in portion column
    p100_list = [w for w in words_l if abs(w[0] - x_portion) < 25 and w[4] == '100' and w[1] > y_header_bottom]
    p100_list.sort(key=lambda w: w[1])
    
    products = []
    
    for i, p_word in enumerate(p100_list):
        y_curr = p_word[1]
        y_next = p100_list[i+1][1] if i + 1 < len(p100_list) else pl.rect.height - 20
        y_prev = p100_list[i-1][1] if i > 0 else y_header_bottom
        
        # Product code: check x < 85 in y range [y_curr - 8, y_curr + 8] or [y_prev, y_next]
        code_candidates = [w for w in words_l if w[0] < 85 and abs(w[1] - y_curr) < 15 and re.search(r'\d', w[4])]
        code = ""
        if code_candidates:
            # Pick the one that looks like code
            for c in code_candidates:
                if re.match(r'^\d+(\.\d+)+$', c[4]):
                    code = c[4]
                    break
            if not code:
                code = code_candidates[0][4]
                
        # Also check right page for code (right page code is in rightmost column x > 470)
        code_r_cands = [w for w in words_r if w[0] > 470 and abs(w[1] - y_curr) < 15 and re.search(r'\d', w[4])]
        code_r = ""
        for c in code_r_cands:
            if re.match(r'^\d+(\.\d+)+$', c[4]):
                code_r = c[4]
                break
        if not code and code_r:
            code = code_r
            
        # Product name: words in name column between y_curr - 12 and min(y_next - 5, y_curr + 40)
        # Note: Name can start a bit above y_curr (e.g. y_curr - 10)
        name_words = [w for w in words_l if 80 <= w[0] < x_portion - 10 and (y_curr - 12) <= w[1] < min(y_next - 5, y_curr + 38)]
        name_words.sort(key=lambda w: (round(w[1] / 6) * 6, w[0]))
        name = " ".join([w[4] for w in name_words]).strip()
        
        # Clean up name: remove spurious standalone numbers or table markers
        name = re.sub(r'^(?:[0-9.]+\s*)+', '', name)
        
        # Left page 100g row words (y within y_curr +- 5)
        row_l = [w for w in words_l if abs(w[1] - y_curr) < 6 and w[0] > x_portion + 15]
        row_l.sort(key=lambda w: w[0])
        
        # Right page 100g row words (y within y_curr +- 6)
        row_r = [w for w in words_r if abs(w[1] - y_curr) < 6]
        row_r.sort(key=lambda w: w[0])
        
        # Energy (kcal): on right page around x in [445..478]
        kcal_words = [w for w in row_r if 445 <= w[0] <= 478]
        kcal_val = parse_num(kcal_words[0][4]) if kcal_words else None
        
        products.append({
            "code": code,
            "code_r": code_r,
            "name": name,
            "y": round(y_curr, 1),
            "kcal": kcal_val,
            "row_l_words": [(round(w[0], 1), w[4]) for w in row_l],
            "row_r_words": [(round(w[0], 1), w[4]) for w in row_r],
        })
        
    return products

def main():
    doc = pymupdf.open(PDF_PATH)
    # Test on spread 25, 26
    prods = extract_table_spread(doc, 25, 26, "Молочные продукты")
    print(f"Extracted {len(prods)} products from spread (25, 26):")
    for p in prods:
        print(f"Code: {p['code']:<12} | Name: {p['name'][:35]:<35} | Kcal: {p['kcal']} | Left values: {[w[1] for w in p['row_l_words'][:6]]}")

if __name__ == "__main__":
    main()

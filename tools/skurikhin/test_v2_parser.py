import pymupdf
import re

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

from tools.skurikhin.extract_skurikhin import (
    TABLE_METADATA, detect_page_cols_left, detect_page_cols_right,
    clean_num, match_waste, extract_appendix1
)

def parse_row_v2(wl, wr, cols_l, cols_r, y_curr, t_id):
    # Left page: filter border characters '1', '|', '!'
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
                
    # Right page: tolerance 8.0 points for scan skew!
    # First find right page y_curr_r: if there is a matching code or kcal row within 8 points
    row_words_r = [w for w in wr if abs(w[1] - y_curr) <= 8.5]
    if row_words_r:
        # Cluster y on right page to find modal y
        y_r_vals = [w[1] for w in row_words_r if 430 <= w[0] <= 490]
        y_r_target = y_r_vals[0] if y_r_vals else y_curr
        row_words_r = [w for w in row_words_r if abs(w[1] - y_r_target) < 5]
        
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
    code_words = [w for w in merged_r if w[0] > 465 and re.search(r'\d', w[4])]
    x_code_row = code_words[0][0] if code_words else 480.0
    
    # Candidate kcal numbers: exclude standalone '1', '|', '!'
    kcal_cands = [w for w in merged_r if 435 <= w[0] < x_code_row and clean_num(w[4]) is not None and w[4] not in ['1', '|', '!']]
    if kcal_cands:
        # Pick rightmost valid candidate
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

def test_all():
    doc = pymupdf.open(PDF_PATH)
    total_valid = 0
    total_prods = 0
    
    for t_id, start_p, end_p, group_name in TABLE_METADATA:
        t_valid = 0
        t_total = 0
        for left_pno in range(start_p, end_p + 1, 2):
            right_pno = left_pno + 1
            pl = doc[left_pno - 1]
            pr = doc[right_pno - 1]
            
            wl = pl.get_text("words")
            wr = pr.get_text("words")
            
            cols_l = detect_page_cols_left(wl, t_id)
            cols_r = detect_page_cols_right(wr, t_id)
            
            x_portion = cols_l.get("portion", 215.0 if t_id != 10 else 243.0)
            
            candidates = [w for w in wl if abs(w[0] - x_portion) < 25 and w[4] == '100' and w[1] > 80]
            p100 = []
            for cw in candidates:
                # Exclude %с.п., %с,п, с.п.
                is_sp = any(('с.п' in w[4] or 'с,п' in w[4] or '%с' in w[4]) for w in wl if abs(w[1] - cw[1]) < 4)
                if not is_sp:
                    p100.append(cw)
            p100.sort(key=lambda w: w[1])
            
            for p_word in p100:
                y = p_word[1]
                vl, vr = parse_row_v2(wl, wr, cols_l, cols_r, y, t_id)
                
                # Conservation of mass auto-correction
                w_val = vl.get("water") or 0.0
                for k in ["protein", "fat", "carbohydrates"]:
                    v = vl.get(k)
                    if v and v > 10.0 and (w_val + v) > 100.0:
                        vl[k] = round(v / 10.0, 2)
                        
                mds_val = vl.get("mds") or 0.0
                starch_val = vl.get("starch") or 0.0
                if mds_val > 0 or starch_val > 0:
                    current_carbs = vl.get("carbohydrates") or 0.0
                    sum_sugars = round(mds_val + starch_val, 2)
                    if current_carbs < mds_val:
                        vl["carbohydrates"] = sum_sugars
                        
                prot = vl.get("protein") or 0.0
                fat = vl.get("fat") or 0.0
                carb = vl.get("carbohydrates") or 0.0
                oa = vl.get("organic_acids") or 0.0
                alk = vr.get("alk") or 0.0
                kcal = vr.get("kcal")
                
                t_total += 1
                if kcal is not None:
                    calc = 4*prot + 9*fat + 4*carb + 3*oa + 7*alk
                    diff = abs(calc - kcal)
                    if diff <= max(12.0, 0.20 * kcal):
                        t_valid += 1
                        
        total_valid += t_valid
        total_prods += t_total
        print(f"Table {t_id:2d} ({group_name:<40}): {t_valid:3d} / {t_total:3d} valid ({t_valid/t_total*100:.1f}%)")
        
    print(f"\nOVERALL VALIDATION: {total_valid} / {total_prods} ({total_valid / total_prods * 100:.1f}%)")

if __name__ == "__main__":
    test_all()

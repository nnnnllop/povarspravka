import pymupdf
import re

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def extract_appendix1(doc):
    waste_dict = {}
    
    for pno in range(201, 207):
        page = doc[pno]
        words = page.get_text("words")
        
        # Col 1: name x in [30, 200], val x in [180, 260]
        # Col 2: name x in [260, 470], val x in [450, 560]
        for col_name_x, col_val_x in [((30, 195), (195, 265)), ((260, 465), (465, 560))]:
            # Find values (pure numbers or ranges)
            vals = [w for w in words if col_val_x[0] <= w[0] <= col_val_x[1] and re.search(r'\d', w[4]) and w[1] > 100]
            vals.sort(key=lambda w: w[1])
            
            for v in vals:
                # Find product name above/near this value in col_name_x
                y_val = v[1]
                # Words in name column around y_val
                nw = [w for w in words if col_name_x[0] <= w[0] <= col_name_x[1] and abs(w[1] - y_val) < 10]
                nw.sort(key=lambda w: w[0])
                name = " ".join([w[4] for w in nw]).strip()
                # Clean value
                v_str = v[4].replace(',', '.')
                # If number
                m = re.match(r'^([0-9.]+)', v_str)
                if m and name and len(name) > 2 and not name.isupper():
                    waste_dict[name.lower()] = float(m.group(1))
                    
    return waste_dict

def main():
    doc = pymupdf.open(PDF_PATH)
    w = extract_appendix1(doc)
    print(f"Extracted {len(w)} waste entries from Appendix 1. Samples:")
    for k in list(w.keys())[:15]:
        print(f"  {k}: {w[k]}%")

if __name__ == "__main__":
    main()

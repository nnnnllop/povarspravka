import pymupdf
import re

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def main():
    doc = pymupdf.open(PDF_PATH)
    
    # We will collect products
    # A product code typically has format: \d+\.\d+\.\d+(?:\.\d+)*
    # Let's inspect how many product codes appear on each spread
    all_codes = {}
    
    for left_idx in range(24, 194, 2):
        p_left = doc[left_idx]
        p_right = doc[left_idx + 1]
        
        # Look for code words in left column (x < 90)
        words_l = p_left.get_text("words")
        words_r = p_right.get_text("words")
        
        # Sort words by y
        # Find product codes: e.g. 1.1.1.1, 1.1.1.2 or 3.1.1 etc.
        # Notice some codes might have OCR typos like 1 1.1.1 or 1.1.15 instead of 1.1.1.5
        # Let's inspect all candidate code patterns
        left_codes = []
        for w in words_l:
            if w[0] < 90:
                txt = w[4].strip()
                # If matches pattern like \d+\.\d+...
                if re.match(r'^\d+\.\d+(\.\d+)+$', txt):
                    left_codes.append((txt, w[1], w[3])) # code, y0, y1
                    
        right_codes = []
        for w in words_r:
            if w[0] > 450: # On right page, code is in rightmost column (x > 450)
                txt = w[4].strip()
                if re.match(r'^\d+\.\d+(\.\d+)+$', txt):
                    right_codes.append((txt, w[1], w[3]))
                    
        all_codes[left_idx + 1] = {
            "left_codes": left_codes,
            "right_codes": right_codes
        }
        
    total_l = sum(len(v["left_codes"]) for v in all_codes.values())
    total_r = sum(len(v["right_codes"]) for v in all_codes.values())
    print(f"Total regex matched codes on left pages: {total_l}")
    print(f"Total regex matched codes on right pages: {total_r}")
    
    # Print sample from a few pages
    for pno in [25, 51, 53, 81, 103, 111, 127, 129, 151, 163, 175, 191]:
        info = all_codes[pno]
        print(f"Doc page {pno}: {len(info['left_codes'])} left codes, {len(info['right_codes'])} right codes")
        if info['left_codes']:
            print(f"  Sample codes: {[c[0] for c in info['left_codes'][:5]]}")

if __name__ == "__main__":
    main()

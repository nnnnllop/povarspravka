import pymupdf
import json

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def analyze_spread(left_pno, right_pno):
    doc = pymupdf.open(PDF_PATH)
    p_left = doc[left_pno - 1]
    p_right = doc[right_pno - 1]
    
    print(f"=== SPREAD: Pages {left_pno} and {right_pno} ===")
    
    # Left page blocks
    blocks_left = p_left.get_text("blocks")
    # Sort by y0, then x0
    blocks_left.sort(key=lambda b: (round(b[1], 1), round(b[0], 1)))
    
    # Find table lines/drawings if any
    drawings_left = p_left.get_drawings()
    print(f"Drawings on left page: {len(drawings_left)}")
    
    # Find all words with coords
    words_l = p_left.get_text("words")
    words_r = p_right.get_text("words")
    
    # Look at y-ranges for row groups
    # Code column on left page is typically around x < 80
    code_words = [w for w in words_l if w[0] < 80 and any(c.isdigit() for c in w[4])]
    print(f"Codes found in left column (x < 80): {len(code_words)}")
    for cw in code_words[:10]:
        print(f"  Code: {cw[4]:<15} at y0={cw[1]:.1f}, y1={cw[3]:.1f}")

if __name__ == "__main__":
    analyze_spread(25, 26)

import pymupdf
import re

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

# The start doc page of each of the 12 tables:
TABLE_STARTS = [
    (1, 25),
    (2, 51),
    (3, 53),
    (4, 81),
    (5, 103),
    (6, 111),
    (7, 127),
    (8, 129),
    (9, 151),
    (10, 163),
    (11, 175),
    (12, 191)
]

def main():
    doc = pymupdf.open(PDF_PATH)
    for t_num, pno in TABLE_STARTS:
        p_left = doc[pno - 1]
        p_right = doc[pno] # right page
        
        # Get headers (y < 90)
        wl = [w for w in p_left.get_text("words") if 35 <= w[1] <= 80]
        wl.sort(key=lambda w: w[0])
        wr = [w for w in p_right.get_text("words") if 35 <= w[1] <= 80]
        wr.sort(key=lambda w: w[0])
        
        headers_left = " ".join([w[4] for w in wl if not w[4].isdigit() and w[4] not in ['%', 'мг%']])
        headers_right = " ".join([w[4] for w in wr if not w[4].isdigit() and w[4] not in ['%', 'мг%', 'мкг%']])
        
        print(f"\n--- TABLE {t_num} (Doc pages {pno}, {pno+1}) ---")
        print(f"LEFT headers:  {headers_left[:120]}")
        print(f"RIGHT headers: {headers_right[:120]}")

if __name__ == "__main__":
    main()

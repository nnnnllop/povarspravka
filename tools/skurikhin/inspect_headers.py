import pymupdf

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def main():
    doc = pymupdf.open(PDF_PATH)
    p_left = doc[24] # page 25
    p_right = doc[25] # page 26
    
    print("=== Column Headers on Left Page (y < 125) ===")
    words_l = p_left.get_text("words")
    # headers are above y=120
    hl = [w for w in words_l if w[1] < 125 and w[1] > 30]
    hl.sort(key=lambda w: (round(w[1], 1), round(w[0], 1)))
    for w in hl:
        print(f"x=({w[0]:5.1f}..{w[2]:5.1f}), y=({w[1]:5.1f}..{w[3]:5.1f}): {w[4]}")
        
    print("\n=== Column Headers on Right Page (y < 125) ===")
    words_r = p_right.get_text("words")
    hr = [w for w in words_r if w[1] < 125 and w[1] > 30]
    hr.sort(key=lambda w: (round(w[1], 1), round(w[0], 1)))
    for w in hr:
        print(f"x=({w[0]:5.1f}..{w[2]:5.1f}), y=({w[1]:5.1f}..{w[3]:5.1f}): {w[4]}")

if __name__ == "__main__":
    main()

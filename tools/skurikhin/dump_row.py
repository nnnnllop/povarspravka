import pymupdf

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def main():
    doc = pymupdf.open(PDF_PATH)
    p_left = doc[24]
    p_right = doc[25]
    
    # Left page words between y=120 and 175
    wl = [w for w in p_left.get_text("words") if 120 <= w[1] <= 175]
    wl.sort(key=lambda w: (round(w[1], 1), round(w[0], 1)))
    
    print("=== LEFT PAGE (y in 120..175) ===")
    current_y = None
    line = []
    for w in wl:
        y = round(w[1], 0)
        if current_y is None or abs(y - current_y) > 4:
            if line:
                print(f"y={current_y:5.1f} | " + " ".join(line))
            current_y = y
            line = [f"({w[0]:.1f}:{w[4]})"]
        else:
            line.append(f"({w[0]:.1f}:{w[4]})")
    if line:
        print(f"y={current_y:5.1f} | " + " ".join(line))
        
    print("\n=== RIGHT PAGE (y in 120..175) ===")
    wr = [w for w in p_right.get_text("words") if 120 <= w[1] <= 175]
    wr.sort(key=lambda w: (round(w[1], 1), round(w[0], 1)))
    current_y = None
    line = []
    for w in wr:
        y = round(w[1], 0)
        if current_y is None or abs(y - current_y) > 4:
            if line:
                print(f"y={current_y:5.1f} | " + " ".join(line))
            current_y = y
            line = [f"({w[0]:.1f}:{w[4]})"]
        else:
            line.append(f"({w[0]:.1f}:{w[4]})")
    if line:
        print(f"y={current_y:5.1f} | " + " ".join(line))

if __name__ == "__main__":
    main()

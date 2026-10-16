import pymupdf

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def test_spread_alignment(left_pno):
    doc = pymupdf.open(PDF_PATH)
    pl = doc[left_pno - 1]
    pr = doc[left_pno]
    
    # Find all "100" in portion column (x in 185..225)
    portions_100 = [w for w in pl.get_text("words") if 185 <= w[0] <= 225 and w[4] == '100']
    portions_100.sort(key=lambda w: w[1])
    
    # On right page, find kcal or code near those y coordinates
    print(f"Spread ({left_pno}, {left_pno+1}): Found {len(portions_100)} products with '100' portion:")
    for w in portions_100[:5]:
        y = w[1]
        # find code on left
        codes_l = [cw[4] for cw in pl.get_text("words") if cw[0] < 85 and abs(cw[1] - y) < 8]
        # find code on right
        codes_r = [cw[4] for cw in pr.get_text("words") if cw[0] > 470 and abs(cw[1] - y) < 8]
        # find kcal on right
        kcal_r = [cw[4] for cw in pr.get_text("words") if 448 <= cw[0] <= 480 and abs(cw[1] - y) < 8]
        print(f"  y={y:.1f}: L_code={codes_l}, R_code={codes_r}, kcal={kcal_r}")

if __name__ == "__main__":
    for p in [25, 51, 53, 81, 103, 111, 127, 129, 151, 163, 175, 191]:
        test_spread_alignment(p)

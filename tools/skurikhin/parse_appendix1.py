import pymupdf

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def main():
    doc = pymupdf.open(PDF_PATH)

    # Doc pages 202 to 207 (pages 201..206 0-indexed)
    for pno in range(201, 207):
        page = doc[pno]
        words = page.get_text("words")
        # Appendix 1 has 2 pairs of columns:
        # Col 1: Product name (x ~ 30..150), Waste % (x ~ 150..250)
        # Col 2: Product name (x ~ 260..420), Waste % (x ~ 420..550)
        print(f"\n--- Appendix 1 Doc Page {pno+1} ---")
        lines = page.get_text().split('\n')
        # Filter non-empty
        lines = [l.strip() for l in lines if l.strip()]
        for l in lines[:15]:
            print("  ", l)

if __name__ == "__main__":
    main()

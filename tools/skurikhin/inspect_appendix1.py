import pymupdf

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def main():
    doc = pymupdf.open(PDF_PATH)
    # Check pages 202 to 207 (Appendix 1)
    for p in range(201, 207):
        print(f"=== Doc Page {p+1} ===")
        txt = doc[p].get_text()
        lines = [l.strip() for l in txt.split('\n') if l.strip()]
        for l in lines[:25]:
            print("  ", l)

if __name__ == "__main__":
    main()

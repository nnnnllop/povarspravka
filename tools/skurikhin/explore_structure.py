import pymupdf
import re

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def main():
    doc = pymupdf.open(PDF_PATH)
    print(f"Total pages: {len(doc)}")
    
    # Check page ranges for tables
    table_starts = {}
    for i, page in enumerate(doc):
        text = page.get_text()
        first_few = text[:500]
        # Match "ТАБЛИЦА 1" or "Таблица 1."
        m = re.search(r'(?:ТАБЛИЦА|Таблица)\s+(\d+)', first_few)
        if m:
            t_num = int(m.group(1))
            if t_num not in table_starts:
                table_starts[t_num] = []
            table_starts[t_num].append(i + 1)
            
    print("Table occurrences in PDF pages:")
    for t_num in sorted(table_starts.keys()):
        print(f"Table {t_num}: doc pages {table_starts[t_num][:10]} (total {len(table_starts[t_num])})")

    # Check pages around 180-205
    for p in range(185, 205):
        txt = doc[p].get_text()
        first_line = txt.strip().split('\n')[0] if txt.strip() else 'EMPTY'
        print(f"Doc page {p+1}: {first_line[:80]}")

if __name__ == "__main__":
    main()

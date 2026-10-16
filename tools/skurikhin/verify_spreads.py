import pymupdf
import re

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def main():
    doc = pymupdf.open(PDF_PATH)
    
    print("Checking pairs from doc page 25 to 194:")
    for left_idx in range(24, 194, 2):
        right_idx = left_idx + 1
        p_left = doc[left_idx]
        p_right = doc[right_idx]
        
        t_left = p_left.get_text()[:200].replace('\n', ' ')
        t_right = p_right.get_text()[:200].replace('\n', ' ')
        
        # Check if left has ТАБЛИЦА and right has column headers or table continuation
        m_left = re.search(r'ТАБЛИЦА\s+(\d+)', t_left)
        t_left_num = m_left.group(1) if m_left else "NO_TAB"
        
        # Extract product codes on left vs right
        # Codes are like 1.1.1.1, 3.2.1, etc.
        codes_left = re.findall(r'\b\d+\.\d+(?:\.\d+)*(?:\.\d+)*\b', p_left.get_text())
        codes_right = re.findall(r'\b\d+\.\d+(?:\.\d+)*(?:\.\d+)*\b', p_right.get_text())
        
        # Filter codes that look like product codes (depth >= 2 or 3)
        prod_left = [c for c in codes_left if c.count('.') >= 2]
        prod_right = [c for c in codes_right if c.count('.') >= 2]
        
        print(f"Pages ({left_idx+1}, {right_idx+1}) [Tab {t_left_num}]: left_prods={len(prod_left)}, right_prods={len(prod_right)}")
        # Check if first and last product codes match
        if prod_left and prod_right:
            if prod_left[0] != prod_right[0]:
                print(f"  WARNING: mismatch first code! L={prod_left[0]} vs R={prod_right[0]}")
            if prod_left[-1] != prod_right[-1]:
                print(f"  WARNING: mismatch last code! L={prod_left[-1]} vs R={prod_right[-1]}")

if __name__ == "__main__":
    main()

import pymupdf
from rapidocr_onnxruntime import RapidOCR
import re

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

def main():
    engine = RapidOCR()
    doc = pymupdf.open(PDF_PATH)
    
    # Test on page 44 (spread 43, 44), y around 245 (product 1.4.4.4 Сливки сухие 42%)
    p_right = doc[43]
    pix = p_right.get_pixmap(dpi=200, clip=pymupdf.Rect(400, 240, 500, 265))
    res, _ = engine(pix.tobytes("png"))
    print("RapidOCR on p.44 kcal region (1.4.4.4):", [r[1] for r in res])
    
    # Test on page 34 (spread 33, 34), product 1.3.3.7 (Паста ацидофильная)
    # y around 400..450
    p34 = doc[33]
    pix = p34.get_pixmap(dpi=200, clip=pymupdf.Rect(420, 400, 500, 440))
    res, _ = engine(pix.tobytes("png"))
    print("RapidOCR on p.34 kcal region (1.3.3.7):", [r[1] for r in res])

if __name__ == "__main__":
    main()

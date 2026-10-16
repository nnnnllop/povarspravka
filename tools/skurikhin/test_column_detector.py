import pymupdf
import re

PDF_PATH = r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf"

TABLE_STARTS = [
    ("Таблица 1. Молоко и молочные продукты", 25, 50),
    ("Таблица 2. Яйцепродукты", 51, 52),
    ("Таблица 3. Мясо и мясные продукты", 53, 80),
    ("Таблица 4. Рыба и продукты из нее", 81, 102),
    ("Таблица 5. Жировые продукты", 103, 110),
    ("Таблица 6. Зерно и продукты переработки", 111, 126),
    ("Таблица 7. Бобовые, орехи", 127, 128),
    ("Таблица 8. Овощи, грибы", 129, 150),
    ("Таблица 9. Фрукты, ягоды", 151, 162),
    ("Таблица 10. Кондитерские изделия", 163, 174),
    ("Таблица 11. Напитки", 175, 190),
    ("Таблица 12. Вспомогательные вещества", 191, 194),
]

def detect_columns_left(words):
    # Find key headers in y < 100
    headers = {}
    patterns = [
        ("portion", r"^[Пп]орци"),
        ("water", r"^[Вв]ода"),
        ("protein", r"^[Бб]ел"),
        ("fat", r"^[Жж]ир"),
        ("sfa", r"^[Нн][Жж][Кк]"),
        ("pufa_or_chol", r"(?:[Хх]ол|[Пп][Нн][Жж][Кк])"),
        ("mds", r"(?:[Мм][Дд][Сс]|Ыдс)"),
        ("starch", r"(?:[Кк]р|Гкр)"),
        ("carbs", r"^[Уу]гл"),
        ("fiber", r"(?:[Пп][Вв]|РПВ)"),
        ("oa", r"(?:[Оо][Кк]|НПВ)"),
        ("ash", r"^[Зз]ола"),
    ]
    for w in words:
        if w[1] > 100: continue
        for key, pat in patterns:
            if key not in headers and re.search(pat, w[4]):
                headers[key] = (w[0] + w[2]) / 2
                
    return headers

def detect_columns_right(words):
    headers = {}
    patterns = [
        ("na", r"^Na$"),
        ("k", r"^К$"),
        ("ca", r"^Са$"),
        ("mg", r"(?:^Мд$|^Mg$)"),
        ("p", r"^Р$"),
        ("fe", r"^Fe$"),
        ("vit_a", r"^А$"),
        ("carotene", r"^[Кк]ар"),
        ("re", r"^[Рр]Э$"),
        ("te", r"^[Тт]Э$"),
        ("b1", r"(?:^[ВвB]1$|^Bi$)"),
        ("b2", r"(?:^[ВвB]2$)"),
        ("pp", r"^[РрP][РрP]$"),
        ("ne", r"^[НнN][ЭэE]$"),
        ("vit_c", r"^[СcC]$"),
        ("alk", r"^[Аа]лк$"),
        ("kcal", r"(?:[Ээ][Цц]|[Кк]кал)"),
        ("code", r"^[Кк]од$"),
    ]
    for w in words:
        if w[1] > 100: continue
        for key, pat in patterns:
            if key not in headers and re.search(pat, w[4]):
                headers[key] = (w[0] + w[2]) / 2
                
    return headers

def main():
    doc = pymupdf.open(PDF_PATH)
    for title, start_p, end_p in TABLE_STARTS:
        pl = doc[start_p - 1]
        pr = doc[start_p]
        wl = pl.get_text("words")
        wr = pr.get_text("words")
        cl = detect_columns_left(wl)
        cr = detect_columns_right(wr)
        print(f"\n{title} (Doc pages {start_p}-{end_p}):")
        print(f"  Left cols ({len(cl)}/12): {list(cl.keys())}")
        print(f"  Right cols ({len(cr)}/18): {list(cr.keys())}")

if __name__ == "__main__":
    main()

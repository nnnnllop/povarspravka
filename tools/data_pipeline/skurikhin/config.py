"""Configuration for Skurikhin data extraction and validation pipeline."""
from pathlib import Path

# Paths
DEFAULT_PDF_PATH = Path(r"C:\Users\zomni\Downloads\Telegram Desktop\Khimicheskiy_sostav_Rossiyskikh_produktov_pitania_Skurikhin.pdf")
BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parent.parent.parent
OUTPUT_DIR = BASE_DIR.parent / "output"
DB_PATH = OUTPUT_DIR / "reference.db"
JSON_PATH = OUTPUT_DIR / "skurikhin_products.json"
CSV_PATH = OUTPUT_DIR / "skurikhin_products.csv"
VALIDATION_REPORT_PATH = OUTPUT_DIR / "validation_report.json"

# Page ranges in Skurikhin (0-indexed)
TOC_PAGES = range(2, 5)
TABLE_PAGES_RANGE = (24, 193)  # inclusive
APPENDIX_1_PAGES = range(201, 207)  # Waste %
APPENDIX_2_PAGES = range(207, 210)  # Measures (spoons, cups)
APPENDIX_3_PAGE = 210               # 1 piece weights
SUBJECT_INDEX_PAGES = range(211, 235)  # Product alphabetical index

# 12 Primary Food Groups defined in the book
FOOD_GROUPS = [
    {"id": 1, "code": "1", "name": "Молоко и молочные продукты"},
    {"id": 2, "code": "2", "name": "Яйцепродукты"},
    {"id": 3, "code": "3", "name": "Мясо и мясные продукты"},
    {"id": 4, "code": "4", "name": "Рыба, нерыбные объекты промысла и продукты из них"},
    {"id": 5, "code": "5", "name": "Жировые продукты (жирностью более 50%)"},
    {"id": 6, "code": "6", "name": "Зерно и продукты его переработки"},
    {"id": 7, "code": "7", "name": "Бобовые, орехи"},
    {"id": 8, "code": "8", "name": "Овощи, грибы и продукты их переработки"},
    {"id": 9, "code": "9", "name": "Фрукты, ягоды и продукты их переработки"},
    {"id": 10, "code": "10", "name": "Кондитерские изделия"},
    {"id": 11, "code": "11", "name": "Напитки"},
    {"id": 12, "code": "12", "name": "Вспомогательные пищевые вещества и улучшители вкуса"},
]

# Standard nutrient codes matching international INFOODS / USDA standards
NUTRIENT_CODES = {
    # Proximates
    "water": {"name": "Вода", "unit": "g", "code": "WATER"},
    "protein": {"name": "Белок", "unit": "g", "code": "PROCNT"},
    "fat": {"name": "Жиры", "unit": "g", "code": "FAT"},
    "carbs": {"name": "Углеводы", "unit": "g", "code": "CHOCDF"},
    "fiber": {"name": "Пищевые волокна", "unit": "g", "code": "FIBTG"},
    "ash": {"name": "Зола", "unit": "g", "code": "ASH"},
    "organic_acids": {"name": "Органические кислоты", "unit": "g", "code": "OA"},
    "sugars": {"name": "Моно- и дисахара", "unit": "g", "code": "SUGAR"},
    "starch": {"name": "Крахмал", "unit": "g", "code": "STARCH"},
    "sfa": {"name": "Насыщенные жирные кислоты", "unit": "g", "code": "FASAT"},
    "pufa": {"name": "Полиненасыщенные жирные кислоты", "unit": "g", "code": "FAPU"},
    "chol": {"name": "Холестерин", "unit": "mg", "code": "CHOLE"},
    "alcohol": {"name": "Спирт этиловый", "unit": "g", "code": "ALC"},
    # Minerals
    "na": {"name": "Натрий", "unit": "mg", "code": "NA"},
    "k": {"name": "Калий", "unit": "mg", "code": "K"},
    "ca": {"name": "Кальций", "unit": "mg", "code": "CA"},
    "mg": {"name": "Магний", "unit": "mg", "code": "MG"},
    "p": {"name": "Фосфор", "unit": "mg", "code": "P"},
    "fe": {"name": "Железо", "unit": "mg", "code": "FE"},
    # Vitamins
    "vit_a": {"name": "Витамин A (ретинол)", "unit": "mcg", "code": "VITA_RAE"},
    "carotene": {"name": "Бета-каротин", "unit": "mcg", "code": "CARTB"},
    "re": {"name": "Ретиноловый эквивалент", "unit": "mcg", "code": "RETOL"},
    "te": {"name": "Токоферолэквивалент (вит. E)", "unit": "mg", "code": "TOCPHA"},
    "b1": {"name": "Витамин B1 (тиамин)", "unit": "mg", "code": "THIA"},
    "b2": {"name": "Витамин B2 (рибофлавин)", "unit": "mg", "code": "RIBF"},
    "pp": {"name": "Витамин PP (ниацин)", "unit": "mg", "code": "NIA"},
    "ne": {"name": "Ниациновый эквивалент", "unit": "mg", "code": "NIAEQ"},
    "c": {"name": "Витамин C (аскорбиновая к-та)", "unit": "mg", "code": "VITC"},
    # Energy
    "kcal": {"name": "Энергетическая ценность", "unit": "kcal", "code": "ENERC_KCAL"},
}

# Authoritative canonical name overrides for OCR errors / Subject Index shifts in Skurikhin 2002
KNOWN_CANONICAL_NAMES = {
    "8.1.4.1": "Картофель",
    "8.1.4.2": "Картофель сушеный",
    "8.1.4.3": "Борщ с картофелем",
    "8.1.4.4": "Суп картофельный",
    "8.1.4.5": "Суп картофельный с макаронными изделиями",
    "8.1.4.6": "Суп картофельный с горохом",
    "8.1.4.7": "Суп картофельный с крупой",
    "8.1.4.8": "Суп-пюре картофельный",
    "8.1.4.9": "Картофель отварной",
    "8.1.4.10": "Картофель тушеный с грибами",
    "8.1.4.11": "Картофель тушеный с мясом",
    "8.1.4.12": "Картофель в молоке",
    "8.1.4.13": "Картофель запеченный с сыром",
    "8.1.4.14": "Картофель в сметане с чесноком",
    "8.1.4.15": "Картофель жареный (из вареного)",
    "8.1.4.16": "Картофель жареный во фритюре",
    "8.1.4.17": "Картофель жареный (из сырого)",
    "8.1.5.12": "Свекла",
    "8.1.5.24": "Редис",
    "8.1.2.1.13": "Капуста квашеная",
    "9.2.1.1": "Виноград",
    "7.1.7": "Соя, зерно",
    "7.1.11": "Фасоль, зерно",
    "7.1.12": "Фасоль (стручок)",
    "3.5.2.8": "Бифштекс рубленый",
    "2.3.1": "Белок яичный сухой",
    "2.4.1": "Желток яичный сухой",
    "1.6.4.3": "Сыр Сулугуни",
    "5.2.5": "Шпик свиной",
    "5.4.9": "Масло кунжутное",
    "1.2.2.4": "Кефир 2,5% жирности",
    "1.3.2.11": "Ряженка 6,0% жирности",
    "10.8.1": "Какао-порошок",
    "5.1.5": "Масло сливочное несоленое «Крестьянское»",
    # 4.1.1.1 and 4.1.1.5 were both named "Килька балтийская" from the Subject
    # Index, so the fish and the prepared dish were indistinguishable in search.
    # Printed p. 80, code 4.1.1.5: "Килька соленая с картофелем и маслом по 1-100".
    "4.1.1.5": "Килька соленая с картофелем и маслом по 1-100",
}

# Manual corrections for cells whose OCR text layer lost a digit or a decimal
# point.  Every value below was read from the rendered page, not from the text
# layer.  Key: product code -> {field: correct value}.
KNOWN_PROXIMATE_FIXES = {
    # Printed p. 50, table 2: "Яйцо целое 12,7"; the OCR text layer has "12./".
    "2.1.1": {"protein": 12.7},
    "2.1.2": {"protein": 12.7},
    # Printed p. 128: "Салат" 1,5 % protein; OCR produced 5.0.
    "8.1.1.4": {"protein": 1.5},
    # Printed p. 144: "Салат из свежих помидоров с перцем" 87,3 / 0,9.
    "8.1.6.9": {"water": 87.3, "protein": 0.9},
    # Printed p. 184: "Кофе черный" fat 0,5; OCR produced 5.0.
    "11.1.8.2": {"fat": 0.5},
    # Printed p. 170: agar water 14,0 / carbohydrates 0,0; pectin water 10,0.
    "10.11.1": {"water": 14.0, "carbs": 0.0},
    "10.11.11": {"water": 10.0},
    # Printed p. 56: canned chicken in its own juice water 64,4; OCR dropped 6.
    "3.3.11": {"water": 64.4},
    # Printed p. 80: the dish's fibre column is 0,1; OCR produced 3.0.
    "4.1.1.5": {"fiber": 0.1},
    # Printed p. 74: "Столичные" ash 2,8; OCR produced 0.
    "3.6.3.4": {"ash": 2.8},
}

# Energy values that the OCR text layer bound to a neighbouring row.  Verified
# against the printed page and against 4P+9F+4C (+ organic acids, where the
# book includes them).
KNOWN_KCAL_FIXES = {
    # Printed p. 185: coffee (black, no sugar) 7 kcal / 100 g.
    "11.1.8.2": 7.0,
    # Printed p. 145: 66 kcal / 100 g (0.9 protein, 4.7 fat, 4.3 carbs).
    "8.1.6.9": 66.0,
}

# Waste overrides where the Appendix 1 heuristic is ambiguous or clearly wrong.
# None means "no cold-processing waste" (a prepared dish / ready-to-eat product).
KNOWN_WASTE_OVERRIDES = {
    # Printed p. 204: "Яйца куриные I категории 13"; "Яйца перепелиные 8".
    "2.1.1": 13.0,
    "2.5.1": 8.0,
    # Printed p. 80: 4.1.1.5 is a prepared dish, not the raw fish; the 46 % in
    # Appendix 1 belongs to 4.1.1.1 "Килька балтийская".
    "4.1.1.5": None,
    # Prepared egg salad (p. 50) must not inherit the raw "Салат" 20 %.
    "2.1.5": None,
}

# Common Russian culinary synonyms for fast search in reference.db
SKURIKHIN_SYNONYMS = [
    ("8.1.4.1", "картошка"),
    ("8.1.4.1", "картоха"),
    ("6.6.4", "гречка"),
    ("6.6.4", "гречневая крупа"),
    ("6.6.4", "ядрица"),
    ("6.6.3", "продел"),
    ("6.2.5.1", "овсянка"),
    ("6.2.5.1", "геркулес"),
    ("6.2.5.1", "овсяные хлопья"),
    ("3.5.6.1", "курица"),
    ("3.5.6.1", "курятина"),
    ("8.1.6.6", "помидор"),
    ("8.1.6.6", "помидоры"),
    ("8.1.5.12", "бурак"),
    ("8.1.5.12", "свеколка"),
    ("8.1.5.18", "морковка"),
    ("8.1.1.1", "лучок"),
    ("8.1.1.1", "репчатый лук"),
    ("2.1.1", "яйцо"),
    ("2.1.1", "яйца куриные"),
    ("5.1.1", "сливочное масло"),
    ("5.4.1", "подсолнечное масло"),
    ("5.4.1", "растительное масло"),
    ("10.1.1", "сахар"),
    ("12.1.1", "соль"),
    ("12.1.1", "поваренная соль"),
    ("1.1.1.1", "молоко коровье"),
    ("1.4.1.1", "сметанка"),
    ("1.5.1", "творожок"),
    ("1.2.1.1", "кефирчик"),
]

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

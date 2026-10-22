"""Configuration and constants for USDA data pipeline (SR Legacy and Foundation Foods)."""

from __future__ import annotations

from pathlib import Path

# Base Paths
PACKAGE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = PACKAGE_DIR.parents[2]
DATA_DIR = PACKAGE_DIR / "data"
OUTPUT_DIR = PACKAGE_DIR / "output"

# Source Data Locations (SR Legacy + Foundation Foods)
USDA_CACHE_DIR = PROJECT_ROOT / "tools" / "usda" / "cache"
SR_LEGACY_DIR = USDA_CACHE_DIR / "sr_legacy" / "FoodData_Central_sr_legacy_food_csv_2018-04"
FOUNDATION_DIR = USDA_CACHE_DIR / "foundation" / "FoodData_Central_foundation_food_csv_2024-10-31"
SR_LEGACY_ZIP = USDA_CACHE_DIR / "sr_legacy.zip"
FOUNDATION_ZIP = USDA_CACHE_DIR / "foundation.zip"

# Fallback Survey Foods archive
DEFAULT_SURVEY_ZIP = DATA_DIR / "FoodData_Central_survey_food_json_2024-10-31.zip"

# Output Locations
DEFAULT_OUTPUT_DB = OUTPUT_DIR / "usda_products.db"
DEFAULT_MANIFEST_PATH = OUTPUT_DIR / "usda_catalog_manifest.json"
DEFAULT_VALIDATION_REPORT = OUTPUT_DIR / "validation_report.json"
TRANSLATION_CACHE_PATH = DATA_DIR / "translation_cache.json"
TRANSLATIONS_CACHE_DB = USDA_CACHE_DIR / "translations_cache.db"

REFERENCE_DB_PATH = PROJECT_ROOT / "tools" / "data_pipeline" / "output" / "reference.db"
APP_ASSETS_DIR = PROJECT_ROOT / "app" / "assets" / "db"

# Argos Translate Model Path (optional offline fallback)
ARGOS_MODEL_PATH = Path("C:/Users/zomni/.gemini/antigravity/scratch/translate-en_ru.argosmodel")

# Validation Constraints
MAX_CALORIES = 950.0  # Pure fat is ~900 kcal/100g
MAX_MACRO_VALUE = 100.0  # Max per 100g
MAX_MACRO_SUM = 105.0  # Allow slight analytical variance
ATWATER_TOLERANCE_PCT = 0.25  # 25% discrepancy tolerance before warning
MIN_VALID_PRODUCTS = 4000

# Core Nutrient IDs in USDA CSVs and JSONs
# Format: both 4-digit FDC nutrient IDs and 3-digit nutrient numbers
NUTRIENT_IDS = {
    "protein": ("1003", "203"),
    "fat": ("1004", "204"),
    "carbs": ("1005", "205"),
    "energy": ("1008", "208"),
    "water": ("1051", "255"),
    "fiber": ("1079", "291"),
    "ash": ("1007", "207"),
    "sugars": ("2000", "269"),
    "starch": ("1009", "209"),
    "sfa": ("1258", "606"),
    "pufa": ("1257", "646"),
    "mufa": ("1292", "645"),
    "chol": ("1253", "601"),
    "alcohol": ("1018", "221"),
    # Minerals
    "ca": ("1087", "301"),
    "fe": ("1089", "303"),
    "mg": ("1090", "304"),
    "p": ("1091", "305"),
    "k": ("1092", "306"),
    "na": ("1093", "307"),
    "zn": ("1095", "309"),
    "cu": ("1098", "312"),
    "se": ("1103", "317"),
    # Vitamins
    "retol": ("1105", "319"),
    "vit_a": ("1106", "320"),
    "carotene": ("1107", "321"),
    "tocpha": ("1109", "323"),
    "vit_d": ("1114", "328"),
    "vit_c": ("1162", "401"),
    "b1": ("1165", "404"),
    "b2": ("1166", "405"),
    "pp": ("1167", "406"),
    "b6": ("1175", "415"),
    "fol": ("1177", "417"),
    "b12": ("1178", "418"),
    "choln": ("1180", "421"),
    "vit_k": ("1185", "430"),
}

# Standard INFOODS Nutrient Codes matching plan.md & skurikhin/config.py
NUTRIENT_CODE_MAP: dict[str, str] = {
    # Proximates
    "1003": "PROCNT", "203": "PROCNT",
    "1004": "FAT", "204": "FAT",
    "1005": "CHOCDF", "205": "CHOCDF",
    "1008": "ENERC_KCAL", "208": "ENERC_KCAL",
    "1051": "WATER", "255": "WATER",
    "1079": "FIBTG", "291": "FIBTG",
    "1007": "ASH", "207": "ASH",
    "2000": "SUGAR", "269": "SUGAR", "1063": "SUGAR",
    "1009": "STARCH", "209": "STARCH",
    "1258": "FASAT", "606": "FASAT",
    "1257": "FAPU", "646": "FAPU",
    "1292": "FAMS", "645": "FAMS",
    "1253": "CHOLE", "601": "CHOLE",
    "1018": "ALC", "221": "ALC",
    # Minerals
    "1087": "CA", "301": "CA",
    "1089": "FE", "303": "FE",
    "1090": "MG", "304": "MG",
    "1091": "P", "305": "P",
    "1092": "K", "306": "K",
    "1093": "NA", "307": "NA",
    "1095": "ZN", "309": "ZN",
    "1098": "CU", "312": "CU",
    "1103": "SE", "317": "SE",
    # Vitamins
    "1105": "RETOL", "319": "RETOL",
    "1106": "VITA_RAE", "320": "VITA_RAE",
    "1107": "CARTB", "321": "CARTB",
    "1109": "TOCPHA", "323": "TOCPHA",
    "1114": "VITD", "328": "VITD",
    "1162": "VITC", "401": "VITC",
    "1165": "THIA", "404": "THIA",
    "1166": "RIBF", "405": "RIBF",
    "1167": "NIA", "406": "NIA",
    "1175": "VITB6A", "415": "VITB6A",
    "1177": "FOL", "417": "FOL",
    "1178": "VITB12", "418": "VITB12",
    "1180": "CHOLN", "421": "CHOLN",
    "1185": "VITK1", "430": "VITK1",
}

# 28 USDA SR Legacy & Foundation Food Categories
USDA_CATEGORIES: dict[str, dict[str, Any]] = {
    "1": {"id": 101, "code": "USDA_0100", "name_en": "Dairy and Egg Products", "name_ru": "Молочные продукты и яйца"},
    "2": {"id": 102, "code": "USDA_0200", "name_en": "Spices and Herbs", "name_ru": "Специи и пряности"},
    "3": {"id": 103, "code": "USDA_0300", "name_en": "Baby Foods", "name_ru": "Детское питание"},
    "4": {"id": 104, "code": "USDA_0400", "name_en": "Fats and Oils", "name_ru": "Жиры и масла"},
    "5": {"id": 105, "code": "USDA_0500", "name_en": "Poultry Products", "name_ru": "Птица и продукты из птицы"},
    "6": {"id": 106, "code": "USDA_0600", "name_en": "Soups, Sauces, and Gravies", "name_ru": "Супы, соусы и подливы"},
    "7": {"id": 107, "code": "USDA_0700", "name_en": "Sausages and Luncheon Meats", "name_ru": "Колбасы и мясные деликатесы"},
    "8": {"id": 108, "code": "USDA_0800", "name_en": "Breakfast Cereals", "name_ru": "Сухие завтраки"},
    "9": {"id": 109, "code": "USDA_0900", "name_en": "Fruits and Fruit Juices", "name_ru": "Фрукты и фруктовые соки"},
    "10": {"id": 110, "code": "USDA_1000", "name_en": "Pork Products", "name_ru": "Свинина и продукты из свинины"},
    "11": {"id": 111, "code": "USDA_1100", "name_en": "Vegetables and Vegetable Products", "name_ru": "Овощи и продукты из овощей"},
    "12": {"id": 112, "code": "USDA_1200", "name_en": "Nut and Seed Products", "name_ru": "Орехи и семена"},
    "13": {"id": 113, "code": "USDA_1300", "name_en": "Beef Products", "name_ru": "Говядина и продукты из говядины"},
    "14": {"id": 114, "code": "USDA_1400", "name_en": "Beverages", "name_ru": "Напитки"},
    "15": {"id": 115, "code": "USDA_1500", "name_en": "Finfish and Shellfish Products", "name_ru": "Рыба и морепродукты"},
    "16": {"id": 116, "code": "USDA_1600", "name_en": "Legumes and Legume Products", "name_ru": "Бобовые и продукты из бобовых"},
    "17": {"id": 117, "code": "USDA_1700", "name_en": "Lamb, Veal, and Game Products", "name_ru": "Баранина, телятина и дичь"},
    "18": {"id": 118, "code": "USDA_1800", "name_en": "Baked Products", "name_ru": "Выпечка и хлебобулочные изделия"},
    "19": {"id": 119, "code": "USDA_1900", "name_en": "Sweets", "name_ru": "Сладости и кондитерские изделия"},
    "20": {"id": 120, "code": "USDA_2000", "name_en": "Cereal Grains and Pasta", "name_ru": "Злаки, крупы и макароны"},
    "21": {"id": 121, "code": "USDA_2100", "name_en": "Fast Foods", "name_ru": "Фастфуд"},
    "22": {"id": 122, "code": "USDA_2200", "name_en": "Meals, Entrees, and Side Dishes", "name_ru": "Готовые блюда и гарниры"},
    "23": {"id": 123, "code": "USDA_2500", "name_en": "Snacks", "name_ru": "Снеки и закуски"},
    "24": {"id": 124, "code": "USDA_3500", "name_en": "American Indian/Alaska Native Foods", "name_ru": "Традиционные блюда коренных народов"},
    "25": {"id": 125, "code": "USDA_3600", "name_en": "Restaurant Foods", "name_ru": "Ресторанные блюда"},
    "26": {"id": 126, "code": "USDA_4500", "name_en": "Branded Food Products Database", "name_ru": "Брендовые продукты"},
    "27": {"id": 127, "code": "USDA_2600", "name_en": "Quality Control Materials", "name_ru": "Контрольные образцы"},
    "28": {"id": 128, "code": "USDA_1410", "name_en": "Alcoholic Beverages", "name_ru": "Алкогольные напитки"},
}

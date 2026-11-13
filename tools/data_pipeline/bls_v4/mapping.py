"""Соответствие «BLS 4.0 -> единый формат питательных веществ».

Единый формат повторяет `skurikhin_products.json`: словарь
`nutrients[key] = {value, unit, label}`, значения на 100 г съедобной части.

Особенности BLS, которые здесь учтены:
  * энергия дана в кДж (`ENERCJ`) и ккал (`ENERCC`);
  * йод (`ID`) — в мкг/100 г, а не в мг, как остальные минералы;
  * β-каротин (`CARTB`) — в мкг/100 г (в справочнике Скурихина — мг);
  * витамин A дан как ретиноловый эквивалент (`VITA`, мкг RE);
  * «доступные» углеводы — `CHO`; пищевые волокна — отдельно `FIBT`;
  * пропуски закодированы строками «-», «<LOD», «TR», «<LOQ».
"""
from __future__ import annotations

# BLS-код столбца -> (ключ унифицированного формата, единица, подпись)
NUTRIENTS: dict[str, tuple[str, str, str]] = {
    "ENERCC": ("energy_kcal", "kcal", "ЭЦ, ккал"),
    "ENERCJ": ("energy_kj", "kJ", "ЭЦ, кДж"),
    "WATER": ("water", "g", "Вода, г"),
    "PROT625": ("protein", "g", "Белки, г"),
    "FAT": ("fat", "g", "Жиры, г"),
    "CHO": ("carbs", "g", "Углеводы усвояемые, г"),
    "FIBT": ("fiber", "g", "ПВ, г"),
    "SUGAR": ("sugars", "g", "Моно- и дисахариды, г"),
    "STARCH": ("starch", "g", "Крахмал, г"),
    "ALC": ("alcohol", "g", "Алкоголь, г"),
    "OA": ("organic_acids", "g", "Органические кислоты, г"),
    "ASH": ("ash", "g", "Зола, г"),
    "FASAT": ("fat_saturated", "g", "НЖК, г"),
    "FAMS": ("fat_mono", "g", "МНЖК, г"),
    "FAPU": ("fat_polyunsaturated", "g", "ПНЖК, г"),
    "CHORL": ("cholesterol", "mg", "Холестерин, мг"),
    "NA": ("sodium", "mg", "Na, мг"),
    "K": ("potassium", "mg", "K, мг"),
    "CA": ("calcium", "mg", "Ca, мг"),
    "MG": ("magnesium", "mg", "Mg, мг"),
    "P": ("phosphorus", "mg", "P, мг"),
    "FE": ("iron", "mg", "Fe, мг"),
    "ID": ("iodine", "µg", "Йод, мкг"),
    "VITA": ("vitamin_a_re", "µg", "Витамин A (RE), мкг"),
    # Дефект D16: ретинол (`RETOL`, мкг/100 г) раньше не импортировался вовсе —
    # в базе у продуктов BLS была только величина РЭ, а карточка не показывала
    # «Витамин A (ретинол)». В BLS значение уже в мкг, пересчёт не нужен.
    "RETOL": ("retinol", "µg", "Ретинол, мкг"),
    "CARTB": ("beta_carotene", "µg", "β-каротин, мкг"),
    "VITE": ("vitamin_e", "mg", "Витамин E, мг"),
    "VITD": ("vitamin_d", "µg", "Витамин D, мкг"),
    "THIA": ("vitamin_b1", "mg", "Витамин B1, мг"),
    "RIBF": ("vitamin_b2", "mg", "Витамин B2, мг"),
    "NIA": ("niacin", "mg", "Ниацин (PP), мг"),
    "NIAEQ": ("niacin_equivalent", "mg", "Ниациновый эквивалент, мг"),
    "VITC": ("vitamin_c", "mg", "Витамин C, мг"),
}

# порядок вывода в JSON
ORDER = [
    "energy_kcal", "energy_kj", "water", "protein", "fat",
    "fat_saturated", "fat_mono", "fat_polyunsaturated", "cholesterol",
    "carbs", "sugars", "starch", "fiber", "organic_acids", "alcohol", "ash",
    "sodium", "potassium", "calcium", "magnesium", "phosphorus", "iron",
    "iodine",
    "vitamin_a_re", "retinol", "beta_carotene", "vitamin_e", "vitamin_d",
    "vitamin_b1", "vitamin_b2", "niacin", "niacin_equivalent", "vitamin_c",
]

# Первая буква кода BLS -> категория (детерминированное правило)
CATEGORIES: dict[str, str] = {
    "B": "Хлеб",
    "C": "Крупы, мука, макароны",
    "D": "Кондитерские изделия",
    # В BLS 4.0 буква E — «Eier und Eierzeugnisse» (яйца и макаронные
    # изделия), а не напитки: напитки это N (безалкогольные) и P (алкогольные).
    "E": "Яйца и макаронные изделия",
    "F": "Фрукты",
    "G": "Овощи и грибы",
    "H": "Бобовые, орехи, семена, соевые продукты",
    "J": "Вегетарианские продукты, соя",
    "K": "Картофель",
    "M": "Молоко и сыры",
    "N": "Безалкогольные напитки",
    "P": "Алкогольные напитки",
    "Q": "Масла и жиры",
    "R": "Специи, соусы, соль",
    "S": "Сладости, сахар, мёд, мороженое",
    "T": "Рыба и морепродукты",
    "U": "Говядина, телятина, баранина",
    "V": "Птица, дичь, субпродукты",
    "W": "Колбасные и мясные изделия",
    "X": "Готовые блюда",
    "Y": "Сложные блюда, супы",
}

# единицы, которые обязаны совпадать при проверке
EXPECTED_UNITS = {key: unit for key, unit, _ in NUTRIENTS.values()}

# Критерии формулы ккал BLS (энергия на 100 г)
KCAL = {"protein": 4.0, "fat": 9.0, "carbs": 4.0, "fiber": 2.0,
        "alcohol": 7.0, "organic_acids": 3.0, "polyol": 2.4}


def category_of(code: str) -> str:
    return CATEGORIES.get((code or "?")[0].upper(), "Прочее")

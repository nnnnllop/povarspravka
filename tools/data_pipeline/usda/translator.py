"""Culinary translation, search normalization, and synonym generation engine for USDA foods."""

from __future__ import annotations

import json
import logging
import re
import sqlite3
from pathlib import Path
from typing import Any

from .config import (
    ARGOS_MODEL_PATH,
    TRANSLATION_CACHE_PATH,
    TRANSLATIONS_CACHE_DB,
    USDA_CATEGORIES,
)

logger = logging.getLogger(__name__)

# 28 USDA SR Legacy Food Categories in Russian
USDA_CATEGORIES_RU: dict[str, str] = {
    cat["name_en"]: cat["name_ru"] for cat in USDA_CATEGORIES.values()
}

# WWEIA Categories fallback mapping
WWEIA_CATEGORIES_RU: dict[str, str] = {
    "Apple juice": "Яблочный сок",
    "Apples": "Яблоки",
    "Baby food: cereals": "Детское питание: каши",
    "Baby food: fruit": "Детское питание: фруктовое пюре",
    "Baby food: meat and dinners": "Детское питание: мясные блюда и обеды",
    "Baby food: mixtures": "Детское питание: смешанные пюре",
    "Baby food: snacks and sweets": "Детское питание: снеки и десерты",
    "Baby food: vegetables": "Детское питание: овощное пюре",
    "Baby food: yogurt": "Детское питание: йогурты",
    "Baby juice": "Детский сок",
    "Baby water": "Детская вода",
    "Bacon": "Бекон",
    "Bagels and English muffins": "Бейглы и маффины",
    "Bananas": "Бананы",
    "Bean, pea, legume dishes": "Блюда из бобовых и гороха",
    "Beans, peas, legumes": "Бобы, горох, фасоль",
    "Beef, excludes ground": "Говядина (кроме фарша)",
    "Beer": "Пиво",
    "Biscuits, muffins, quick breads": "Печенье, кексы и сдоба",
    "Blueberries and other berries": "Черника, голубика и лесные ягоды",
    "Bottled water": "Бутилированная вода",
    "Broccoli": "Брокколи",
    "Burgers": "Бургеры",
    "Burritos and tacos": "Буррито и тако",
    "Butter and animal fats": "Сливочное масло и животные жиры",
    "Cabbage": "Капуста",
    "Cakes and pies": "Торты и пироги",
    "Candy containing chocolate": "Шоколадные конфеты",
    "Candy not containing chocolate": "Конфеты и карамель (без шоколада)",
    "Carrots": "Морковь",
    "Cereal bars": "Злаковые батончики",
    "Cheese": "Сыр",
    "Cheese sandwiches": "Сэндвичи с сыром",
    "Chicken fillet sandwiches": "Сэндвичи с куриным филе",
    "Chicken patties, nuggets and tenders": "Куриные котлеты, наггетсы и стрипсы",
    "Chicken, whole pieces": "Курица (кусковое мясо)",
    "Citrus fruits": "Цитрусовые фрукты",
    "Citrus juice": "Цитрусовый сок",
    "Coffee": "Кофе",
    "Cold cuts and cured meats": "Мясная нарезка и ветчина",
    "Coleslaw, non-lettuce salads": "Овощные салаты (без латука)",
    "Cookies and brownies": "Печенье и брауни",
    "Corn": "Кукуруза",
    "Cottage/ricotta cheese": "Творог и рикотта",
    "Crackers, excludes saltines": "Крекеры",
    "Cream and cream substitutes": "Сливки и растительные сливки",
    "Cream cheese, sour cream, whipped cream": "Сливочный сыр, сметана и взбитые сливки",
    "Deli and cured meat sandwiches": "Сэндвичи с мясной нарезкой",
    "Diet soft drinks": "Диетические газированные напитки",
    "Diet sport and energy drinks": "Диетические спортивные напитки",
    "Dips, gravies, other sauces": "Соусы, подливы и дипы",
    "Doughnuts, sweet rolls, pastries": "Пончики, булочки и выпечка",
    "Dried fruits": "Сухофрукты",
    "Egg rolls, dumplings, sushi": "Роллы, пельмени, дамплинги и суши",
    "Egg/breakfast sandwiches": "Сэндвичи с яйцом и утренние сэндвичи",
    "Eggs and omelets": "Яйца и омлеты",
    "Enhanced water": "Обогащенная вода",
    "Fish": "Рыба",
    "Frankfurter sandwiches": "Хот-доги и сэндвичи с сосисками",
    "Frankfurters": "Сосиски и сардельки",
    "French fries and other fried white potatoes": "Картофель фри и жареный картофель",
    "Fried rice and lo/chow mein": "Жареный рис и лапша вок",
    "Fried vegetables": "Жареные овощи",
    "Fruit drinks": "Фруктовые напитки и морсы",
    "Gelatins, ices, sorbets": "Желе, фруктовый лед и сорбеты",
    "Grapes": "Виноград",
    "Grits and other cooked cereals": "Горячие зерновые каши",
    "Ground beef": "Говяжий фарш",
    "Human milk": "Грудное молоко",
    "Ice cream and frozen dairy desserts": "Мороженое и замороженные десерты",
    "Jams, syrups, toppings": "Варенье, джемы, сиропы и топпинги",
    "Lamb, goat, game": "Баранина, козлятина и дичь",
    "Lettuce and lettuce salads": "Салат-латук и листовые салаты",
    "Liquor and cocktails": "Крепкий алкоголь и коктейли",
    "Liver and organ meats": "Печень и субпродукты",
    "Macaroni and cheese": "Макароны с сыром",
    "Mango and papaya": "Манго и папайя",
    "Margarine": "Маргарин",
    "Mashed potatoes and white potato mixtures": "Картофельное пюре и блюда из картофеля",
    "Mayonnaise": "Майонез",
    "Meat and BBQ sandwiches": "Мясные сэндвичи и бургеры с барбекю",
    "Meat mixed dishes": "Смешанные мясные блюда",
    "Melons": "Дыни и арбузы",
    "Milk shakes and other dairy drinks": "Милкшейки и молочные коктейли",
    "Milk, lowfat": "Молоко нежирное (1-2%)",
    "Milk, nonfat": "Молоко обезжиренное (0%)",
    "Milk, reduced fat": "Молоко пониженной жирности (2%)",
    "Milk, whole": "Молоко цельное (3.2-3.5%)",
    "Mustard and other condiments": "Горчица и приправы",
    "Nachos": "Начос",
    "Not included in a food category": "Разное (вне категорий)",
    "Nutrition bars": "Питательные батончики",
    "Nutritional beverages": "Питательные напитки",
    "Nuts and seeds": "Орехи и семена",
    "Oatmeal": "Овсянка и овсяная каша",
    "Olives, pickles, pickled vegetables": "Оливки, соленья и маринованные овощи",
    "Onions": "Лук",
    "Other Mexican mixed dishes": "Мексиканские блюда",
    "Other dark green vegetables": "Темно-зеленые листовые овощи",
    "Other diet drinks": "Другие диетические напитки",
    "Other fruit juice": "Другие фруктовые соки",
    "Other fruits and fruit salads": "Другие фрукты и фруктовые салаты",
    "Other red and orange vegetables": "Красные и оранжевые овощи",
    "Other starchy vegetables": "Крахмалистые овощи",
    "Other vegetables and combinations": "Овощи и овощные смеси",
    "Pancakes, waffles, French toast": "Блины, вафли и тосты",
    "Pasta mixed dishes, excludes macaroni and cheese": "Паста и макаронные блюда с добавками",
    "Pasta sauces, tomato-based": "Томатные соусы для пасты",
    "Pasta, noodles, cooked grains": "Макароны, лапша и вареные крупы",
    "Peaches and nectarines": "Персики и нектарины",
    "Pears": "Груши",
    "Pineapple": "Ананас",
    "Pizza": "Пицца",
    "Plant-based milk": "Растительное молоко",
    "Plant-based yogurt": "Растительный йогурт",
    "Popcorn": "Попкорн",
    "Pork": "Свинина",
    "Potato chips": "Картофельные чипсы",
    "Poultry mixed dishes": "Блюда из птицы",
    "Pretzels/snack mix": "Крендели и снеки",
    "Protein and nutritional powders": "Протеин и спортивные порошки",
    "Pudding": "Пудинг",
    "Ramen and Asian broth-based soups": "Рамен и азиатские супы",
    "Rice": "Рис",
    "Rice mixed dishes": "Блюда из риса",
    "Rolls and buns": "Булочки и рогалики",
    "Salad dressings and vegetable oils": "Заправки для салатов и растительные масла",
    "Saltine crackers": "Соленые крекеры",
    "Sausages": "Колбасы и сосиски",
    "Seafood mixed dishes": "Блюда из морепродуктов",
    "Seafood sandwiches": "Сэндвичи с рыбой и морепродуктами",
    "Shellfish": "Моллюски и ракообразные",
    "Smoothies and grain drinks": "Смузи и злаковые напитки",
    "Soft drinks": "Сладкие газированные напитки",
    "Soups, broth-based": "Супы на прозрачном бульоне",
    "Soups, cream-based": "Крем-супы и супы-пюре",
    "Soy and meat-alternative products": "Соевые продукты и заменители мяса",
    "Soy-based condiments": "Соевый соус и приправы",
    "Spinach": "Шпинат",
    "Sport and energy drinks": "Спортивные и энергетические напитки",
    "Stir-fry and soy-based sauce mixtures": "Стир-фрай и блюда в соевом соусе",
    "Strawberries": "Клубника",
    "String beans": "Стручковая фасоль",
    "Sugar substitutes": "Заменители сахара",
    "Sugars and honey": "Сахар и мед",
    "Tap water": "Водопроводная вода",
    "Tea": "Чай",
    "Tomato-based condiments": "Томатные соусы и кетчуп",
    "Tomatoes": "Помидоры (томаты)",
    "Tortilla, corn, other chips": "Кукурузные чипсы и начос",
    "Tortillas": "Тортильи и лепёшки",
    "Turkey, duck, other poultry": "Индейка, утка и другая птица",
    "Turnovers and other grain-based items": "Пирожки и слойки",
    "Vegetable dishes": "Овощные блюда",
    "Vegetable juice": "Овощной сок",
    "Vegetable sandwiches/burgers": "Овощные сэндвичи и вегетарианские бургеры",
    "Vegetables on a sandwich": "Овощи в сэндвичах",
    "White potatoes, baked or boiled": "Белый картофель (печеный или вареный)",
    "Wine": "Вино",
    "Yeast breads": "Дрожжевой хлеб",
    "Yogurt, Greek": "Греческий йогурт",
    "Yogurt, regular": "Обычный йогурт",
}

# Culinary Dictionary & Term Replacements
CULINARY_TERMS: dict[str, str] = {
    "cooked": "вареный / готовый",
    "raw": "сырой",
    "baked": "запеченный",
    "roasted": "жареный / запеченный",
    "boiled": "вареный",
    "fried": "жареный",
    "pan fried": "жареный на сковороде",
    "deep fried": "во фритюре",
    "broiled": "на гриле",
    "grilled": "на гриле",
    "steamed": "на пару",
    "stewed": "тушеный",
    "braised": "тушеный",
    "smoked": "копченый",
    "cured": "вяленый / сырокопченый",
    "dried": "сушеный",
    "dehydrated": "сушеный (обезвоженный)",
    "canned": "консервированный",
    "frozen": "замороженный",
    "fresh": "свежий",
    "toasted": "подсушенный / тост",
    "pickled": "маринованный / соленый",
    "unprepared": "сырой (полуфабрикат)",
    "prepared": "приготовленный",
    "prepared from recipe": "по домашнему рецепту",
    "home recipe": "домашний рецепт",
    "commercially prepared": "промышленного производства",
    "restaurant": "ресторанный",
    "fast food": "фастфуд",
    "ready-to-eat": "готовый к употреблению",
    "ready-to-feed": "готовая к употреблению",
    "ready-to-serve": "готовый к подаче",
    "nfs": "не уточнено",
    "ns as to fat": "жирность не уточнена",
    "ns as to fat type": "тип жира не уточнен",
    "ns as to type of milk": "тип молока не уточнен",
    "no added fat": "без добавления жира",
    "fat added": "с добавлением жира",
    "with cheese": "с сыром",
    "without cheese": "без сыра",
    "with salt": "с солью",
    "without salt": "без соли",
    "salt added": "с солью",
    "no salt added": "без соли",
    "reduced sodium": "с пониженным содержанием соли",
    "low sodium": "низкое содержание натрия",
    "sweetened": "сладкий (с сахаром)",
    "unsweetened": "без сахара",
    "decaffeinated": "без кофеина",
    "caffeinated": "с кофеином",
    "enriched": "обогащенный",
    "unenriched": "необогащенный",
    "fortified": "обогащенный витаминами",
    "skin eaten": "с кожурой",
    "skin not eaten": "без кожуры",
    "with skin": "с кожей / с кожурой",
    "without skin": "без кожи / без кожуры",
    "meat only": "только мякоть",
    "flesh only": "только мякоть",
    "flesh and skin": "мякоть и кожура",
    "bone-in": "на кости",
    "boneless": "без костей (филе)",
    "boneless, skinless": "филе без кожи",
    "whole": "цельный",
    "plain": "натуральный / без добавок",
    "regular": "классический",
    "light": "облегченный",
    "lowfat": "нежирный (1%)",
    "low fat": "нежирный",
    "nonfat": "обезжиренный (0%)",
    "fat-free": "обезжиренный",
    "fat free": "обезжиренный",
    "reduced fat": "пониженной жирности (2%)",
    "lean": "постный",
    "extra lean": "особо постный",
    "whole grain": "цельнозерновой",
    "whole wheat": "из цельной пшеницы",
    "sliced": "нарезанный ломтиками",
    "diced": "нарезанный кубиками",
    "chopped": "рубленый",
    "mashed": "пюре",
    "pureed": "пюрированный",
    "ground": "фарш",
    "breast": "грудка (филе)",
    "chicken breast": "куриная грудка (филе)",
    "chicken thigh": "куриное бедро",
    "chicken drumstick": "куриная голень",
    "chicken wing": "куриное крыло",
    "ground beef": "говяжий фарш",
    "beef steak": "говяжий стейк",
    "pork chop": "свиная отбивная",
    "pork loin": "свиная корейка",
    "pork rib": "свиные ребра",
    "sweet potato": "батат (сладкий картофель)",
    "sweet potatoes": "батат (сладкий картофель)",
    "french fries": "картофель фри",
    "french fried": "картофель фри",
    "hash brown": "хашбраун (драники)",
    "buttermilk": "пахта",
    "sour cream": "сметана",
    "goat milk": "козье молоко",
    # Primary food items
    "chicken": "курица",
    "beef": "говядина",
    "pork": "свинина",
    "turkey": "индейка",
    "turkey drumstick": "голень индейки",
    "retail parts": "кулинарные отрубы/части тушки",
    "lamb": "баранина",
    "veal": "телятина",
    "duck": "утка",
    "fish": "рыба",
    "salmon": "лосось",
    "tuna": "тунец",
    "cod": "треска",
    "shrimp": "креветки",
    "potatoes": "картофель",
    "potato": "картофель",
    "apples": "яблоки",
    "apple": "яблоко",
    "milk": "молоко",
    "cheese": "сыр",
    "egg": "яйцо",
    "eggs": "яйца",
    "bread": "хлеб",
    "rice": "рис",
    "butter": "сливочное масло",
    "oil": "растительное масло",
    "water": "вода",
    "juice": "сок",
    "tea": "чай",
    "coffee": "кофе",
    "tomatoes": "помидоры (томаты)",
    "tomato": "помидоры (томаты)",
    "carrots": "морковь",
    "carrot": "морковь",
    "onions": "лук",
    "onion": "лук",
    "garlic": "чеснок",
    "cabbage": "капуста",
    "spinach": "шпинат",
    "broccoli": "брокколи",
    "beans": "фасоль",
    "peas": "горох",
    "corn": "кукуруза",
    "mushrooms": "грибы",
    "mushroom": "грибы",
}

# Portion Measure Units Translated to Russian
MEASURE_UNITS_RU: dict[str, str] = {
    "cup": "стакан",
    "fl oz": "жидк. унция (~30 мл)",
    "tbsp": "ст. л.",
    "tablespoon": "ст. л.",
    "tsp": "ч. л.",
    "teaspoon": "ч. л.",
    "slice": "ломтик",
    "piece": "шт",
    "medium": "средний (1 шт)",
    "small": "малый (1 шт)",
    "large": "крупный (1 шт)",
    "extra large": "очень крупный (1 шт)",
    "container": "упаковка",
    "bottle": "бутылка",
    "can": "банка",
    "packet": "пакетик",
    "bar": "батончик",
    "patty": "котлета",
    "link": "сосиска",
    "portion": "порция",
    "serving": "порция",
    "fillet": "филе",
    "waffle, square": "вафля квадратная (1 шт)",
    "Quantity not specified": "Стандартная порция",
}

# Synonyms dictionary for Russian culinary keywords
RUSSIAN_SYNONYMS_EXPANSIONS: dict[str, list[str]] = {
    "картофель": ["картошка", "картофельный", "клубни"],
    "картошка": ["картофель", "картофельный"],
    "батат": ["сладкий картофель"],
    "помидор": ["томат", "томаты", "помидоры"],
    "томат": ["помидор", "помидоры", "томаты"],
    "свекла": ["буряк", "свеколка"],
    "курица": ["цыпленок", "курятина", "куриное мясо", "куриная грудка"],
    "цыпленок": ["курица", "курятина"],
    "говядина": ["мясо говядины", "говяжий", "телятина"],
    "свинина": ["мясо свинины", "свиной"],
    "индейка": ["индюшатина", "филе индейки"],
    "яйцо": ["яйца", "яйцо куриное", "яйца куриные"],
    "овсянка": ["геркулес", "овсяные хлопья", "овсяная каша", "овес"],
    "гречка": ["гречневая крупа", "гречневая каша", "гречиха"],
    "рис": ["рисовая крупа", "рис белый", "рисовая каша"],
    "творог": ["творожок", "домашний творог"],
    "сметана": ["сметанка"],
    "пахта": ["маслянка"],
    "сыр": ["сыры", "твердый сыр"],
    "масло": ["маслице"],
    "сливочное масло": ["масло сливочное", "маслице"],
    "подсолнечное масло": ["растительное масло", "масло подсолнечное"],
    "оливковое масло": ["масло оливковое", "растительное масло"],
    "макароны": ["паста", "спагетти", "рожки", "вермишель"],
    "хлеб": ["батон", "хлебушек", "булка"],
    "лосось": ["семга", "форель", "красная рыба"],
    "тунец": ["рыба тунец", "тунец в собственном соку"],
    "треска": ["филе трески"],
    "минтай": ["филе минтая"],
    "яблоко": ["яблоки", "яблочко"],
    "банан": ["бананы"],
    "апельсин": ["апельсины"],
    "лимон": ["лимоны"],
    "морковь": ["морковка"],
    "капуста": ["капуста белокочанная"],
    "лук": ["лучок", "лук репчатый"],
    "чеснок": ["чесночок"],
    "огурец": ["огурцы", "огурчик"],
    "сахар": ["сахар-песок", "сахарок"],
    "мед": ["медок", "пчелиный мед"],
    "чай": ["чаек"],
    "кофе": ["кофеек", "эспрессо"],
}


class TranslationEngine:
    """Manages bilingual translation, caching, search normalization, and synonym generation."""

    def __init__(self, cache_file: Path | None = None, db_cache: Path | None = None) -> None:
        self.cache_file = cache_file or TRANSLATION_CACHE_PATH
        self.db_cache = db_cache or TRANSLATIONS_CACHE_DB
        self.cache: dict[str, str] = {}
        self.load_all_caches()
        self._argos_translation = None
        self._argos_initialized = False

    def load_all_caches(self) -> None:
        """Load translations from SQLite cache and JSON file."""
        # 1. Load SQLite cache (pre-translated 8,028 SR Legacy & Foundation items)
        if self.db_cache.is_file():
            try:
                conn = sqlite3.connect(str(self.db_cache))
                cur = conn.cursor()
                cur.execute("SELECT source_en, translated_ru FROM translations")
                for src, tr in cur.fetchall():
                    if src and tr:
                        self.cache[src] = tr
                conn.close()
                logger.info("Loaded %d translations from SQLite cache %s", len(self.cache), self.db_cache.name)
            except Exception as e:
                logger.warning("Could not read SQLite translation cache: %s", e)

        # 2. Load JSON cache
        if self.cache_file.is_file():
            try:
                with self.cache_file.open("r", encoding="utf-8") as f:
                    data = json.load(f)
                    self.cache.update(data)
                logger.info("Total cache size after JSON load: %d items", len(self.cache))
            except Exception as e:
                logger.warning("Could not read JSON translation cache: %s", e)

    def save_cache(self) -> None:
        """Save translation cache to JSON."""
        try:
            self.cache_file.parent.mkdir(parents=True, exist_ok=True)
            with self.cache_file.open("w", encoding="utf-8") as f:
                json.dump(self.cache, f, ensure_ascii=False, indent=2)
            logger.info("Saved %d translations to %s", len(self.cache), self.cache_file)
        except Exception as e:
            logger.warning("Could not save translation cache: %s", e)

    def post_process_russian(self, en: str, ru: str) -> str:
        """Apply targeted culinary corrections to clean up machine translation artifacts."""
        res = ru
        en_lower = en.lower()

        # Audit D01-D02: apply to cached translations too, before generic poultry rules.
        if "turkey" in en_lower:
            res = re.sub(r"\bбарабанная\s+палочка\s+турция\b", "Голень индейки", res, flags=re.I)
            res = re.sub(r"\bтурция\b", "индейка", res, flags=re.I)
        if "retail parts" in en_lower:
            res = re.sub(r"запчасти для розничной торговли", "кулинарные отрубы/части тушки", res, flags=re.I)
        if re.search(r"\bfish,\s*drum\b", en_lower):
            res = re.sub(r"рыба,\s*(?:голень|барабан|drum)\b", "Рыба семейства горбылевых (горбыль)", res, flags=re.I)

        # 1. Produce / Plant-based corrections (flesh -> мякоть, skin -> кожура)
        is_produce = any(
            k in en_lower
            for k in ["potato", "apple", "peach", "pear", "tomato", "fruit", "vegetable", "squash", "eggplant"]
        )
        if is_produce:
            res = re.sub(r"\bмясо и кожа\b", "мякоть и кожура", res, flags=re.I)
            res = re.sub(r"\bмякоть и мясо\b", "мякоть", res, flags=re.I)
            res = re.sub(r"\bтолько мясо\b", "только мякоть", res, flags=re.I)
            res = re.sub(r"\bмясо\b", "мякоть", res, flags=re.I)
            res = re.sub(r"\bплоть\b", "мякоть", res, flags=re.I)
            res = re.sub(r"\bкожа\b", "кожура", res, flags=re.I)
            res = re.sub(r"\bкожи\b", "кожуры", res, flags=re.I)

        # 2. Potatoes / French Fries / Hashbrowns
        if "potato" in en_lower:
            res = re.sub(r"\bжареный на французском(?: языке)?\b", "картофель фри", res, flags=re.I)
            res = re.sub(r"\bжареная на французском(?: языке)?\b", "картофель фри", res, flags=re.I)
            res = re.sub(r"\bжареное на французском(?: языке)?\b", "картофель фри", res, flags=re.I)
            res = re.sub(r"\bхеш-коричневый\b", "хашбраун (драники)", res, flags=re.I)
            res = re.sub(r"\bкартофельный пух\b", "картофельные крокеты", res, flags=re.I)

        # 3. Sweet potato / Батат
        if "sweet potato" in en_lower:
            res = re.sub(r"\bсладкий картофель\b", "батат (сладкий картофель)", res, flags=re.I)
            res = re.sub(r"\bсладкого картофеля\b", "батата (сладкого картофеля)", res, flags=re.I)
            res = re.sub(r"\bсладкий картофельный\b", "бататный", res, flags=re.I)

        # 4. Poultry giblets and cuts (drumstick -> голень, giblets -> потроха)
        if any(k in en_lower for k in ["chicken", "turkey", "poultry", "duck", "goose", "emu"]):
            res = re.sub(r"\bперчатки\b", "потроха", res, flags=re.I)
            res = re.sub(r"\bкуриный мягкий блюдо\b", "куриные стрипсы", res, flags=re.I)
            res = re.sub(r"\bкуриный тендерлоин\b", "куриное филе (стрипсы)", res, flags=re.I)
            res = re.sub(r"\bбарабанн\w*\s*палочк\w*\b", "голень", res, flags=re.I)
            res = re.sub(r"\bбарабан[ыаеуомв]*\b", "голени", res, flags=re.I)
            res = re.sub(r"\bбарабан\b", "голень", res, flags=re.I)

        # Snap beans / String beans
        res = re.sub(r"\bбобы,?\s*окунь\b", "стручковая фасоль", res, flags=re.I)
        res = re.sub(r"\bокунь\s*бобы\b", "стручковая фасоль", res, flags=re.I)

        # Navel oranges
        res = re.sub(r"\bсырые пупки\b", "апельсины Навел, сырые", res, flags=re.I)
        res = re.sub(r"\bпупки\b", "апельсины Навел", res, flags=re.I)

        # 5. Meat loaf & crumbled meat
        if any(k in en_lower for k in ["beef", "pork", "meat", "lamb", "veal"]):
            res = re.sub(r"\bбуханка\b", "мясной рулет", res, flags=re.I)
            res = re.sub(r"\bкрошится\b", "обжаренный фарш", res, flags=re.I)

        # 6. Dairy & buttermilk corrections
        res = re.sub(r"\bпахотный\b", "пахта", res, flags=re.I)
        res = re.sub(r"\bПахотный\b", "Пахта", res)
        res = re.sub(r"\bкозел молоко\b", "козье молоко", res, flags=re.I)
        res = re.sub(r"\bКозел молоко\b", "Козье молоко", res)
        res = re.sub(r"\bжирный свободный\b", "обезжиренный", res, flags=re.I)
        res = re.sub(r"\bлактоза свободный\b", "безлактозный", res, flags=re.I)
        res = re.sub(r"\bиспаряющийся\b", "концентрированное", res, flags=re.I)
        res = re.sub(r"\bсоевый молоко\b", "соевое молоко", res, flags=re.I)
        res = re.sub(r"\bСоевый молоко\b", "Соевое молоко", res)
        res = re.sub(r"\bминдаль молоко\b", "миндальное молоко", res, flags=re.I)
        res = re.sub(r"\bМиндаль молоко\b", "Миндальное молоко", res)
        res = re.sub(r"\bкислый крем\b", "сметана", res, flags=re.I)
        res = re.sub(r"\bхлопковый сыр\b", "творог", res, flags=re.I)
        res = re.sub(r"\bкоттеджный сыр\b", "творог", res, flags=re.I)

        # 7. Bakery: icing, unbaked, deep dish
        res = re.sub(r"\bс ледяным\b", "с глазурью", res, flags=re.I)
        res = re.sub(r"\bледяной\b", "глазурь", res, flags=re.I)
        res = re.sub(r"\bнеобожженный\b", "сырой / невыпеченный", res, flags=re.I)
        res = re.sub(r"\bглубокое блюдо\b", "глубокая форма", res, flags=re.I)

        # 8. Restaurant menu artifacts
        if "restaurant" in en_lower:
            res = re.sub(r"\bвход\b", "основное блюдо", res, flags=re.I)
            res = re.sub(r"\bоранжевый курица\b", "курица в апельсиновом соусе", res, flags=re.I)

        # 9. Duplicate percentage indicators like (2%) (2%)
        res = re.sub(r"\(2%\)\s*\(2%\)", "(2%)", res)
        res = re.sub(r"\(1%\)\s*\(1%\)", "(1%)", res)
        res = re.sub(r"\(0%\)\s*\(0%\)", "(0%)", res)

        # 10. General whitespace and punctuation cleanup
        res = re.sub(r"\s+", " ", res).strip(" ,;:")
        if res:
            res = res[0].upper() + res[1:]
        return res

    def translate_segment(self, segment: str) -> str:
        """Translate a single culinary segment or term."""
        s = segment.strip()
        if not s:
            return ""
        s_low = s.lower()
        if s_low in CULINARY_TERMS:
            return CULINARY_TERMS[s_low]
        if s in self.cache:
            return self.cache[s]
        # Match dictionary phrases and terms
        res = s
        for k, v in sorted(CULINARY_TERMS.items(), key=lambda x: len(x[0]), reverse=True):
            res = re.sub(rf"\b{re.escape(k)}\b", v, res, flags=re.I)
        return res

    def translate_food_description(self, description_en: str, category_en: str = "") -> str:
        """Translate full USDA food description into a natural, grammatical Russian title."""
        desc = description_en.strip()
        if not desc:
            return ""

        # Check cache
        if desc in self.cache:
            raw_ru = self.cache[desc]
            return self.post_process_russian(desc, raw_ru)

        # Segment-by-segment dictionary matching
        segments = [s.strip() for s in desc.split(",") if s.strip()]
        translated_segments = [self.translate_segment(s) for s in segments if s]

        raw_ru = ", ".join(translated_segments)
        cleaned = self.post_process_russian(desc, raw_ru)
        self.cache[desc] = cleaned
        return cleaned

    def translate_category(self, category_en: str) -> str:
        """Translate USDA food category into Russian."""
        clean = category_en.strip()
        if clean in USDA_CATEGORIES_RU:
            return USDA_CATEGORIES_RU[clean]
        if clean in WWEIA_CATEGORIES_RU:
            return WWEIA_CATEGORIES_RU[clean]
        return clean

    def translate_measure_description(self, measure_desc: str) -> str:
        """Translate portion or measure description into Russian."""
        raw = measure_desc.strip()
        if not raw:
            return "1 порция"

        if raw in MEASURE_UNITS_RU:
            return MEASURE_UNITS_RU[raw]

        translated = raw
        for unit_en, unit_ru in sorted(MEASURE_UNITS_RU.items(), key=lambda x: len(x[0]), reverse=True):
            pattern = re.compile(rf"\b{re.escape(unit_en)}\b", re.IGNORECASE)
            translated = pattern.sub(unit_ru, translated)

        return translated.strip()


def normalize_for_search(text: str) -> str:
    """Normalize text for offline SQLite search and FTS5.

    - Converts to lowercase
    - Normalizes ё -> е
    - Replaces punctuation/symbols with spaces
    - Collapses multiple whitespace to single space
    """
    if not text:
        return ""
    t = text.lower().replace("ё", "е")
    # Replace anything non-alphanumeric (Russian, English, digits) with space
    t = re.sub(r"[^a-zа-я0-9\s]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t


def generate_synonyms(name_ru: str, name_en: str, category_ru: str = "") -> list[str]:
    """Generate search synonyms for a food product.

    Includes:
      - Original English description (so user can search in English)
      - Russian culinary colloquialisms & alternate names
      - Inverted word variations (e.g. 'Молоко цельное' <-> 'Цельное молоко')
      - Category name in Russian
    """
    synonyms: set[str] = set()
    name_ru = re.sub(r"\bбарабанн\w*\s+палочк\w*\b", "голень", name_ru, flags=re.I)
    name_ru = re.sub(r"\bбарабанн\w*\s+палочка\s+турция\b", "Голень индейки", name_ru, flags=re.I)
    if "turkey" in name_en.lower() and "drumstick" in name_en.lower():
        synonyms.add("Голень индейки")

    # Always include the original English name
    if name_en:
        synonyms.add(name_en.strip())

    # Add category in Russian if informative
    if category_ru and category_ru not in ("Разное (вне категорий)", "Не уточнено"):
        synonyms.add(category_ru)

    norm_ru = normalize_for_search(name_ru)
    words = norm_ru.split()

    # Keyword expansions
    for word in words:
        if word in RUSSIAN_SYNONYMS_EXPANSIONS:
            for exp in RUSSIAN_SYNONYMS_EXPANSIONS[word]:
                synonyms.add(exp)

    # Invert two-word phrases like 'молоко цельное' -> 'цельное молоко'
    if len(words) == 2:
        inverted = f"{words[1]} {words[0]}"
        synonyms.add(inverted)
    elif len(words) >= 3 and "," in name_ru:
        parts = [p.strip() for p in name_ru.split(",") if p.strip()]
        if len(parts) >= 2:
            p0 = parts[0].strip()
            p1 = parts[1].strip()
            if not re.search(r"\d", p1) and len(p1) > 2 and len(p0) > 2:
                alt = f"{p1.lower()} {p0.lower()}".capitalize()
                synonyms.add(alt)

    clean_synonyms = []
    for s in synonyms:
        s_clean = s.strip()
        if not s_clean or s_clean == name_ru:
            continue
        s_clean = re.sub(r"\bбарабанн\w*\s+палоч\w*", "голень", s_clean, flags=re.I)
        s_clean = re.sub(r"\bтурци\w*", "индейка", s_clean, flags=re.I)
        s_clean = re.sub(r"\bбобы,\s*окунь", "стручковая фасоль", s_clean, flags=re.I)
        clean_synonyms.append(s_clean)
    return sorted(clean_synonyms, key=lambda s: (len(s), s))

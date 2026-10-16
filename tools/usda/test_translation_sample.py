import csv
import re
import sys
import time

sys.stdout.reconfigure(encoding='utf-8')

import argostranslate.translate
import ctranslate2

# Pre-translation regex replacements (English cleanup)
CLEAN_EN_PATTERNS = [
    (r'\bNFS\b', ''),
    (r'\bNFSMI Recipe No\.[^,]+', ''),
    (r',?\s*broilers or fryers', ''),
    (r',?\s*broiler or fryers', ''),
    (r'\bUPC\s*\d+\b', ''),
    (r'trimmed to 1/8" fat', 'trimmed 1/8" fat'),
    (r'trimmed to 1/4" fat', 'trimmed 1/4" fat'),
    (r'trimmed to 0" fat', 'trimmed 0" fat'),
]

# Meat / primary food inversion mappings
INVERSION_MAP = [
    (re.compile(r'^Beef,\s*ground,?', re.I), 'Ground beef,'),
    (re.compile(r'^Pork,\s*ground,?', re.I), 'Ground pork,'),
    (re.compile(r'^Turkey,\s*ground,?', re.I), 'Ground turkey,'),
    (re.compile(r'^Chicken,\s*ground,?', re.I), 'Ground chicken,'),
    (re.compile(r'^Lamb,\s*ground,?', re.I), 'Ground lamb,'),
    (re.compile(r'^Veal,\s*ground,?', re.I), 'Ground veal,'),
    (re.compile(r'^Cheese,\s*cottage,?', re.I), 'Cottage cheese,'),
    (re.compile(r'^Cheese,\s*cream,?', re.I), 'Cream cheese,'),
    (re.compile(r'^Cheese,\s*mozzarella,?', re.I), 'Mozzarella cheese,'),
    (re.compile(r'^Cheese,\s*cheddar,?', re.I), 'Cheddar cheese,'),
    (re.compile(r'^Cheese,\s*parmesan,?', re.I), 'Parmesan cheese,'),
    (re.compile(r'^Cheese,\s*feta,?', re.I), 'Feta cheese,'),
    (re.compile(r'^Cheese,\s*ricotta,?', re.I), 'Ricotta cheese,'),
    (re.compile(r'^Cheese,\s*swiss,?', re.I), 'Swiss cheese,'),
    (re.compile(r'^Cheese,\s*blue,?', re.I), 'Blue cheese,'),
    (re.compile(r'^Cheese,\s*provolone,?', re.I), 'Provolone cheese,'),
    (re.compile(r'^Cheese,\s*gouda,?', re.I), 'Gouda cheese,'),
    (re.compile(r'^Cheese,\s*brie,?', re.I), 'Brie cheese,'),
    (re.compile(r'^Milk,\s*whole,?', re.I), 'Whole milk,'),
    (re.compile(r'^Milk,\s*reduced fat,?', re.I), 'Reduced fat milk,'),
    (re.compile(r'^Milk,\s*lowfat,?', re.I), 'Low fat milk,'),
    (re.compile(r'^Milk,\s*nonfat,?', re.I), 'Skim milk,'),
    (re.compile(r'^Butter,\s*without salt,?', re.I), 'Unsalted butter,'),
    (re.compile(r'^Butter,\s*with salt,?', re.I), 'Salted butter,'),
    (re.compile(r'^Oil,\s*olive,?', re.I), 'Olive oil,'),
    (re.compile(r'^Oil,\s*sunflower,?', re.I), 'Sunflower oil,'),
    (re.compile(r'^Oil,\s*canola,?', re.I), 'Canola oil,'),
    (re.compile(r'^Oil,\s*corn,?', re.I), 'Corn oil,'),
    (re.compile(r'^Oil,\s*soybean,?', re.I), 'Soybean oil,'),
    (re.compile(r'^Oil,\s*coconut,?', re.I), 'Coconut oil,'),
    (re.compile(r'^Fish,\s*salmon,?', re.I), 'Salmon fish,'),
    (re.compile(r'^Fish,\s*tuna,?', re.I), 'Tuna fish,'),
    (re.compile(r'^Fish,\s*cod,?', re.I), 'Cod fish,'),
    (re.compile(r'^Fish,\s*trout,?', re.I), 'Trout fish,'),
    (re.compile(r'^Fish,\s*halibut,?', re.I), 'Halibut fish,'),
]

def clean_english_name(name: str) -> str:
    cleaned = name.strip()
    for pattern, repl in CLEAN_EN_PATTERNS:
        cleaned = re.sub(pattern, repl, cleaned)
    for regex, repl in INVERSION_MAP:
        if regex.search(cleaned):
            cleaned = regex.sub(repl, cleaned)
            break
    # normalize spaces and commas
    cleaned = re.sub(r'\s*,\s*', ', ', cleaned)
    cleaned = re.sub(r'\s+', ' ', cleaned).strip(' ,')
    return cleaned

# Post-translation Russian cleanup patterns
POST_RU_REPLACEMENTS = [
    (re.compile(r'\bХлопковый сыр\b', re.I), 'Творог'),
    (re.compile(r'\bхлопкового сыра\b', re.I), 'творога'),
    (re.compile(r'\bкоттеджный сыр\b', re.I), 'творог'),
    (re.compile(r'\bКоттеджный сыр\b', re.I), 'Творог'),
    (re.compile(r'\bмясная говядина\b', re.I), 'говяжий фарш'),
    (re.compile(r'\bМясная говядина\b', re.I), 'Говяжий фарш'),
    (re.compile(r'\bГовядина, земля\b', re.I), 'Говяжий фарш'),
    (re.compile(r'\bговядина, земля\b', re.I), 'говяжий фарш'),
    (re.compile(r'\bСвинина, земля\b', re.I), 'Свиной фарш'),
    (re.compile(r'\bИндейка, земля\b', re.I), 'Фарш из индейки'),
    (re.compile(r'\bКурица, земля\b', re.I), 'Куриный фарш'),
    (re.compile(r'\bс кожей\b', re.I), 'с кожурой'),
    (re.compile(r'\bбез кожи\b', re.I), 'без кожуры'),
    (re.compile(r'\bтолько мясо\b', re.I), 'только мякоть'),
    (re.compile(r'\bсырое\b', re.I), 'сырой'),
    (re.compile(r'\bготовый к употреблению\b', re.I), 'готовый к употреблению'),
    (re.compile(r'\bДетское питание\b', re.I), 'Детское питание'),
    (re.compile(r'\s*,\s*', re.I), ', '),
    (re.compile(r'\s+', re.I), ' '),
]

def clean_russian_name(name: str, category: str = '') -> str:
    cleaned = name.strip()
    for regex, repl in POST_RU_REPLACEMENTS:
        cleaned = regex.sub(repl, cleaned)
    cleaned = cleaned.strip(' ,')
    if cleaned:
        cleaned = cleaned[0].upper() + cleaned[1:]
    return cleaned

print('Setup complete.')

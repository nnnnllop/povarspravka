import csv
import json
import os
import re
import sqlite3
import sys

# Ensure UTF-8 output
sys.stdout.reconfigure(encoding='utf-8')

JSON_PATH = os.path.join("data", "usda", "products_usda.json")
CSV_PATH = os.path.join("data", "usda", "products_usda.csv")
DB_PATH = os.path.join("tools", "usda", "cache", "translations_cache.db")

# Targeted culinary cleanup regexes
POLISH_RULES = [
    # Mince & meat terms
    (re.compile(r'\bговядина\s+наземная\b', re.I), 'говяжий фарш'),
    (re.compile(r'\bГовядина\s+наземная\b', re.I), 'Говяжий фарш'),
    (re.compile(r'\bсвинина\s+наземная\b', re.I), 'свиной фарш'),
    (re.compile(r'\bСвинина\s+наземная\b', re.I), 'Свиной фарш'),
    (re.compile(r'\bкурица\s+наземная\b', re.I), 'куриный фарш'),
    (re.compile(r'\bКурица\s+наземная\b', re.I), 'Куриный фарш'),
    (re.compile(r'\bиндейка\s+наземная\b', re.I), 'фарш из индейки'),
    (re.compile(r'\bИндейка\s+наземная\b', re.I), 'Фарш из индейки'),
    (re.compile(r'\bназемная\s+говядина\b', re.I), 'говяжий фарш'),
    (re.compile(r'\bНаземная\s+говядина\b', re.I), 'Говяжий фарш'),
    (re.compile(r',\s*земля,\s*', re.I), ', фарш, '),
    (re.compile(r'\bземля,\s*сырой\b', re.I), 'фарш, сырой'),
    (re.compile(r'\bземля,\s*приготовленн', re.I), 'фарш, приготовленн'),

    # Ground squirrel fix
    (re.compile(r'\bБелка,\s*земля,\s*мясо\b', re.I), 'Суслик, мясо'),

    # Pitted (without stones / pits)
    (re.compile(r'\bпит-стопы\b', re.I), 'без косточек'),
    (re.compile(r'\bс питами\b', re.I), 'без косточек'),
    (re.compile(r'\bпитted\b', re.I), 'без косточек'),

    # Culinary terms
    (re.compile(r'\bхлопчатобумажн\w+\s+выпечк\w+', re.I), 'слоёной выпечки'),
    (re.compile(r'\bукорочение\b', re.I), 'кулинарный жир'),
    (re.compile(r'\bУкорочение\b', re.I), 'Кулинарный жир'),
    (re.compile(r'\bМаргарин-подобное укорочение\b', re.I), 'Кондитерский жир (аналог маргарина)'),
    (re.compile(r'\bнеподготовленн\w+\b', re.I), 'в сухом виде'),
    (re.compile(r'\bНеподготовленн\w+\b', re.I), 'В сухом виде'),
    (re.compile(r'\bпан-бройлированн\w+\b', re.I), 'обжаренный на сковороде'),
    (re.compile(r'\bпанкошеный\b', re.I), 'обжаренный на сковороде'),
    (re.compile(r'\bпятнистый,\s*приготовленный\b', re.I), 'котлета, приготовленная'),

    # Seafood & crustacean fixes
    (re.compile(r'^Корица,\s*(колючий омар|омар|краб|кревет)', re.I), r'Ракообразные, \1'),
    (re.compile(r'^Корица,\s*', re.I), 'Ракообразные, '),

    # Skin fixes
    (re.compile(r'\bс кожей\b', re.I), 'с кожурой'),
    (re.compile(r'\bбез кожи\b', re.I), 'без кожуры'),
    (re.compile(r'\bмясо и кожа\b', re.I), 'мякоть и кожура'),

    # Punctuation & spaces
    (re.compile(r'\s*;\s*', re.I), ', '),
    (re.compile(r'\s*,\s*', re.I), ', '),
    (re.compile(r',\s*,+', re.I), ','),
    (re.compile(r'\s+', re.I), ' '),
]

def polish_text(ru_text: str, en_text: str = '') -> str:
    cleaned = ru_text.strip()
    for regex, repl in POLISH_RULES:
        cleaned = regex.sub(repl, cleaned)
    cleaned = cleaned.strip(' ,;:')
    if cleaned:
        cleaned = cleaned[0].upper() + cleaned[1:]
    return cleaned

def main():
    print("Polishing translations...")
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    changes = 0
    updated_records = []
    db_updates = []

    for item in data:
        orig_ru = item["name_ru"]
        polished_ru = polish_text(orig_ru, item.get("name_en", ""))
        if polished_ru != orig_ru:
            changes += 1
            item["name_ru"] = polished_ru
            db_updates.append((polished_ru, item["name_en"]))
        updated_records.append(item)

    print(f"Applied polish to {changes} records.")

    # Save JSON
    with open(JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(updated_records, f, ensure_ascii=False, indent=2)
    print(f"Saved updated JSON ({os.path.getsize(JSON_PATH) / 1024 / 1024:.2f} MB).")

    # Save CSV
    fieldnames = ["fdc_id", "name_ru", "name_en", "category", "kcal", "protein", "fat", "carbs", "water", "fiber"]
    with open(CSV_PATH, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(updated_records)
    print(f"Saved updated CSV ({os.path.getsize(CSV_PATH) / 1024 / 1024:.2f} MB).")

    # Update SQLite cache
    if os.path.exists(DB_PATH) and db_updates:
        conn = sqlite3.connect(DB_PATH)
        with conn:
            conn.executemany("UPDATE translations SET translated_ru = ? WHERE source_en = ?", db_updates)
        conn.close()
        print(f"Updated {len(db_updates)} records in SQLite cache.")

if __name__ == "__main__":
    main()

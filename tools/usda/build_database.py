import csv
import glob
import json
import os
import sys
import time
from typing import Dict, List, Any

import sys
import os

# Ensure project root is in sys.path
sys.path.insert(0, os.path.abspath("."))
sys.stdout.reconfigure(encoding='utf-8')

from tools.usda.translator import UsdaTranslator

CACHE_DIR = os.path.join("tools", "usda", "cache")
OUTPUT_DIR = os.path.join("data", "usda")
DB_CACHE_PATH = os.path.join(CACHE_DIR, "translations_cache.db")

JSON_OUTPUT_PATH = os.path.join(OUTPUT_DIR, "products_usda.json")
CSV_OUTPUT_PATH = os.path.join(OUTPUT_DIR, "products_usda.csv")

# Nutrient IDs according to USDA FoodData Central
NUTRIENT_PROTEIN = '1003'  # Protein (g)
NUTRIENT_FAT = '1004'      # Total lipid (fat) (g)
NUTRIENT_CARBS = '1005'    # Carbohydrate, by difference (g)
NUTRIENT_KCAL = '1008'     # Energy (kcal)
NUTRIENT_WATER = '1051'    # Water (g)
NUTRIENT_FIBER = '1079'    # Fiber, total dietary (g)


def load_categories(sr_dir: str) -> Dict[str, str]:
    """Loads food categories mapping {category_id: category_name}."""
    cat_map = {}
    path = os.path.join(sr_dir, "food_category.csv")
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            reader = csv.DictReader(f)
            for row in reader:
                cat_map[row["id"]] = row["description"]
    return cat_map


def load_foods_and_nutrients() -> List[Dict[str, Any]]:
    """Loads SR Legacy and Foundation foods with their corresponding nutrients."""
    sr_folders = glob.glob(os.path.join(CACHE_DIR, "sr_legacy", "*"))
    foundation_folders = glob.glob(os.path.join(CACHE_DIR, "foundation", "*"))

    sr_dir = [f for f in sr_folders if os.path.isdir(f)][0]
    foundation_dir = [f for f in foundation_folders if os.path.isdir(f)][0]

    cat_map = load_categories(sr_dir)
    foods_dict = {}

    # 1. Load SR Legacy foods (all 7793 items)
    sr_food_path = os.path.join(sr_dir, "food.csv")
    print(f"Loading SR Legacy foods from {sr_food_path}...")
    with open(sr_food_path, "r", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            fdc_id = int(row["fdc_id"])
            cat_id = row.get("food_category_id", "")
            foods_dict[fdc_id] = {
                "fdc_id": fdc_id,
                "name_en": row["description"].strip(),
                "category": cat_map.get(cat_id, "Standard Food Products"),
                "source": "SR Legacy",
                "protein": 0.0,
                "fat": 0.0,
                "carbs": 0.0,
                "kcal": 0.0,
                "water": 0.0,
                "fiber": 0.0,
                "has_explicit_kcal": False,
            }
    print(f"  Loaded {len(foods_dict)} SR Legacy items.")

    # 2. Load Foundation foods (only foundation_food data_type, ~387 items)
    foundation_food_path = os.path.join(foundation_dir, "food.csv")
    print(f"Loading Foundation foods from {foundation_food_path}...")
    ff_count = 0
    with open(foundation_food_path, "r", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("data_type") == "foundation_food":
                fdc_id = int(row["fdc_id"])
                cat_id = row.get("food_category_id", "")
                foods_dict[fdc_id] = {
                    "fdc_id": fdc_id,
                    "name_en": row["description"].strip(),
                    "category": cat_map.get(cat_id, "Foundation Foods"),
                    "source": "Foundation",
                    "protein": 0.0,
                    "fat": 0.0,
                    "carbs": 0.0,
                    "kcal": 0.0,
                    "water": 0.0,
                    "fiber": 0.0,
                    "has_explicit_kcal": False,
                }
                ff_count += 1
    print(f"  Loaded {ff_count} Foundation items. Total unique foods: {len(foods_dict)}.")

    # 3. Load nutrients for SR Legacy
    sr_nut_path = os.path.join(sr_dir, "food_nutrient.csv")
    print(f"Loading SR Legacy nutrients from {sr_nut_path}...")
    with open(sr_nut_path, "r", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            fdc_id = int(row["fdc_id"])
            if fdc_id in foods_dict:
                nid = row["nutrient_id"]
                val = float(row["amount"]) if row["amount"] else 0.0
                val = max(0.0, val)
                if nid == NUTRIENT_PROTEIN:
                    foods_dict[fdc_id]["protein"] = val
                elif nid == NUTRIENT_FAT:
                    foods_dict[fdc_id]["fat"] = val
                elif nid == NUTRIENT_CARBS:
                    foods_dict[fdc_id]["carbs"] = val
                elif nid == NUTRIENT_KCAL:
                    foods_dict[fdc_id]["kcal"] = val
                    foods_dict[fdc_id]["has_explicit_kcal"] = True
                elif nid == NUTRIENT_WATER:
                    foods_dict[fdc_id]["water"] = val
                elif nid == NUTRIENT_FIBER:
                    foods_dict[fdc_id]["fiber"] = val

    # 4. Load nutrients for Foundation foods
    ff_nut_path = os.path.join(foundation_dir, "food_nutrient.csv")
    print(f"Loading Foundation nutrients from {ff_nut_path}...")
    with open(ff_nut_path, "r", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            fdc_id = int(row["fdc_id"])
            if fdc_id in foods_dict and foods_dict[fdc_id]["source"] == "Foundation":
                nid = row["nutrient_id"]
                val = float(row["amount"]) if row["amount"] else 0.0
                val = max(0.0, val)
                if nid == NUTRIENT_PROTEIN:
                    foods_dict[fdc_id]["protein"] = val
                elif nid == NUTRIENT_FAT:
                    foods_dict[fdc_id]["fat"] = val
                elif nid == NUTRIENT_CARBS:
                    foods_dict[fdc_id]["carbs"] = val
                elif nid == NUTRIENT_KCAL:
                    foods_dict[fdc_id]["kcal"] = val
                    foods_dict[fdc_id]["has_explicit_kcal"] = True
                elif nid == NUTRIENT_WATER:
                    foods_dict[fdc_id]["water"] = val
                elif nid == NUTRIENT_FIBER:
                    foods_dict[fdc_id]["fiber"] = val

    # 5. Handle missing kcal if not explicitly provided
    computed_kcal_count = 0
    for food in foods_dict.values():
        if not food["has_explicit_kcal"]:
            # Compute Atwater kcal: 4*P + 9*F + 4*C
            computed_kcal = round(food["protein"] * 4.0 + food["fat"] * 9.0 + food["carbs"] * 4.0, 1)
            food["kcal"] = computed_kcal
            computed_kcal_count += 1

    print(f"  Handled kcal (explicitly present: {len(foods_dict) - computed_kcal_count}, computed via Atwater: {computed_kcal_count}).")

    return list(foods_dict.values())


def validate_foods(foods: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Validates nutrient ranges (0..100 g) and macro-energy correlations."""
    print("\nRunning auto-validation...")
    violations = []
    large_deviations = []
    zero_macros_with_kcal = []

    for f in foods:
        fdc_id = f["fdc_id"]
        # Range checks (0..100g)
        for nutrient in ["protein", "fat", "carbs", "water", "fiber"]:
            val = f[nutrient]
            if val < 0.0 or val > 100.0:
                violations.append((fdc_id, nutrient, val, f["name_en"]))

        # Check macro-kcal correlation
        # Expected Atwater = 4*P + 9*F + 4*C
        p, fat, c, kcal = f["protein"], f["fat"], f["carbs"], f["kcal"]
        expected_kcal = 4.0 * p + 9.0 * fat + 4.0 * c
        diff = abs(kcal - expected_kcal)

        # Allow higher difference for alcoholic drinks (alcohol = 7 kcal/g) or non-nutritive sweeteners
        is_alcohol_or_sweetener = "Alcoholic" in f["category"] or "Sweetener" in f["name_en"] or "Beverages" in f["category"]
        if diff > 50.0 and not is_alcohol_or_sweetener:
            large_deviations.append({
                "fdc_id": fdc_id,
                "name_en": f["name_en"],
                "kcal": kcal,
                "expected_kcal": round(expected_kcal, 1),
                "diff": round(diff, 1)
            })

    print(f"  Range violations (0..100g): {len(violations)}")
    print(f"  Foods checked: {len(foods)}")
    print(f"  Average deviation |kcal - (4P+9F+4C)|: {sum(abs(f['kcal'] - (4*f['protein'] + 9*f['fat'] + 4*f['carbs'])) for f in foods) / len(foods):.2f} kcal")

    return {
        "violations": violations,
        "large_deviations": large_deviations,
    }


def main():
    t_start = time.time()
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)

    print("=" * 60)
    print("USDA FoodData Central Parser, Translator & Normalizer")
    print("=" * 60)

    # 1. Load Foods and Nutrients
    foods = load_foods_and_nutrients()

    # 2. Validate Nutrients
    validation_res = validate_foods(foods)

    # 3. Translation
    print("\nStarting Translation to Russian...")
    translator = UsdaTranslator(DB_CACHE_PATH)
    all_names_en = [f["name_en"] for f in foods]
    translations_map = translator.translate_batch(all_names_en, batch_size=128)

    # Attach translated names & format fields
    final_records = []
    category_counts = {}

    for f in foods:
        orig_en = f["name_en"]
        name_ru = translations_map.get(orig_en, orig_en)

        cat = f["category"]
        category_counts[cat] = category_counts.get(cat, 0) + 1

        record = {
            "fdc_id": f["fdc_id"],
            "name_ru": name_ru,
            "name_en": orig_en,
            "category": cat,
            "kcal": round(float(f["kcal"]), 1),
            "protein": round(float(f["protein"]), 2),
            "fat": round(float(f["fat"]), 2),
            "carbs": round(float(f["carbs"]), 2),
            "water": round(float(f["water"]), 2),
            "fiber": round(float(f["fiber"]), 2),
        }
        final_records.append(record)

    # Sort deterministically by category and name_ru
    final_records.sort(key=lambda x: (x["category"], x["name_ru"]))

    # 4. Save to JSON
    print(f"\nSaving JSON to {JSON_OUTPUT_PATH}...")
    with open(JSON_OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(final_records, f, ensure_ascii=False, indent=2)
    print(f"  Saved {len(final_records)} records ({os.path.getsize(JSON_OUTPUT_PATH) / 1024 / 1024:.2f} MB).")

    # 5. Save to CSV
    print(f"\nSaving CSV to {CSV_OUTPUT_PATH}...")
    fieldnames = ["fdc_id", "name_ru", "name_en", "category", "kcal", "protein", "fat", "carbs", "water", "fiber"]
    with open(CSV_OUTPUT_PATH, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(final_records)
    print(f"  Saved {len(final_records)} records ({os.path.getsize(CSV_OUTPUT_PATH) / 1024 / 1024:.2f} MB).")

    translator.cache.close()
    elapsed = time.time() - t_start
    print(f"\nPipeline successfully completed in {elapsed:.1f}s ({elapsed / 60:.2f} min)!")

    # Print summary statistics
    print("\n=== SUMMARY STATISTICS ===")
    print(f"Total foods processed: {len(final_records)}")
    print(f"Categories ({len(category_counts)}):")
    for cat, count in sorted(category_counts.items(), key=lambda x: x[1], reverse=True):
        print(f"  - {cat}: {count} items")

    print("\nSample translated records (first 10):")
    for r in final_records[:10]:
        print(f"  [{r['fdc_id']}] {r['name_ru']} | EN: {r['name_en']}")
        print(f"      КБЖУ на 100г: {r['kcal']} ккал | Б: {r['protein']}г | Ж: {r['fat']}г | У: {r['carbs']}г | Вода: {r['water']}г | Клетчатка: {r['fiber']}г")


if __name__ == "__main__":
    main()

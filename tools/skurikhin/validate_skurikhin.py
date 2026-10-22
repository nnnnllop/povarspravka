import json
import csv
from collections import Counter

JSON_PATH = r"data\skurikhin\products_skurikhin.json"
CSV_PATH = r"data\skurikhin\products_skurikhin.csv"

def main():
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        products = json.load(f)
        
    print(f"=== Skurikhin Dataset Validation Report ===")
    print(f"Total products in JSON: {len(products)}")
    
    # Check CSV
    with open(CSV_PATH, "r", encoding="utf-8-sig") as f:
        reader = list(csv.DictReader(f))
    print(f"Total rows in CSV: {len(reader)}")
    
    # 1. Group statistics
    groups = Counter(p["group"] for p in products)
    print("\n--- Products by Group ---")
    for g, count in groups.most_common():
        print(f"  {g:<50}: {count} products")
        
    # 2. Validation breakdown
    valid_prods = [p for p in products if p["validation"]["is_valid"]]
    invalid_prods = [p for p in products if not p["validation"]["is_valid"]]
    val_rate = len(valid_prods) / len(products) * 100
    print(f"\n--- Validation Summary ---")
    print(f"  Valid:   {len(valid_prods)} ({val_rate:.1f}%)")
    print(f"  Invalid: {len(invalid_prods)} ({100 - val_rate:.1f}%)")
    
    # Breakdown of reasons
    reasons = Counter()
    for p in invalid_prods:
        r = p["validation"]["reason"]
        if "kcal diff" in r:
            reasons["kcal diff (energy calculation discrepancy)"] += 1
        elif "Missing energy" in r:
            reasons["Missing energy kcal"] += 1
        elif "out of range" in r:
            reasons["B, J, U out of range"] += 1
        else:
            reasons[r] += 1
            
    print("\n--- Failure Reasons Breakdown ---")
    for r, count in reasons.most_common():
        print(f"  {r}: {count}")
        
    # Samples of invalid products
    print("\n--- Sample Discrepancies ---")
    for p in invalid_prods[:12]:
        m = p["macronutrients"]
        v = p["validation"]
        t = p["table_id"]
        c = p["code"]
        name = p["name"]
        print(f"  [Table {t}] Code {c}: {name[:30]:<30} | Б={m['protein_g']:4.1f} Ж={m['fat_g']:4.1f} У={m['carbohydrates_g']:4.1f} | ккал={m['energy_kcal']} (расчет={v['kcal_calculated']})")
        
    # 3. Check waste percentage coverage
    with_waste = [p for p in products if p.get("waste_percent") is not None]
    print(f"\n--- Non-edible / Waste Coverage ---")
    print(f"  Products with waste % matched from Appendix 1: {len(with_waste)} ({len(with_waste)/len(products)*100:.1f}%)")
    print("  Samples of matched waste:")
    for p in with_waste[:6]:
        print(f"    {p['name'][:30]:<30} -> отходы: {p['waste_percent']}%")
        
    # 4. Check uniqueness
    codes = [p["code"] for p in products if p["code"]]
    names = [p["name"] for p in products if p["name"]]
    code_counts = Counter(codes)
    dupe_codes = [c for c, cnt in code_counts.items() if cnt > 1]
    print(f"\n--- Duplicate Check ---")
    print(f"  Unique codes: {len(set(codes))} (total codes: {len(codes)})")
    if dupe_codes:
        print(f"  Duplicate codes found ({len(dupe_codes)}): {dupe_codes[:5]}")
    else:
        print("  NO duplicate codes!")

if __name__ == "__main__":
    main()

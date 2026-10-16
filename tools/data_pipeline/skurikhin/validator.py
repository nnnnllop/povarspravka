"""Comprehensive Validator for Skurikhin 2002 dataset.

Performs nutritional physics and chemistry checks:
1. Energy consistency: Atwater formula 4*P + 9*F + 4*C (+ 7*Alc + 3*OA) vs book kcal
2. Mass conservation: Water + Protein + Fat + Carbs + Ash + Organic acids ≈ 100g
3. Range checks: 0 <= macro <= 100g, 0 <= kcal <= 900, 0 <= waste <= 100%
4. Schema & Uniqueness: valid codes, non-empty names, valid group IDs
"""
from typing import Dict, List, Tuple, Any
import json
from pathlib import Path


class SkurikhinValidator:
    def __init__(self, energy_tolerance_pct: float = 15.0, proximate_range: Tuple[float, float] = (85.0, 110.0)):
        self.energy_tolerance_pct = energy_tolerance_pct
        self.proximate_min, self.proximate_max = proximate_range

    def validate_product(self, prod: Dict[str, Any]) -> Tuple[bool, List[str], Dict[str, Any]]:
        """Validate a single product record. Returns (is_valid, warnings, metrics)."""
        warnings = []
        is_fatal = False

        # 1. Schema checks
        code = prod.get("code", "")
        name = prod.get("name", "")
        group_id = prod.get("group_id", 0)

        if not code:
            warnings.append("Missing product code")
            is_fatal = True
        if not name or name.strip() == "":
            warnings.append("Missing product name")
            is_fatal = True
        if not (1 <= group_id <= 12):
            warnings.append(f"Invalid group_id: {group_id}")
            is_fatal = True

        # 2. Value range checks
        prot = prod.get("protein", 0.0)
        fat = prod.get("fat", 0.0)
        carb = prod.get("carbs", 0.0)
        water = prod.get("water", 0.0)
        ash = prod.get("ash", 0.0)
        fiber = prod.get("fiber", 0.0)
        oa = prod.get("organic_acids", 0.0)
        alc = prod.get("alcohol", 0.0)
        kcal = prod.get("kcal", 0.0)
        waste = prod.get("waste_pct")

        for k, v in [("protein", prot), ("fat", fat), ("carbs", carb), ("water", water), ("ash", ash)]:
            if v < 0:
                warnings.append(f"Negative value for {k}: {v}")
                is_fatal = True
            elif v > 100.5:
                warnings.append(f"Value for {k} exceeds 100g: {v}")
                is_fatal = True

        if kcal < 0:
            warnings.append(f"Negative kcal: {kcal}")
            is_fatal = True
        elif kcal > 950:
            warnings.append(f"Implausibly high kcal: {kcal}")

        if waste is not None and not (0 <= waste <= 95):
            warnings.append(f"Invalid waste percentage: {waste}")

        # 3. Energy consistency check (Skurikhin 2002 Atwater formula)
        calc_kcal = 4.0 * prot + 9.0 * fat + 4.0 * carb
        if alc > 0:
            calc_kcal += 7.0 * alc
        if oa > 0:
            calc_kcal += 3.0 * oa

        calc_kcal = round(calc_kcal, 1)
        energy_diff = abs(kcal - calc_kcal)
        energy_diff_pct = (energy_diff / kcal * 100.0) if kcal >= 10.0 else 0.0

        if kcal >= 10.0 and energy_diff_pct > self.energy_tolerance_pct and energy_diff > 15.0:
            warnings.append(f"Energy mismatch: book={kcal} vs calc={calc_kcal} (diff={energy_diff_pct:.1f}%)")

        # 4. Proximate Mass Conservation check (include alcohol for beverages)
        prox_sum = round(water + prot + fat + carb + ash + oa + alc, 1)
        # Note: if fiber was already included in carbs or measured separately
        if not (self.proximate_min <= prox_sum <= self.proximate_max):
            # If not in range, check if adding fiber brings it into range
            if not (self.proximate_min <= prox_sum + fiber <= self.proximate_max):
                warnings.append(f"Proximate mass sum out of expected range: {prox_sum}g (water={water}, P={prot}, F={fat}, C={carb}, ash={ash}, alc={alc})")

        metrics = {
            "calc_kcal": calc_kcal,
            "energy_diff": round(energy_diff, 1),
            "energy_diff_pct": round(energy_diff_pct, 1),
            "proximate_sum": prox_sum,
        }

        return (not is_fatal), warnings, metrics

    def validate_dataset(self, products: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Validate entire dataset and generate summary report."""
        total = len(products)
        passed = 0
        fatal_count = 0
        warning_count = 0
        code_counts: Dict[str, int] = {}
        group_counts: Dict[str, int] = {}
        all_warnings: List[Dict[str, Any]] = []

        energy_diffs = []
        prox_sums = []

        for p in products:
            code = p.get("code", "")
            code_counts[code] = code_counts.get(code, 0) + 1
            grp = p.get("group_name", "Unknown")
            group_counts[grp] = group_counts.get(grp, 0) + 1

            is_valid, warns, metrics = self.validate_product(p)
            energy_diffs.append(metrics["energy_diff_pct"])
            prox_sums.append(metrics["proximate_sum"])

            if not is_valid:
                fatal_count += 1
            else:
                passed += 1

            if warns:
                warning_count += len(warns)
                all_warnings.append({
                    "id": p.get("id"),
                    "code": code,
                    "name": p.get("name"),
                    "warnings": warns,
                    "metrics": metrics
                })

        # Check duplicate codes
        duplicates = [c for c, count in code_counts.items() if count > 1]

        avg_energy_diff = sum(energy_diffs) / total if total > 0 else 0.0
        avg_prox_sum = sum(prox_sums) / total if total > 0 else 0.0

        report = {
            "total_products": total,
            "passed_products": passed,
            "pass_rate_pct": round((passed / total * 100.0) if total > 0 else 0.0, 2),
            "fatal_errors": fatal_count,
            "duplicate_codes_count": len(duplicates),
            "duplicate_codes": duplicates,
            "total_warnings": warning_count,
            "products_with_warnings_count": len(all_warnings),
            "products_per_group": group_counts,
            "quality_metrics": {
                "avg_energy_difference_pct": round(avg_energy_diff, 2),
                "avg_proximate_sum_grams": round(avg_prox_sum, 2),
            },
            "warnings_sample": all_warnings[:30],
        }

        return report


if __name__ == "__main__":
    import sys
    from .table_extractor import extract_all_products
    sys.stdout.reconfigure(encoding="utf-8")
    products = extract_all_products()
    validator = SkurikhinValidator()
    report = validator.validate_dataset(products)
    print("\n" + "="*50)
    print("SKURIKHIN DATASET VALIDATION REPORT")
    print("="*50)
    print(f"Total Products:         {report['total_products']}")
    print(f"Passed Quality Gate:    {report['passed_products']} ({report['pass_rate_pct']}%)")
    print(f"Fatal Errors:           {report['fatal_errors']}")
    print(f"Duplicate Codes:        {report['duplicate_codes_count']}")
    print(f"Avg Energy Delta:       {report['quality_metrics']['avg_energy_difference_pct']}%")
    print(f"Avg Proximate Mass:     {report['quality_metrics']['avg_proximate_sum_grams']}g")
    print("="*50)

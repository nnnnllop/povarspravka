"""Macronutrient validation engine for USDA FoodData Central."""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

from .config import (
    ATWATER_TOLERANCE_PCT,
    MAX_CALORIES,
    MAX_MACRO_SUM,
    MAX_MACRO_VALUE,
)


@dataclass
class ValidationResult:
    is_valid: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    macros: dict[str, float] = field(default_factory=dict)
    all_nutrients: dict[str, float] = field(default_factory=dict)


def extract_nutrient_dict_legacy(food: dict[str, Any]) -> dict[str, float]:
    """Extract mapping of nutrient_number -> amount from foodNutrients list (legacy support)."""
    nutrients: dict[str, float] = {}
    for item in food.get("foodNutrients", []):
        nut = item.get("nutrient") or {}
        num = str(nut.get("number") or item.get("nutrientNumber") or "")
        amount = item.get("amount")
        if amount is None:
            continue
        try:
            val = float(amount)
            if math.isfinite(val) and val >= 0.0:
                nutrients[num] = val
        except (ValueError, TypeError):
            continue
    return nutrients


def validate_food_item(food: dict[str, Any]) -> ValidationResult:
    """Validate a single USDA food item against macronutrient limits.

    Checks:
      1. Presence of fdcId/fdc_id and non-empty description.
      2. Presence of all 4 core macronutrients: protein, fat, carbs, kcal.
      3. Bounds [0.0, 100.0] for individual macronutrients per 100g.
      4. Bounds [0.0, 950.0] for energy in kcal per 100g.
      5. Macro sum <= 105.0g (allows analytical tolerance).
      6. Plausibility check against Atwater formula (4P + 9F + 4C + 7Alc).
    """
    errors: list[str] = []
    warnings: list[str] = []

    # 1. Identity & description check
    fdc_id = food.get("fdc_id") if "fdc_id" in food else food.get("fdcId")
    if fdc_id is None:
        return ValidationResult(is_valid=False, errors=["Missing fdcId"])
    try:
        int_id = int(fdc_id)
        if int_id <= 0:
            return ValidationResult(is_valid=False, errors=[f"Invalid fdcId: {fdc_id}"])
    except (ValueError, TypeError):
        return ValidationResult(is_valid=False, errors=[f"Non-integer fdcId: {fdc_id}"])

    desc = str(food.get("description") or "").strip()
    if not desc:
        return ValidationResult(is_valid=False, errors=["Empty description"])

    # Extract nutrients (supports both structured dict and raw foodNutrients list)
    nutrients: dict[str, float] = dict(food.get("all_nutrients", {}))

    # Check if we have direct macro fields or need to extract from foodNutrients
    if "protein" in food:
        protein = float(food.get("protein") or 0.0)
        fat = float(food.get("fat") or 0.0)
        carbs = float(food.get("carbs") or 0.0)
        kcal = float(food.get("kcal") or 0.0)
        water = float(food["water"]) if food.get("water") is not None else None
        fiber = float(food["fiber"]) if food.get("fiber") is not None else None
        alcohol = float(food.get("alcohol") or 0.0)
    else:
        # Legacy foodNutrients extraction
        raw_nuts = extract_nutrient_dict_legacy(food)
        if "203" not in raw_nuts:
            errors.append("Missing core macronutrient: protein (code 203)")
        if "204" not in raw_nuts:
            errors.append("Missing core macronutrient: fat (code 204)")
        if "205" not in raw_nuts:
            errors.append("Missing core macronutrient: carbs (code 205)")
        if "208" not in raw_nuts:
            errors.append("Missing core macronutrient: energy (code 208)")

        if errors:
            return ValidationResult(is_valid=False, errors=errors, all_nutrients=raw_nuts)

        protein = raw_nuts["203"]
        fat = raw_nuts["204"]
        carbs = raw_nuts["205"]
        kcal = raw_nuts["208"]
        water = raw_nuts.get("255")
        fiber = raw_nuts.get("291")
        alcohol = raw_nuts.get("221", 0.0)
        nutrients = raw_nuts

    # If kcal is 0 or missing but macros exist, impute via Atwater
    if kcal <= 0.0 and (protein > 0 or fat > 0 or carbs > 0):
        calc_kcal = round((4.0 * protein) + (9.0 * fat) + (4.0 * carbs) + (7.0 * alcohol), 1)
        kcal = calc_kcal
        warnings.append(f"Imputed missing energy using Atwater formula: {calc_kcal} kcal")

    # 3. Value bounds
    if not (0.0 <= protein <= MAX_MACRO_VALUE):
        errors.append(f"Protein value out of bounds [0, {MAX_MACRO_VALUE}]: {protein}")
    if not (0.0 <= fat <= MAX_MACRO_VALUE):
        errors.append(f"Fat value out of bounds [0, {MAX_MACRO_VALUE}]: {fat}")
    if not (0.0 <= carbs <= MAX_MACRO_VALUE):
        errors.append(f"Carbs value out of bounds [0, {MAX_MACRO_VALUE}]: {carbs}")
    if not (0.0 <= kcal <= MAX_CALORIES):
        errors.append(f"Energy value out of bounds [0, {MAX_CALORIES}]: {kcal}")

    if water is not None and not (0.0 <= water <= MAX_MACRO_VALUE):
        errors.append(f"Water value out of bounds [0, {MAX_MACRO_VALUE}]: {water}")
    if fiber is not None and not (0.0 <= fiber <= MAX_MACRO_VALUE):
        errors.append(f"Fiber value out of bounds [0, {MAX_MACRO_VALUE}]: {fiber}")

    # 4. Macro sum check
    macro_sum = protein + fat + carbs
    if macro_sum > MAX_MACRO_SUM:
        errors.append(f"Macro sum exceeds maximum limit {MAX_MACRO_SUM}g: {macro_sum:.2f}g")

    if water is not None and (macro_sum + water) > 112.0:
        warnings.append(f"Total proximate sum (macros + water) is high: {macro_sum + water:.2f}g")

    # 5. Atwater energy plausibility check
    calc_kcal = (4.0 * protein) + (9.0 * fat) + (4.0 * carbs) + (7.0 * alcohol)
    if kcal > 0 and calc_kcal > 0:
        diff = abs(kcal - calc_kcal)
        allowed_diff = max(30.0, calc_kcal * ATWATER_TOLERANCE_PCT)
        if diff > allowed_diff:
            warnings.append(
                f"Energy discrepancy: published {kcal:.1f} kcal vs Atwater {calc_kcal:.1f} kcal (diff: {diff:.1f})"
            )

    is_valid = len(errors) == 0
    macros = {
        "protein": round(protein, 2),
        "fat": round(fat, 2),
        "carbs": round(carbs, 2),
        "kcal": round(kcal, 1),
        "water": round(water, 2) if water is not None else 0.0,
        "fiber": round(fiber, 2) if fiber is not None else 0.0,
        "ash": round(float(food.get("ash") or 0.0), 2),
        "sugars": round(float(food.get("sugars") or 0.0), 2),
        "starch": round(float(food.get("starch") or 0.0), 2),
        "sfa": round(float(food.get("sfa") or 0.0), 2),
        "pufa": round(float(food.get("pufa") or 0.0), 2),
        "chol": round(float(food.get("chol") or 0.0), 2),
        "alcohol": round(float(alcohol), 2),
    }

    return ValidationResult(
        is_valid=is_valid,
        errors=errors,
        warnings=warnings,
        macros=macros,
        all_nutrients=nutrients,
    )


class DatasetValidator:
    """Validator manager tracking dataset validation statistics."""

    def __init__(self) -> None:
        self.total: int = 0
        self.passed: int = 0
        self.rejected: int = 0
        self.warnings_total: int = 0
        self.rejection_reasons: dict[str, int] = {}
        self.warning_reasons: dict[str, int] = {}

    def validate(self, food: dict[str, Any]) -> ValidationResult:
        self.total += 1
        res = validate_food_item(food)
        if res.is_valid:
            self.passed += 1
        else:
            self.rejected += 1
            for err in res.errors:
                key = err.split(":")[0]
                self.rejection_reasons[key] = self.rejection_reasons.get(key, 0) + 1

        for warn in res.warnings:
            self.warnings_total += 1
            wkey = warn.split(":")[0]
            self.warning_reasons[wkey] = self.warning_reasons.get(wkey, 0) + 1

        return res

    def summary(self) -> dict[str, Any]:
        return {
            "total_evaluated": self.total,
            "passed": self.passed,
            "rejected": self.rejected,
            "pass_rate_pct": round(self.passed / self.total * 100, 2) if self.total else 0.0,
            "warnings_total": self.warnings_total,
            "rejection_reasons": self.rejection_reasons,
            "warning_reasons": self.warning_reasons,
        }

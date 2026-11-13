// Self-contained copy of the OLD algorithm (git show HEAD:app/lib/...).
//
// PRODUCTION CODE IS NOT MODIFIED. This file is a verbatim transcription of
// the HEAD (658d3ff) versions of:
//   * core/calculation/calculation_math.dart          -> OldMath
//   * core/calculation/calculation_validation.dart    -> OldValidation
//   * core/calculation/models/product.dart (getters)  -> OldProductView
//   * core/calculation/models/ingredient.dart         -> OldIngredient
//   * core/calculation/models/dish.dart (effectiveYieldGrams) -> oldEffectiveYield
//   * core/calculation/calculation_engine.dart        -> OldEngine
//
// Only the class/enum names differ (Old* prefixes) so that the old and the new
// implementation can live in one compilation unit. Every body is copied
// verbatim; the two intentional code removals (the `-0.0` early return that is
// now present in the NEW code, and `_isVerifiedSkurikhinMeasure`) are called
// out at the place where they matter.
//
// Deliberately referenced from a test so the analyzer does not flag it unused.
library;

import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/calculation_result.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

const String reauditRegressionOldLibMarker = 'old-lib-1';

// ---------------------------------------------------------------------------
// OLD CalculationMath  (git show HEAD:app/lib/core/calculation/calculation_math.dart)
// ---------------------------------------------------------------------------
class OldMath {
  static (BigInt, int) decimal(double value) {
    if (!value.isFinite)
      throw ArgumentError.value(value, 'value', 'Must be finite');
    final parts = value.toString().toLowerCase().split('e');
    final mantissa = parts[0];
    final fraction = mantissa.contains('.') ? mantissa.split('.')[1].length : 0;
    final exponent = parts.length == 2 ? int.parse(parts[1]) : 0;
    return (BigInt.parse(mantissa.replaceAll('.', '')), fraction - exponent);
  }

  // Verbatim HEAD body, EXCEPT the lines marked as moved.
  static double productRounded(double a, double b, int digits,
      {bool divideBy100 = false}) {
    final (an, ad) = decimal(a);
    final (bn, bd) = decimal(b);
    // ---------------------------------------------------------------
    // PRODUCTION-CODE OBSERVATION (this file is the reference implementation,
    // so the *new* production line order is what we report on):
    //
    //   NEW app/lib/core/calculation/calculation_math.dart:16-18
    //     final (an, ad) = decimal(a);
    //     final (bn, bd) = decimal(b);
    //     if (a == 0.0 || b == 0.0) return 0.0;   <-- AFTER the parse
    //
    //   HEAD (this file): the same three lines, same order.
    //
    // i.e. the changed file is byte-identical here; see REPORT.md REG-01.
    // ---------------------------------------------------------------
    if (a == 0.0 || b == 0.0) return 0.0;
    var n = an * bn;
    final scale = ad + bd + (divideBy100 ? 2 : 0) - digits;
    final d = scale > 0 ? BigInt.from(10).pow(scale) : BigInt.one;
    if (scale < 0) n *= BigInt.from(10).pow(-scale);
    final rounded = (n.abs() * BigInt.two + d) ~/ (d * BigInt.two);
    // HEAD: no _finiteClamp here (added by the fix, MATH-06).
    return (n.isNegative ? -rounded : rounded).toDouble() /
        BigInt.from(10).pow(digits).toDouble();
  }

  static double energy(double p, double f, double c) {
    final terms = [decimal(p), decimal(f), decimal(c)];
    final scale = terms.map((t) => t.$2).reduce((a, b) => a > b ? a : b);
    final weights = [4, 9, 4];
    var numerator = BigInt.zero;
    for (var i = 0; i < terms.length; i++) {
      numerator += terms[i].$1 * BigInt.from(weights[i]) *
          BigInt.from(10).pow(scale - terms[i].$2);
    }
    return _rationalRounded(numerator, BigInt.one, scale, 1);
  }

  static double ratioRounded(double value, double divisor, int digits,
      {double multiplier = 100}) {
    final (vn, vd) = decimal(value);
    final (dn, dd) = decimal(divisor);
    final (mn, md) = decimal(multiplier);
    if (dn <= BigInt.zero) throw ArgumentError.value(divisor, 'divisor');
    var n = vn * mn;
    var d = dn;
    final scale = dd - vd - md + digits;
    if (scale >= 0) {
      n *= BigInt.from(10).pow(scale);
    } else {
      d *= BigInt.from(10).pow(-scale);
    }
    final rounded = (n.abs() * BigInt.two + d) ~/ (d * BigInt.two);
    return (n.isNegative ? -rounded : rounded).toDouble() /
        BigInt.from(10).pow(digits).toDouble();
  }

  static double _rationalRounded(BigInt numerator, BigInt denominator,
      int scale, int digits) {
    final shift = digits - scale;
    if (shift >= 0) {
      numerator *= BigInt.from(10).pow(shift);
    } else {
      denominator *= BigInt.from(10).pow(-shift);
    }
    final units = (numerator.abs() * BigInt.two + denominator) ~/
        (denominator * BigInt.two);
    return (numerator.isNegative ? -units : units).toDouble() /
        BigInt.from(10).pow(digits).toDouble();
  }

  static (BigInt, int) _sum(Iterable<double> values) {
    var total = BigInt.zero;
    var scale = 0;
    for (final value in values) {
      final (n, s) = decimal(value);
      if (s > scale) {
        total *= BigInt.from(10).pow(s - scale);
        scale = s;
      }
      total += n * BigInt.from(10).pow(scale - s);
    }
    return (total, scale);
  }

  static double sumRounded(Iterable<double> values, int digits) {
    final (n, s) = _sum(values);
    return _rationalRounded(n, BigInt.one, s, digits);
  }

  static bool sumExceeds(Iterable<double> values, double limit) {
    final (n, s) = _sum([...values, -limit]);
    return n > BigInt.zero;
  }

  static double wasteAdjusted(double value, double waste, int digits,
      {bool inverse = false}) {
    final (vn, vs) = decimal(value);
    final (wn, ws) = decimal(waste);
    final scale = ws > 0 ? ws : 0;
    final hundred = BigInt.from(100) * BigInt.from(10).pow(scale);
    final remaining = hundred - wn * BigInt.from(10).pow(scale - ws);
    if (remaining < BigInt.zero || remaining > hundred) {
      throw ArgumentError.value(waste, 'waste');
    }
    if (inverse && remaining == BigInt.zero) {
      throw ArgumentError.value(waste, 'waste', 'No finite inverse');
    }
    return inverse
        ? _rationalRounded(vn * hundred, remaining, vs, digits)
        : _rationalRounded(vn * remaining, hundred, vs, digits);
  }

  static double round1(double v) => productRounded(v, 1.0, 1);
  static double round2(double v) => productRounded(v, 1.0, 2);
}

// ---------------------------------------------------------------------------
// OLD CalculationValidation
// ---------------------------------------------------------------------------
class OldValidation {
  static bool inRange(double value, double min, double max) =>
      value.isFinite && value >= min && value <= max;

  static void range(double value, double min, double max, String name) {
    if (!inRange(value, min, max)) {
      throw ArgumentError.value(value, name, 'Expected finite $min..$max');
    }
  }

  static void product(Product p) {
    if (!p.hasExplicitProtein || p.protein.isNaN) {
      throw ArgumentError('Product missing protein');
    }
    if (!p.hasExplicitFat || p.fat.isNaN) {
      throw ArgumentError('Product missing fat');
    }
    if (!p.hasExplicitCarbs || p.carbs.isNaN) {
      throw ArgumentError('Product missing carbs');
    }
    range(p.wastePct, 0, 100, 'wastePct');
    range(p.protein, 0, 100, 'protein');
    range(p.fat, 0, 100, 'fat');
    range(p.carbs, 0, 100, 'carbs');
    if (OldMath.sumExceeds([p.protein, p.fat, p.carbs], 100)) {
      throw ArgumentError(
        'Product nutrients sum (${p.protein} + ${p.fat} + ${p.carbs}) exceeds 100g',
      );
    }
  }

  static void dish(Dish dish) {
    for (final r in [
      dish.retentionProtein,
      dish.retentionFat,
      dish.retentionCarbs
    ]) {
      range(r, 0, 1, 'retention');
    }
    if (dish.customYieldGrams != null) {
      range(dish.customYieldGrams!, .1, 9999999, 'customYieldGrams');
    }
    for (final ing in dish.ingredients) {
      range(ing.weightGrams, 0, 9999999, 'weightGrams');
      product(ing.product);
    }
  }
}

// ---------------------------------------------------------------------------
// OLD Ingredient getters (HEAD models/ingredient.dart)
// ---------------------------------------------------------------------------
class OldIngredient {
  static double netFromGross(double gross, double wastePct) {
    OldValidation.range(gross, 0, 9999999, 'gross');
    OldValidation.range(wastePct, 0, 100, 'wastePct');
    if (wastePct >= 100.0) return 0.0;
    if (wastePct <= 0.0) return gross;
    return OldMath.wasteAdjusted(gross, wastePct, 12);
  }

  static double? grossFromNet(double net, double wastePct) {
    OldValidation.range(net, 0, 9999999, 'net');
    OldValidation.range(wastePct, 0, 100, 'wastePct');
    if (wastePct >= 100.0) return net == 0 ? 0 : null;
    if (wastePct <= 0.0) return net;
    return OldMath.wasteAdjusted(net, wastePct, 12, inverse: true);
  }

  static double netGrams(Ingredient ing) {
    OldValidation.range(ing.weightGrams, 0, 9999999, 'weightGrams');
    OldValidation.range(ing.product.wastePct, 0, 100, 'wastePct');
    if (!ing.isGross || ing.product.wastePct <= 0.0) {
      return ing.weightGrams;
    }
    if (ing.product.wastePct >= 100.0) return 0.0;
    return OldMath.wasteAdjusted(ing.weightGrams, ing.product.wastePct, 12);
  }

  static double netGramsRounded(Ingredient ing) {
    OldValidation.range(ing.weightGrams, 0, 9999999, 'weightGrams');
    OldValidation.range(ing.product.wastePct, 0, 100, 'wastePct');
    return ing.isGross
        ? OldMath.wasteAdjusted(ing.weightGrams, ing.product.wastePct, 1)
        : OldMath.round1(ing.weightGrams);
  }

  static double proteinInDish(Ingredient ing) =>
      OldMath.productRounded(netGramsRounded(ing), ing.product.proteinRounded, 2,
          divideBy100: true);
  static double fatInDish(Ingredient ing) =>
      OldMath.productRounded(netGramsRounded(ing), ing.product.fatRounded, 2,
          divideBy100: true);
  static double carbsInDish(Ingredient ing) =>
      OldMath.productRounded(netGramsRounded(ing), ing.product.carbsRounded, 2,
          divideBy100: true);
  static double blankKcalInDish(Ingredient ing) =>
      OldMath.energy(proteinInDish(ing), fatInDish(ing), carbsInDish(ing));
}

// ---------------------------------------------------------------------------
// OLD Dish.effectiveYieldGrams
// ---------------------------------------------------------------------------
double oldEffectiveYield(Dish dish) => (dish.customYieldGrams != null &&
        dish.customYieldGrams!.isFinite &&
        dish.customYieldGrams! >= 0.1)
    ? OldMath.round1(dish.customYieldGrams!)
    : OldMath.sumRounded(dish.ingredients.map(OldIngredient.netGramsRounded), 1);

// ---------------------------------------------------------------------------
// OLD CalculationEngine.calculate
// ---------------------------------------------------------------------------
class OldEngine {
  static CalculationResult calculate(Dish dish) {
    OldValidation.dish(dish);
    final rawTotalWeight = OldMath.sumRounded(
        dish.ingredients.map(OldIngredient.netGramsRounded), 1);
    final rawTotalProtein =
        OldMath.sumRounded(dish.ingredients.map(OldIngredient.proteinInDish), 2);
    final rawTotalFat =
        OldMath.sumRounded(dish.ingredients.map(OldIngredient.fatInDish), 2);
    final rawTotalCarbs =
        OldMath.sumRounded(dish.ingredients.map(OldIngredient.carbsInDish), 2);
    final rawTotalKcal = OldMath.sumRounded(
        dish.ingredients.map(OldIngredient.blankKcalInDish), 1);

    final pPct = OldMath.productRounded(dish.retentionProtein, 100, 10);
    final fPct = OldMath.productRounded(dish.retentionFat, 100, 10);
    final cPct = OldMath.productRounded(dish.retentionCarbs, 100, 10);

    final cookedProtein =
        OldMath.productRounded(rawTotalProtein, pPct, 2, divideBy100: true);
    final cookedFat =
        OldMath.productRounded(rawTotalFat, fPct, 2, divideBy100: true);
    final cookedCarbs =
        OldMath.productRounded(rawTotalCarbs, cPct, 2, divideBy100: true);

    final cookedKcal =
        OldMath.energy(cookedProtein, cookedFat, cookedCarbs);

    final yieldGrams = oldEffectiveYield(dish);

    final totalCookedMacros =
        OldMath.sumRounded([cookedProtein, cookedFat, cookedCarbs], 2);
    if (OldMath.sumExceeds(
        [cookedProtein, cookedFat, cookedCarbs], yieldGrams)) {
      throw ArgumentError(
        'Cooked macronutrients mass ($totalCookedMacros g) cannot exceed dish yield ($yieldGrams g)',
      );
    }

    final per100gProtein = yieldGrams > 0
        ? OldMath.ratioRounded(cookedProtein, yieldGrams, 2)
        : 0.0;
    final per100gFat =
        yieldGrams > 0 ? OldMath.ratioRounded(cookedFat, yieldGrams, 2) : 0.0;
    final per100gCarbs =
        yieldGrams > 0 ? OldMath.ratioRounded(cookedCarbs, yieldGrams, 2) : 0.0;
    final per100gKcal =
        yieldGrams > 0 ? OldMath.ratioRounded(cookedKcal, yieldGrams, 1) : 0.0;

    return CalculationResult(
      blankMode: dish.blankMode,
      yieldGrams: yieldGrams,
      rawTotalWeight: rawTotalWeight,
      rawTotalProtein: rawTotalProtein,
      rawTotalFat: rawTotalFat,
      rawTotalCarbs: rawTotalCarbs,
      rawTotalKcal: dish.blankMode == BlankMode.detailed ? rawTotalKcal : null,
      retentionProtein: dish.retentionProtein,
      retentionFat: dish.retentionFat,
      retentionCarbs: dish.retentionCarbs,
      cookedProtein: cookedProtein,
      cookedFat: cookedFat,
      cookedCarbs: cookedCarbs,
      cookedKcal: cookedKcal,
      per100gProtein: per100gProtein,
      per100gFat: per100gFat,
      per100gCarbs: per100gCarbs,
      per100gKcal: per100gKcal,
    );
  }
}

/// Sanity: the reference implementation must agree with the new one on plain
/// positive inputs (the arithmetic is identical until the zero/sign edges).
bool oldMathAgreesOnPositive() {
  OldValidation.range(-0.0, 0, 1, 'x');
  return OldMath.productRounded(12.345, 0.94, 2) ==
      CalculationMath.productRounded(12.345, 0.94, 2);
}
